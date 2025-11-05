//
//  StrategyInfoView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/4/25.
//

import SwiftUI
import SwiftData

struct StrategyInfoView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \OptionStrategy.createdAt, order: .reverse) private var strategies: [OptionStrategy]
    
    @State private var showingAddSheet = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if strategies.isEmpty {
                    ContentUnavailableView(
                        "暂无策略",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("点击右上角 + 按钮添加期权策略")
                    )
                } else {
                    ScrollView(.horizontal) {
                        strategiesTable
                            .padding()
                    }
                }
            }
            .navigationTitle("Strategy Info")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("添加策略", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddStrategyView()
            }
        }
    }
    
    private var strategiesTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                tableHeaderCell("股票", width: 80)
                tableHeaderCell("期权类型", width: 90)
                tableHeaderCell("执行日", width: 120)
                tableHeaderCell("执行价", width: 90)
                tableHeaderCell("期权价格", width: 90)
                tableHeaderCell("每股均价", width: 90)
                tableHeaderCell("合同数", width: 80)
                tableHeaderCell("是否行权", width: 90)
                tableHeaderCell("操作", width: 80)
            }
            .background(Color.gray.opacity(0.2))
            
            Divider()
            
            // 数据行
            ForEach(strategies) { strategy in
                HStack(spacing: 0) {
                    tableCell(strategy.symbol, width: 80)
                    tableCell(strategy.optionType.displayName, width: 90)
                    tableCell(formattedDate(strategy.expirationDate), width: 120)
                    tableCell(formatPrice(strategy.strikePrice), width: 90)
                    tableCell(formatPrice(strategy.optionPrice), width: 90)
                    tableCell(formatPrice(strategy.averagePricePerShare), width: 90)
                    tableCell("\(strategy.contracts)", width: 80)
                    tableCell(strategy.exerciseStatus.displayName, width: 90)
                    
                    // 删除按钮
                    Button(role: .destructive) {
                        deleteStrategy(strategy)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .frame(width: 80)
                }
                .background(strategies.firstIndex(where: { $0.id == strategy.id })! % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
                
                Divider()
            }
        }
        .font(.system(.body, design: .rounded))
    }
    
    private func tableHeaderCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.headline)
            .frame(width: width, alignment: .center)
            .padding(.vertical, 12)
    }
    
    private func tableCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .frame(width: width, alignment: .center)
            .padding(.vertical, 12)
            .lineLimit(1)
    }
    
    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
    
    private func deleteStrategy(_ strategy: OptionStrategy) {
        withAnimation {
            modelContext.delete(strategy)
        }
    }
}

#Preview {
    StrategyInfoView()
        .modelContainer(for: OptionStrategy.self, inMemory: true)
}
