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
    let cost: Double // 总成本 (averagePricePerShare * contracts * 100)
    let strikeProfit: Double // 行权利润（总是计算）
    let strikeProfitPercentage: Double // 行权利润百分比
    let premium: Double // 期权总收入
    let premiumPercentage: Double // 期权收入百分比
    let cashReceivedWhenDue: Double // 到期时实际收到的现金（根据 exercise 状态）
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
            
            // 计算总成本
            let totalCost = symbolStrategies.reduce(0.0) { sum, strategy in
                sum + (strategy.averagePricePerShare * Double(strategy.contracts) * 100)
            }
            
            // 计算总期权收入
            let totalPremium = symbolStrategies.reduce(0.0) { sum, strategy in
                sum + (strategy.optionPrice * Double(strategy.contracts) * 100)
            }
            
            // 计算总 Strike Profit（总是计算，不管 exercise 状态）
            // Formula: Strike Price + Premium - Cost
            let totalStrikeProfit = symbolStrategies.reduce(0.0) { sum, strategy in
                let cost = strategy.averagePricePerShare * Double(strategy.contracts) * 100
                let premium = strategy.optionPrice * Double(strategy.contracts) * 100
                let strikeValue = strategy.strikePrice * Double(strategy.contracts) * 100
                
                let profit = strikeValue + premium - cost
                
                return sum + profit
            }
            
            // 计算 Cash Received When Due（根据 exercise 状态决定）
            let cashReceivedWhenDue = symbolStrategies.reduce(0.0) { sum, strategy in
                switch strategy.exerciseStatus {
                case .yes:
                    // Formula: Strike Price + Premium - Cost
                    let cost = strategy.averagePricePerShare * Double(strategy.contracts) * 100
                    let premium = strategy.optionPrice * Double(strategy.contracts) * 100
                    let strikeValue = strategy.strikePrice * Double(strategy.contracts) * 100
                    let profit = strikeValue + premium - cost
                    return sum + profit
                    
                case .no:
                    // 只计算 premium
                    let premium = strategy.optionPrice * Double(strategy.contracts) * 100
                    return sum + premium
                    
                case .unknown:
                    // 不计算
                    return sum
                }
            }
            
            // 计算百分比
            let strikeProfitPercentage = totalCost > 0 ? (totalStrikeProfit / totalCost) * 100 : 0
            let premiumPercentage = totalCost > 0 ? (totalPremium / totalCost) * 100 : 0
            
            return PortfolioSummary(
                symbol: symbol,
                cost: totalCost,
                strikeProfit: totalStrikeProfit,
                strikeProfitPercentage: strikeProfitPercentage,
                premium: totalPremium,
                premiumPercentage: premiumPercentage,
                cashReceivedWhenDue: cashReceivedWhenDue,
                strategies: symbolStrategies  // 传递该 symbol 在选定日期的策略
            )
        }
        
        // 计算总成本用于 Portfolio Diversity
        let totalPortfolioCost = summaries.reduce(0.0) { $0 + $1.cost }
        
        // 更新每个 summary 的 Portfolio Diversity
        summaries = summaries.map { summary in
            var updated = summary
            updated.portfolioDiversity = totalPortfolioCost > 0 ? (summary.cost / totalPortfolioCost) * 100 : 0
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
            case .cost:
                comparison = summary1.cost < summary2.cost
            case .strikeProfit:
                comparison = summary1.strikeProfit < summary2.strikeProfit
            case .strikeProfitPercentage:
                comparison = summary1.strikeProfitPercentage < summary2.strikeProfitPercentage
            case .premium:
                comparison = summary1.premium < summary2.premium
            case .premiumPercentage:
                comparison = summary1.premiumPercentage < summary2.premiumPercentage
            case .portfolioDiversity:
                comparison = summary1.portfolioDiversity < summary2.portfolioDiversity
            case .cashReceivedWhenDue:
                comparison = summary1.cashReceivedWhenDue < summary2.cashReceivedWhenDue
            }
            return sortOrder == .ascending ? comparison : !comparison
        }
    }
    
    // 计算总值
    private var totalCashReceivedWhenDue: Double {
        portfolioSummaries.reduce(0.0) { $0 + $1.cashReceivedWhenDue }
    }
    
    private var totalCost: Double {
        portfolioSummaries.reduce(0.0) { $0 + $1.cost }
    }
    
    private var totalReturn: Double {
        totalCost > 0 ? (totalCashReceivedWhenDue / totalCost) * 100 : 0
    }
    
    var body: some View {
        NavigationStack {
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
                                    NavigationLink(destination: PortfolioDetailView(summary: summary)) {
                                        PortfolioCard(summary: summary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Portfolio")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search by symbol"
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.characters)
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
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Cash When Due")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let date = selectedExpirationDate {
                    Text("on \(formatDate(date))")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            
            Text(formatPrice(totalCashReceivedWhenDue))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(totalCashReceivedWhenDue >= 0 ? .green : .red)
            
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("Total Cost")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatPrice(totalCost))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack(spacing: 4) {
                    Text("Total Return")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatPercentage(totalReturn))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(totalReturn >= 0 ? .green : .red)
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
                    updateSort(to: .cost)
                } label: {
                    Label("Cost", systemImage: sortField == .cost ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .strikeProfit)
                } label: {
                    Label("Strike Profit", systemImage: sortField == .strikeProfit ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .premium)
                } label: {
                    Label("Premium", systemImage: sortField == .premium ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .cashReceivedWhenDue)
                } label: {
                    Label("Cash Received When Due", systemImage: sortField == .cashReceivedWhenDue ? "checkmark" : "")
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
    case cost
    case strikeProfit
    case strikeProfitPercentage
    case premium
    case premiumPercentage
    case portfolioDiversity
    case cashReceivedWhenDue
    
    var displayName: String {
        switch self {
        case .symbol: return "Symbol"
        case .cost: return "Cost"
        case .strikeProfit: return "Strike Profit"
        case .strikeProfitPercentage: return "Strike Profit %"
        case .premium: return "Premium"
        case .premiumPercentage: return "Premium %"
        case .portfolioDiversity: return "Diversity"
        case .cashReceivedWhenDue: return "Cash When Due"
        }
    }
}

// MARK: - Portfolio Card
struct PortfolioCard: View {
    let summary: PortfolioSummary
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.symbol)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    
                    Text("\(summary.strategies.count) \(summary.strategies.count == 1 ? "Strategy" : "Strategies")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatPrice(summary.cashReceivedWhenDue))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(summary.cashReceivedWhenDue >= 0 ? .green : .red)
                    
                    Text("Cash When Due")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            
            Divider()
            
            // 详细信息网格
            VStack(spacing: 0) {
                // 第一行
                HStack(spacing: 0) {
                    InfoCell(title: "Cost", value: formatPrice(summary.cost))
                    Divider()
                    InfoCell(title: "Strike Profit", value: formatPrice(summary.strikeProfit))
                }
                
                Divider()
                
                // 第二行
                HStack(spacing: 0) {
                    InfoCell(title: "Strike Profit %", value: formatPercentage(summary.strikeProfitPercentage))
                    Divider()
                    InfoCell(title: "Premium", value: formatPrice(summary.premium))
                }
                
                Divider()
                
                // 第三行
                HStack(spacing: 0) {
                    InfoCell(title: "Premium %", value: formatPercentage(summary.premiumPercentage))
                    Divider()
                    InfoCell(title: "Portfolio Diversity", value: formatPercentage(summary.portfolioDiversity))
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 汇总信息
                VStack(spacing: 12) {
                    Text(summary.symbol)
                        .font(.largeTitle.bold())
                    
                    Text(formatPrice(summary.cashReceivedWhenDue))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(summary.cashReceivedWhenDue >= 0 ? .green : .red)
                    
                    Text("Total Cash Received When Due")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                
                // 详细统计
                VStack(spacing: 0) {
                    DetailRow(title: "Cost", value: formatPrice(summary.cost))
                    Divider()
                    DetailRow(title: "Strike Profit", value: formatPrice(summary.strikeProfit))
                    Divider()
                    DetailRow(title: "Strike Profit %", value: formatPercentage(summary.strikeProfitPercentage))
                    Divider()
                    DetailRow(title: "Premium", value: formatPrice(summary.premium))
                    Divider()
                    DetailRow(title: "Premium %", value: formatPercentage(summary.premiumPercentage))
                    Divider()
                    DetailRow(title: "Portfolio Diversity", value: formatPercentage(summary.portfolioDiversity))
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                
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
}

// MARK: - Detail Row
struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
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
