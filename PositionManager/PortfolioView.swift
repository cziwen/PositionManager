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
    let id = UUID()
    let symbol: String
    let totalInvestment: Double // 总投资（实际投入的资金/保证金）
    let cashWhenDue: Double // 到期时收到的现金（不管盈亏）
    let profitLoss: Double // 实际盈亏 = Cash When Due - Total Investment
    let profitLossPercentage: Double // 盈亏百分比
    let premium: Double // 期权总收入（权利金）
    let premiumPercentage: Double // 权利金占投资的百分比
    let hasUnlimitedRisk: Bool // 是否有无限风险（Naked Call）
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
            
            // 检查是否有 Naked Call（无限风险）
            let hasNakedCall = symbolStrategies.contains { $0.optionType == .nakedCall }
            
            // 计算 Cash When Due（到期时收到的现金，不管盈亏）
            let cashWhenDue = symbolStrategies.reduce(0.0) { sum, strategy in
                let quantity = Double(strategy.contracts) * 100
                let strikeValue = strategy.strikePrice * quantity
                
                switch strategy.exerciseStatus {
                case .yes:
                    // 被行权：实际发生的现金流
                    switch strategy.optionType {
                    case .coveredCall:
                        // Covered Call 被行权：收到执行价
                        // Cash = Strike Price × Quantity
                        return sum + strikeValue
                        
                    case .cashSecuredPut:
                        // Cash-Secured Put 被行权：支付执行价
                        // Cash = -Strike Price × Quantity（支出）
                        return sum - strikeValue
                        
                    case .nakedCall:
                        // Naked Call 被行权：使用实际市场价格计算
                        if let marketPrice = strategy.exerciseMarketPrice {
                            // Cash = -Market Price × Quantity（需要以市价买入股票）
                            return sum - (marketPrice * quantity)
                        } else {
                            // 没有输入市场价格，无法计算
                            return sum
                        }
                        
                    case .nakedPut:
                        // Naked Put 被行权：支付执行价
                        // Cash = -Strike Price × Quantity（需要买入）
                        return sum - strikeValue
                    }
                    
                case .no:
                    // 未被行权：没有额外的现金流（只有之前收到的权利金）
                    return sum
                    
                case .unknown:
                    // 不确定：不计算
                    return sum
                }
            }
            
            // 加上权利金收入（所有策略都会收到权利金）
            let totalCashWhenDue = cashWhenDue + totalPremium
            
            // 计算盈亏（需要考虑未行权时的股票未实现盈亏）
            let profitLoss = symbolStrategies.reduce(0.0) { sum, strategy in
                let quantity = Double(strategy.contracts) * 100
                let premium = strategy.optionPrice * quantity
                
                switch strategy.exerciseStatus {
                case .yes:
                    // 被行权：按实际发生的现金流计算
                    switch strategy.optionType {
                    case .coveredCall:
                        let strikeValue = strategy.strikePrice * quantity
                        let stockCost = strategy.averagePricePerShare * quantity
                        // P/L = Strike Value + Premium - Stock Cost
                        return sum + (strikeValue + premium - stockCost)
                        
                    case .cashSecuredPut:
                        let strikeValue = strategy.strikePrice * quantity
                        // P/L = Premium - Strike Value（最大亏损）
                        return sum + (premium - strikeValue)
                        
                    case .nakedCall:
                        if let marketPrice = strategy.exerciseMarketPrice {
                            let marketValue = marketPrice * quantity
                            // P/L = Premium - Market Value
                            return sum + (premium - marketValue)
                        } else {
                            return sum + premium
                        }
                        
                    case .nakedPut:
                        let strikeValue = strategy.strikePrice * quantity
                        // P/L = Premium - Strike Value（最大亏损）
                        return sum + (premium - strikeValue)
                    }
                    
                case .no:
                    // 未行权：考虑股票的未实现盈亏
                    switch strategy.optionType {
                    case .coveredCall:
                        // Covered Call 未行权：
                        // P/L = (Current Price - Avg Price) × Quantity + Premium
                        // 或者说：P/L = Current Value - (Cost - Premium)
                        if let currentPrice = strategy.currentMarketPrice {
                            let stockCost = strategy.averagePricePerShare * quantity
                            let currentValue = currentPrice * quantity
                            // P/L = (Current Value - Stock Cost) + Premium
                            return sum + ((currentValue - stockCost) + premium)
                        } else {
                            // 没有当前价格，只计算权利金
                            return sum + premium
                        }
                        
                    case .cashSecuredPut, .nakedCall, .nakedPut:
                        // 其他类型未行权：只保留权利金
                        return sum + premium
                    }
                    
                case .unknown:
                    // 不确定：不计算
                    return sum
                }
            }
            
            let profitLossPercentage = totalInvestment > 0 ? (profitLoss / totalInvestment) * 100 : 0
            
            // 计算权利金百分比
            let premiumPercentage = totalInvestment > 0 ? (totalPremium / totalInvestment) * 100 : 0
            
            return PortfolioSummary(
                symbol: symbol,
                totalInvestment: totalInvestment,
                cashWhenDue: totalCashWhenDue,
                profitLoss: profitLoss,
                profitLossPercentage: profitLossPercentage,
                premium: totalPremium,
                premiumPercentage: premiumPercentage,
                hasUnlimitedRisk: hasNakedCall,
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
            case .cashWhenDue:
                comparison = summary1.cashWhenDue < summary2.cashWhenDue
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
    
    private var totalCashWhenDue: Double {
        portfolioSummaries.reduce(0.0) { $0 + $1.cashWhenDue }
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
                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text("Total Investment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatPrice(totalInvestment))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    
                    Divider()
                        .frame(height: 30)
                    
                    VStack(spacing: 4) {
                        Text("Cash When Due")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatPrice(totalCashWhenDue))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                    
                    Divider()
                        .frame(height: 30)
                    
                    VStack(spacing: 4) {
                        Text("Positions")
                            .font(.caption)
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
                    updateSort(to: .cashWhenDue)
                } label: {
                    Label("Cash When Due", systemImage: sortField == .cashWhenDue ? "checkmark" : "")
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
    case cashWhenDue
    case profitLoss
    case profitLossPercentage
    case premium
    case premiumPercentage
    case portfolioDiversity
    
    var displayName: String {
        switch self {
        case .symbol: return "Symbol"
        case .investment: return "Investment"
        case .cashWhenDue: return "Cash When Due"
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
                        
                        // 无限风险警告
                        if summary.hasUnlimitedRisk {
                            Text("⚠️")
                                .font(.title3)
                        }
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
                    InfoCell(title: "Cash When Due", value: formatPrice(summary.cashWhenDue), color: .blue)
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
                    
                    if summary.hasUnlimitedRisk {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Contains Unlimited Risk Strategy")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(Capsule())
                    }
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
                        DetailRow(title: "Cash When Due", value: formatPrice(summary.cashWhenDue), color: .blue)
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
