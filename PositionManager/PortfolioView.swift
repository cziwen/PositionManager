//
//  PortfolioView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/4/25.
//

import SwiftUI
import SwiftData

// MARK: - Portfolio Summary Model
struct PortfolioSummary: Identifiable {
    // 使用 symbol 作为稳定的 ID，避免每次重新计算时生成新的 UUID
    var id: String { symbol }
    let symbol: String
    let totalInvestment: Double // 总投资（实际投入的资金/保证金）
    let finalSettlementCash: Double // 最终结算现金（包含保证金成本和盈亏）
    let profitLoss: Double // 实际盈亏 = Final Settlement Cash - Total Investment
    let profitLossPercentage: Double // 盈亏百分比
    let premium: Double // 期权总收入（权利金）
    let premiumPercentage: Double // 权利金占投资的百分比
    let strategies: [OptionStrategy] // 该 symbol 的所有策略
    
    // 计算 Portfolio Diversity (占总投资组合的比例)
    var portfolioDiversity: Double = 0.0
}

// MARK: - Portfolio View
struct PortfolioView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allStrategies: [OptionStrategy]
    
    @State private var searchText: String = ""
    @State private var sortField: PortfolioSortField = .symbol
    @State private var sortOrder: SortOrder = .ascending
    @State private var selectedExpirationDate: Date? = nil
    @State private var showingDatePicker: Bool = false
    
    // 获取所有唯一的执行日期
    private var availableExpirationDates: [Date] {
        let dates = allStrategies.map { $0.expirationDate }
        let uniqueDates = Set(dates.map { Calendar.current.startOfDay(for: $0) })
        return uniqueDates.sorted()
    }
    
    // 根据选择的日期过滤策略
    private var filteredStrategies: [OptionStrategy] {
        guard let selectedDate = selectedExpirationDate else {
            return allStrategies
        }
        
        return allStrategies.filter { strategy in
            Calendar.current.isDate(strategy.expirationDate, inSameDayAs: selectedDate)
        }
    }
    
    // 计算投资组合汇总数据
    private var portfolioSummaries: [PortfolioSummary] {
        // 按 symbol 分组（使用过滤后的策略）
        let groupedStrategies = Dictionary(grouping: filteredStrategies) { $0.symbol }
        
        // 计算每个 symbol 的汇总
        var summaries = groupedStrategies.map { (symbol, symbolStrategies) -> PortfolioSummary in
            // symbolStrategies 是该 symbol 在选定日期（或全部）的策略
            
            // 计算总投资（实际投入的资金/保证金）
            let totalInvestment = symbolStrategies.reduce(0.0) { sum, strategy in
                switch strategy.optionType {
                case .coveredCall:
                    // Covered Call: 股票成本
                    return sum + (strategy.averagePricePerShare * Double(strategy.contracts) * 100)
                    
                case .cashSecuredPut:
                    // Cash-Secured Put: 执行价作为抵押（需要准备的现金）
                    return sum + (strategy.strikePrice * Double(strategy.contracts) * 100)
                    
                case .nakedCall, .nakedPut:
                    // Naked Call/Put: 使用保证金成本
                    return sum + strategy.getMarginCost()
                }
            }
            
            // 计算总期权收入（权利金）
            let totalPremium = symbolStrategies.reduce(0.0) { sum, strategy in
                sum + (strategy.optionPrice * Double(strategy.contracts) * 100)
            }
            
            // 计算 Final Settlement Cash 和 P/L
            // 注意：Final Settlement Cash 是按照您提供的公式计算的现金结算金额
            var totalFinalSettlementCash = 0.0
            var totalProfitLoss = 0.0
            
            for strategy in symbolStrategies {
                let quantity = Double(strategy.contracts) * 100  // N
                let premium = strategy.optionPrice * quantity    // N × P
                let strikeValue = strategy.strikePrice * quantity // N × K
                let stockCost = strategy.averagePricePerShare * quantity // N × S₀
                
                switch strategy.optionType {
                case .coveredCall:
                    // Covered Call 的 Final Settlement Cash 公式：
                    // 未行权：N × P
                    // 被行权：N(P + K)
                    switch strategy.exerciseStatus {
                    case .yes:
                        // 被行权：Final Settlement Cash = N(P + K)
                        let finalCash = premium + strikeValue
                        totalFinalSettlementCash += finalCash
                        // P/L = Final Cash - Stock Cost
                        totalProfitLoss += finalCash - stockCost
                        
                    case .no:
                        // 未行权：Final Settlement Cash = N × P
                        let finalCash = premium
                        totalFinalSettlementCash += finalCash
                        
                        // P/L 包含股票的未实现盈亏
                        if let currentPrice = strategy.currentMarketPrice {
                            let currentValue = currentPrice * quantity
                            let profitLoss = (currentValue - stockCost) + premium
                            totalProfitLoss += profitLoss
                        } else {
                            // 没有当前价格，只计算权利金
                            totalProfitLoss += premium
                        }
                        
                    case .unknown:
                        break
                    }
                    
                case .cashSecuredPut:
                    // Cash-Secured Put 的 Final Settlement Cash 公式：
                    // 未行权：N × P + Collateral (where Collateral = N × K)
                    // 被行权：N × P
                    let collateral = strikeValue  // N × K
                    
                    switch strategy.exerciseStatus {
                    case .yes:
                        // 被行权：Final Settlement Cash = N × P
                        let finalCash = premium
                        totalFinalSettlementCash += finalCash
                        
                        // P/L 需要考虑购买的股票当前价值
                        if let marketPrice = strategy.exerciseMarketPrice {
                            let marketValue = marketPrice * quantity
                            // 投入 collateral 购买股票，收到 premium，股票价值 marketValue
                            let profitLoss = (marketValue + premium) - collateral
                            totalProfitLoss += profitLoss
                        } else {
                            // 没有市场价格，最坏情况假设股票价值为 0
                            let profitLoss = premium - collateral
                            totalProfitLoss += profitLoss
                        }
                        
                    case .no:
                        // 未行权：Final Settlement Cash = N × P + Collateral
                        let finalCash = premium + collateral
                        totalFinalSettlementCash += finalCash
                        
                        // P/L 只是权利金（抵押品返还）
                        let profitLoss = premium
                        totalProfitLoss += profitLoss
                        
                    case .unknown:
                        break
                    }
                    
                case .nakedCall:
                    let marginCost = strategy.getMarginCost()
                    
                    // Naked Call P/L 公式: P/L = N[P - max(0, S_T - K)]
                    // Final Settlement Cash = margin cost + P/L
                    switch strategy.exerciseStatus {
                    case .yes:
                        // 被行权：使用行权时的市场价格
                        if let price = strategy.exerciseMarketPrice {
                            let profitOrLoss = max(0, price - strategy.strikePrice)
                            let profitLoss = quantity * (strategy.optionPrice - profitOrLoss)
                            let finalCash = marginCost + profitLoss
                            totalFinalSettlementCash += finalCash
                            totalProfitLoss += profitLoss
                        }
                        
                    case .no:
                        // 未行权：使用当前市场价格
                        if let price = strategy.currentMarketPrice {
                            let profitOrLoss = max(0, price - strategy.strikePrice)
                            let profitLoss = quantity * (strategy.optionPrice - profitOrLoss)
                            let finalCash = marginCost + profitLoss
                            totalFinalSettlementCash += finalCash
                            totalProfitLoss += profitLoss
                        } else {
                            // 没有价格，只计算权利金
                            let finalCash = marginCost + premium
                            totalFinalSettlementCash += finalCash
                            totalProfitLoss += premium
                        }
                        
                    case .unknown:
                        // 未知状态：无法计算，跳过
                        break
                    }
                    
                case .nakedPut:
                    let marginCost = strategy.getMarginCost()
                    
                    // Naked Put P/L 公式: P/L = N[P - max(0, K - S_T)]
                    // Final Settlement Cash = margin cost + P/L
                    switch strategy.exerciseStatus {
                    case .yes:
                        // 被行权：使用行权时的市场价格
                        if let price = strategy.exerciseMarketPrice {
                            let profitOrLoss = max(0, strategy.strikePrice - price)
                            let profitLoss = quantity * (strategy.optionPrice - profitOrLoss)
                            let finalCash = marginCost + profitLoss
                            totalFinalSettlementCash += finalCash
                            totalProfitLoss += profitLoss
                        }
                        
                    case .no:
                        // 未行权：使用当前市场价格
                        if let price = strategy.currentMarketPrice {
                            let profitOrLoss = max(0, strategy.strikePrice - price)
                            let profitLoss = quantity * (strategy.optionPrice - profitOrLoss)
                            let finalCash = marginCost + profitLoss
                            totalFinalSettlementCash += finalCash
                            totalProfitLoss += profitLoss
                        } else {
                            // 没有价格，只计算权利金
                            let finalCash = marginCost + premium
                            totalFinalSettlementCash += finalCash
                            totalProfitLoss += premium
                        }
                        
                    case .unknown:
                        // 未知状态：无法计算，跳过
                        break
                    }
                }
            }
            
            let finalSettlementCash = totalFinalSettlementCash
            
            let profitLoss = totalProfitLoss
            let profitLossPercentage = totalInvestment > 0 ? (profitLoss / totalInvestment) * 100 : 0
            
            // 计算权利金百分比
            let premiumPercentage = totalInvestment > 0 ? (totalPremium / totalInvestment) * 100 : 0
            
            return PortfolioSummary(
                symbol: symbol,
                totalInvestment: totalInvestment,
                finalSettlementCash: finalSettlementCash,
                profitLoss: profitLoss,
                profitLossPercentage: profitLossPercentage,
                premium: totalPremium,
                premiumPercentage: premiumPercentage,
                strategies: symbolStrategies
            )
        }
        
        // 计算总投资用于 Portfolio Diversity
        let totalPortfolioInvestment = summaries.reduce(0.0) { $0 + $1.totalInvestment }
        
        // 更新每个 summary 的 Portfolio Diversity
        summaries = summaries.map { summary in
            var updated = summary
            updated.portfolioDiversity = totalPortfolioInvestment > 0 ? (summary.totalInvestment / totalPortfolioInvestment) * 100 : 0
            return updated
        }
        
        // 过滤搜索
        let filtered = searchText.isEmpty ? summaries : summaries.filter { summary in
            summary.symbol.localizedCaseInsensitiveContains(searchText)
        }
        
        // 排序
        return filtered.sorted { summary1, summary2 in
            let comparison: Bool
            switch sortField {
            case .symbol:
                comparison = summary1.symbol.localizedCompare(summary2.symbol) == .orderedAscending
            case .investment:
                comparison = summary1.totalInvestment < summary2.totalInvestment
            case .finalSettlementCash:
                comparison = summary1.finalSettlementCash < summary2.finalSettlementCash
            case .profitLoss:
                comparison = summary1.profitLoss < summary2.profitLoss
            case .profitLossPercentage:
                comparison = summary1.profitLossPercentage < summary2.profitLossPercentage
            case .premium:
                comparison = summary1.premium < summary2.premium
            case .premiumPercentage:
                comparison = summary1.premiumPercentage < summary2.premiumPercentage
            case .portfolioDiversity:
                comparison = summary1.portfolioDiversity < summary2.portfolioDiversity
            }
            return sortOrder == .ascending ? comparison : !comparison
        }
    }
    
    // 计算总值
    private var totalInvestment: Double {
        portfolioSummaries.reduce(0.0) { $0 + $1.totalInvestment }
    }
    
    private var totalFinalSettlementCash: Double {
        portfolioSummaries.reduce(0.0) { $0 + $1.finalSettlementCash }
    }
    
    private var totalProfitLoss: Double {
        portfolioSummaries.reduce(0.0) { $0 + $1.profitLoss }
    }
    
    private var totalProfitLossPercentage: Double {
        totalInvestment > 0 ? (totalProfitLoss / totalInvestment) * 100 : 0
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 自定义搜索栏
                HStack(spacing: 12) {
                    // 搜索框
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        
                        TextField("Search by symbol", text: $searchText)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                
                Divider()
                
                // 主内容区
                Group {
                    if portfolioSummaries.isEmpty {
                        if searchText.isEmpty {
                            ContentUnavailableView(
                                "No Portfolio Data",
                                systemImage: "briefcase",
                                description: Text("Add some strategies in 'My Strategy' to see your portfolio")
                            )
                        } else {
                            ContentUnavailableView.search(text: searchText)
                        }
                    } else {
                        VStack(spacing: 0) {
                            // 日期筛选器
                            dateFilterBar
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.systemGroupedBackground))
                            
                            Divider()
                            
                            // 总览卡片
                            portfolioOverviewCard
                                .padding(.horizontal)
                                .padding(.top, 12)
                                .padding(.bottom, 12)
                                .background(Color(.systemGroupedBackground))
                            
                            Divider()
                            
                            // 排序菜单
                            sortingMenu
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.systemGroupedBackground))
                            
                            Divider()
                            
                            // 投资组合列表
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(portfolioSummaries) { summary in
                                        PortfolioCard(summary: summary)
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Date Filter Bar
    private var dateFilterBar: some View {
        HStack {
            Text("Expiration Date:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Menu {
                Button {
                    selectedExpirationDate = nil
                } label: {
                    HStack {
                        Text("All Dates")
                        if selectedExpirationDate == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Divider()
                
                ForEach(availableExpirationDates, id: \.self) { date in
                    Button {
                        selectedExpirationDate = date
                    } label: {
                        HStack {
                            Text(formatDate(date))
                            if let selected = selectedExpirationDate,
                               Calendar.current.isDate(selected, inSameDayAs: date) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedExpirationDate == nil ? "All Dates" : formatDate(selectedExpirationDate!))
                        .font(.subheadline.weight(.medium))
                    
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.blue)
            }
            
            Spacer()
            
            if selectedExpirationDate != nil {
                Button {
                    withAnimation {
                        selectedExpirationDate = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                }
            }
        }
    }
    
    // MARK: - Portfolio Overview Card
    private var portfolioOverviewCard: some View {
        VStack(spacing: 16) {
            // 主要盈亏显示
            VStack(spacing: 4) {
                Text("Profit / Loss")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let date = selectedExpirationDate {
                    Text("on \(formatDate(date))")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            
            Text(formatPrice(totalProfitLoss))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(totalProfitLoss >= 0 ? .green : .red)
            
            Text(formatPercentage(totalProfitLossPercentage))
                .font(.title3.weight(.semibold))
                .foregroundStyle(totalProfitLoss >= 0 ? .green : .red)
            
            Divider()
                .padding(.vertical, 4)
            
            // 详细数据
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text("Total Investment")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatPrice(totalInvestment))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    
                    Divider()
                        .frame(height: 30)
                    
                    VStack(spacing: 4) {
                        Text("Final Settlement Cash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatPrice(totalFinalSettlementCash))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                    
                    Divider()
                        .frame(height: 30)
                    
                    VStack(spacing: 4) {
                        Text("Positions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(portfolioSummaries.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Sorting Menu
    private var sortingMenu: some View {
        HStack {
            Text("Sort by:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Menu {
                Button {
                    updateSort(to: .symbol)
                } label: {
                    Label("Symbol", systemImage: sortField == .symbol ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .investment)
                } label: {
                    Label("Investment", systemImage: sortField == .investment ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .finalSettlementCash)
                } label: {
                    Label("Final Settlement Cash", systemImage: sortField == .finalSettlementCash ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .profitLoss)
                } label: {
                    Label("Profit/Loss", systemImage: sortField == .profitLoss ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .profitLossPercentage)
                } label: {
                    Label("Profit/Loss %", systemImage: sortField == .profitLossPercentage ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .premium)
                } label: {
                    Label("Premium", systemImage: sortField == .premium ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .portfolioDiversity)
                } label: {
                    Label("Portfolio Diversity", systemImage: sortField == .portfolioDiversity ? "checkmark" : "")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sortField.displayName)
                        .font(.subheadline.weight(.medium))
                    
                    Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
            }
            
            Spacer()
            
            Button {
                sortOrder.toggle()
            } label: {
                Image(systemName: sortOrder == .ascending ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
    
    private func updateSort(to field: PortfolioSortField) {
        if sortField == field {
            sortOrder.toggle()
        } else {
            sortField = field
            sortOrder = .ascending
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
    
    private func formatPercentage(_ percentage: Double) -> String {
        String(format: "%.2f%%", percentage)
    }
    
    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Portfolio Sort Field
enum PortfolioSortField {
    case symbol
    case investment
    case finalSettlementCash
    case profitLoss
    case profitLossPercentage
    case premium
    case premiumPercentage
    case portfolioDiversity
    
    var displayName: String {
        switch self {
        case .symbol: return "Symbol"
        case .investment: return "Investment"
        case .finalSettlementCash: return "Final Settlement Cash"
        case .profitLoss: return "Profit/Loss"
        case .profitLossPercentage: return "Profit/Loss %"
        case .premium: return "Premium"
        case .premiumPercentage: return "Premium %"
        case .portfolioDiversity: return "Diversity"
        }
    }
}

// MARK: - Info Cell
struct InfoCell: View {
    let title: String
    let value: String
    var color: Color = .primary
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Portfolio Card
struct PortfolioCard: View {
    let summary: PortfolioSummary
    @State private var showingDetail = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(summary.symbol)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        
                        // 详情按钮
                        Button {
                            showingDetail = true
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Text("\(summary.strategies.count) \(summary.strategies.count == 1 ? "Strategy" : "Strategies")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatPrice(summary.profitLoss))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(summary.profitLoss >= 0 ? .green : .red)
                    
                    Text(formatPercentage(summary.profitLossPercentage))
                        .font(.caption)
                        .foregroundStyle(summary.profitLoss >= 0 ? .green : .red)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            
            Divider()
            
            // 详细信息网格
            VStack(spacing: 0) {
                // 第一行：投资 vs 到期现金流
                HStack(spacing: 0) {
                    InfoCell(title: "Investment", value: formatPrice(summary.totalInvestment))
                    Divider()
                    InfoCell(title: "Final Settlement Cash", value: formatPrice(summary.finalSettlementCash), color: .blue)
                }
                
                Divider()
                
                // 第二行：权利金相关
                HStack(spacing: 0) {
                    InfoCell(title: "Premium", value: formatPrice(summary.premium))
                    Divider()
                    InfoCell(title: "Premium %", value: formatPercentage(summary.premiumPercentage))
                }
                
                Divider()
                
                // 第三行：Portfolio Diversity
                HStack(spacing: 0) {
                    InfoCell(title: "Portfolio Diversity", value: formatPercentage(summary.portfolioDiversity))
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showingDetail) {
            NavigationStack {
                PortfolioDetailView(summary: summary)
            }
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
    
    private func formatPercentage(_ percentage: Double) -> String {
        String(format: "%.2f%%", percentage)
    }
}

// MARK: - Portfolio Detail View
struct PortfolioDetailView: View {
    let summary: PortfolioSummary
    
    // 按到期日分组策略
    private var strategiesByExpiration: [(date: Date, strategies: [OptionStrategy])] {
        let grouped = Dictionary(grouping: summary.strategies) { strategy in
            Calendar.current.startOfDay(for: strategy.expirationDate)
        }
        
        return grouped.map { (date: $0.key, strategies: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 汇总信息 - 强调盈亏
                VStack(spacing: 12) {
                    Text(summary.symbol)
                        .font(.largeTitle.bold())
                    
                    VStack(spacing: 4) {
                        Text(formatPrice(summary.profitLoss))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(summary.profitLoss >= 0 ? .green : .red)
                        
                        Text(formatPercentage(summary.profitLossPercentage))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(summary.profitLoss >= 0 ? .green : .red)
                    }
                    
                    Text("Profit / Loss")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                
                // 现金流分析卡片
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cash Flow Analysis")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 0) {
                        DetailRow(title: "Total Investment", value: formatPrice(summary.totalInvestment))
                        Divider()
                        DetailRow(title: "Premium Received", value: formatPrice(summary.premium), color: .green)
                        Divider()
                        DetailRow(title: "Final Settlement Cash", value: formatPrice(summary.finalSettlementCash), color: .blue)
                        Divider()
                        DetailRow(title: "Net Profit/Loss", value: formatPrice(summary.profitLoss), color: summary.profitLoss >= 0 ? .green : .red)
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                
                // Payoff Diagram 按钮（按到期日分组）
                if !strategiesByExpiration.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Payoff Diagrams")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(Array(strategiesByExpiration.enumerated()), id: \.element.date) { index, group in
                            NavigationLink {
                                PayoffDiagramView(strategies: group.strategies)
                                    .navigationTitle("Payoff Diagram")
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Expiration: \(formatDate(group.date))")
                                            .font(.subheadline.weight(.medium))
                                        
                                        Text("\(group.strategies.count) \(group.strategies.count == 1 ? "strategy" : "strategies")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chart.xyaxis.line")
                                        .font(.title3)
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // 详细统计
                VStack(alignment: .leading, spacing: 12) {
                    Text("Statistics")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 0) {
                        DetailRow(title: "Premium %", value: formatPercentage(summary.premiumPercentage))
                        Divider()
                        DetailRow(title: "Portfolio Diversity", value: formatPercentage(summary.portfolioDiversity))
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                
                // 策略列表
                VStack(alignment: .leading, spacing: 12) {
                    Text("Strategies (\(summary.strategies.count))")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(summary.strategies) { strategy in
                        StrategyDetailCard(strategy: strategy)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(summary.symbol)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
    
    private func formatPercentage(_ percentage: Double) -> String {
        String(format: "%.2f%%", percentage)
    }
    
    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let title: String
    let value: String
    var color: Color = .primary
    
    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding()
    }
}

// MARK: - Strategy Detail Card
struct StrategyDetailCard: View {
    let strategy: OptionStrategy
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strategy.optionType.displayName)
                    .font(.headline)
                
                Spacer()
                
                Text(strategy.exerciseStatus.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(exerciseStatusColor)
                    .clipShape(Capsule())
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expiration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formattedDate(strategy.expirationDate))
                        .font(.subheadline.weight(.medium))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Strike Price")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatPrice(strategy.strikePrice))
                        .font(.subheadline.weight(.medium))
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Premium")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatPrice(strategy.optionPrice))
                        .font(.subheadline.weight(.medium))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Contracts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(strategy.contracts)")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var exerciseStatusColor: Color {
        switch strategy.exerciseStatus {
        case .yes: return .green
        case .no: return .red
        case .unknown: return .gray
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
}

#Preview {
    PortfolioView()
        .modelContainer(for: OptionStrategy.self, inMemory: true)
}
