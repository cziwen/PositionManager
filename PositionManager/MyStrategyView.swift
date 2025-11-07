//
//  StrategyInfoView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/4/25.
//

import SwiftUI
import SwiftData

// 排序配置
enum SortField {
    case symbol
    case type
    case expiration
    case strike
    case premium
    case avgPrice
    case contracts
    case exercise
}

enum SortOrder {
    case ascending
    case descending
    
    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

struct MyStrategyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allStrategies: [OptionStrategy]
    
    @State private var showingAddSheet = false
    @State private var sortField: SortField = .symbol
    @State private var sortOrder: SortOrder = .ascending
    @State private var strategyToDelete: OptionStrategy?
    @State private var showingDeleteConfirmation = false
    @State private var searchText: String = ""
    @State private var strategyToEdit: OptionStrategy?
    @State private var showingEditSheet = false
    
    // 排序后的策略列表
    private var strategies: [OptionStrategy] {
        // 首先过滤搜索结果
        let filteredStrategies = searchText.isEmpty ? allStrategies : allStrategies.filter { strategy in
            strategy.symbol.localizedCaseInsensitiveContains(searchText)
        }
        
        // 然后排序
        return filteredStrategies.sorted { strategy1, strategy2 in
            let comparison: Bool
            switch sortField {
            case .symbol:
                comparison = strategy1.symbol.localizedCompare(strategy2.symbol) == .orderedAscending
            case .type:
                comparison = strategy1.optionType.rawValue.localizedCompare(strategy2.optionType.rawValue) == .orderedAscending
            case .expiration:
                comparison = strategy1.expirationDate < strategy2.expirationDate
            case .strike:
                comparison = strategy1.strikePrice < strategy2.strikePrice
            case .premium:
                comparison = strategy1.optionPrice < strategy2.optionPrice
            case .avgPrice:
                comparison = strategy1.averagePricePerShare < strategy2.averagePricePerShare
            case .contracts:
                comparison = strategy1.contracts < strategy2.contracts
            case .exercise:
                comparison = strategy1.exerciseStatus.rawValue.localizedCompare(strategy2.exerciseStatus.rawValue) == .orderedAscending
            }
            return sortOrder == .ascending ? comparison : !comparison
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 自定义搜索栏和按钮在同一行
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
                    
                    // 添加按钮
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                
                Divider()
                
                // 主内容区
                Group {
                    if strategies.isEmpty {
                        if searchText.isEmpty {
                            ContentUnavailableView(
                                "No Strategies",
                                systemImage: "chart.line.uptrend.xyaxis",
                                description: Text("Tap the + button to add an option strategy")
                            )
                        } else {
                            ContentUnavailableView.search(text: searchText)
                        }
                    } else {
                        VStack(spacing: 0) {
                            // 排序菜单栏
                            sortingMenu
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.systemGroupedBackground))
                            
                            Divider()
                            
                            // 策略列表
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(strategies) { strategy in
                                        StrategyCard(
                                            strategy: strategy,
                                            onDelete: {
                                                strategyToDelete = strategy
                                                showingDeleteConfirmation = true
                                            },
                                            onEdit: {
                                                strategyToEdit = strategy
                                                showingEditSheet = true
                                            }
                                        )
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAddSheet) {
                AddStrategyView(strategyToEdit: nil)
            }
            .sheet(isPresented: $showingEditSheet) {
                AddStrategyView(strategyToEdit: strategyToEdit)
            }
            .onChange(of: showingEditSheet) { oldValue, newValue in
                if !newValue {
                    // Sheet 被关闭时清理
                    strategyToEdit = nil
                }
            }
            .alert(
                "Delete Option Strategy",
                isPresented: $showingDeleteConfirmation,
                presenting: strategyToDelete
            ) { strategy in
                Button("Delete", role: .destructive) {
                    deleteStrategy(strategy)
                }
                Button("Cancel", role: .cancel) {
                    strategyToDelete = nil
                }
            } message: { strategy in
                Text("Are you sure you want to delete the \(strategy.optionType.displayName) strategy for \(strategy.symbol)?")
            }
        }
    }
    
    // 排序菜单
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
                    updateSort(to: .type)
                } label: {
                    Label("Type", systemImage: sortField == .type ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .expiration)
                } label: {
                    Label("Expiration", systemImage: sortField == .expiration ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .strike)
                } label: {
                    Label("Strike Price", systemImage: sortField == .strike ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .premium)
                } label: {
                    Label("Premium", systemImage: sortField == .premium ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .avgPrice)
                } label: {
                    Label("Avg Price", systemImage: sortField == .avgPrice ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .contracts)
                } label: {
                    Label("Contracts", systemImage: sortField == .contracts ? "checkmark" : "")
                }
                
                Button {
                    updateSort(to: .exercise)
                } label: {
                    Label("Exercise Status", systemImage: sortField == .exercise ? "checkmark" : "")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sortFieldDisplayName)
                        .font(.subheadline.weight(.medium))
                    
                    Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
            }
            
            Spacer()
            
            // 切换排序方向
            Button {
                sortOrder.toggle()
            } label: {
                Image(systemName: sortOrder == .ascending ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
    
    private var sortFieldDisplayName: String {
        switch sortField {
        case .symbol: return "Symbol"
        case .type: return "Type"
        case .expiration: return "Expiration"
        case .strike: return "Strike"
        case .premium: return "Premium"
        case .avgPrice: return "Avg Price"
        case .contracts: return "Contracts"
        case .exercise: return "Exercise"
        }
    }
    
    private func updateSort(to field: SortField) {
        if sortField == field {
            sortOrder.toggle()
        } else {
            sortField = field
            sortOrder = .ascending
        }
    }
    
    private func deleteStrategy(_ strategy: OptionStrategy) {
        withAnimation {
            modelContext.delete(strategy)
        }
    }
}

// MARK: - Strategy Card Component
struct StrategyCard: View {
    let strategy: OptionStrategy
    let onDelete: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(strategy.symbol)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        
                        // 编辑按钮
                        Button(action: onEdit) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Text(strategy.optionType.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // 行权状态标签
                exerciseStatusBadge
                
                // 删除按钮
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            
            Divider()
            
            // 详细信息网格
            VStack(spacing: 0) {
                // 第一行
                HStack(spacing: 0) {
                    StrategyInfoCell(title: "Expiration", value: formattedDate(strategy.expirationDate))
                    Divider()
                    StrategyInfoCell(title: "Strike Price", value: formatPrice(strategy.strikePrice))
                }
                
                Divider()
                
                // 第二行
                HStack(spacing: 0) {
                    StrategyInfoCell(title: "Premium", value: formatPrice(strategy.optionPrice))
                    Divider()
                    StrategyInfoCell(title: "Avg Price", value: formatPrice(strategy.averagePricePerShare))
                }
                
                Divider()
                
                // 第三行
                HStack(spacing: 0) {
                    StrategyInfoCell(title: "Contracts", value: "\(strategy.contracts)")
                    Divider()
                    StrategyInfoCell(title: "Total Value", value: formatPrice(strategy.optionPrice * Double(strategy.contracts) * 100))
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var exerciseStatusBadge: some View {
        Text(strategy.exerciseStatus.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(exerciseStatusColor)
            .clipShape(Capsule())
    }
    
    private var exerciseStatusColor: Color {
        switch strategy.exerciseStatus {
        case .yes:
            return .green
        case .no:
            return .red
        case .unknown:
            return .gray
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
}

// MARK: - Strategy Info Cell Component
struct StrategyInfoCell: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

#Preview {
    MyStrategyView()
        .modelContainer(for: OptionStrategy.self, inMemory: true)
}
