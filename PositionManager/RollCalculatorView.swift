//
//  RollCalculatorView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/5/25.
//

import SwiftUI
import SwiftData

struct RollCalculatorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var strategies: [OptionStrategy]
    
    // 输入参数
    @State private var selectedStrategy: OptionStrategy?
    @State private var currentPrice: String = ""
    @State private var newStrike: String = ""
    @State private var newPremium: String = ""
    
    // 显示选择器
    @State private var showingStrategyPicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                // 选择历史策略
                Section {
                    Button {
                        showingStrategyPicker = true
                    } label: {
                        HStack {
                            Text("Select Previous Strategy")
                                .foregroundStyle(.primary)
                            Spacer()
                            if let strategy = selectedStrategy {
                                Text("\(strategy.symbol) - \(strategy.optionType.displayName)")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("None")
                                    .foregroundStyle(.tertiary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("Previous Position")
                } footer: {
                    Text("Select the option strategy you want to roll from")
                }
                
                // 输入参数
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Current Price")
                            Spacer()
                            TextField("0.00", text: $currentPrice)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }
                        
                        if !currentPrice.isEmpty && !currentPrice.isValidPositiveNumber {
                            Text("Please enter a valid positive number")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("New Strike")
                            Spacer()
                            TextField("0.00", text: $newStrike)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }
                        
                        if !newStrike.isEmpty && !newStrike.isValidPositiveNumber {
                            Text("Please enter a valid positive number")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("New Premium")
                            Spacer()
                            TextField("0.00", text: $newPremium)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }
                        
                        if !newPremium.isEmpty && !newPremium.isValidPositiveNumber {
                            Text("Please enter a valid positive number")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("New Position Parameters")
                } footer: {
                    Text("Enter the parameters for the new option you want to sell")
                }
                
                // 计算结果
                if let strategy = selectedStrategy,
                   let calculator = createCalculator() {
                    
                    // 基本信息
                    Section {
                        ResultRow(title: "Avg Cost", value: formatPrice(strategy.averagePricePerShare))
                        ResultRow(title: "Old Premium", value: formatPrice(strategy.optionPrice))
                        ResultRow(title: "Contracts", value: "\(strategy.contracts)")
                    } header: {
                        Text("Position Info")
                    }
                    
                    // 被行权情况
                    Section {
                        ResultRow(
                            title: "P/L",
                            value: formatPrice(calculator.exercisedProfitLoss),
                            valueColor: calculator.exercisedProfitLoss >= 0 ? .green : .red
                        )
                        ResultRow(
                            title: "Return",
                            value: formatPercentage(calculator.exercisedReturn),
                            valueColor: calculator.exercisedReturn >= 0 ? .green : .red
                        )
                    } header: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("If Exercised")
                        }
                    } footer: {
                        Text("Scenario: Your previous option was exercised, stock was called away or put to you")
                    }
                    
                    // 未被行权情况
                    Section {
                        ResultRow(
                            title: "P/L",
                            value: formatPrice(calculator.notExercisedProfitLoss),
                            valueColor: calculator.notExercisedProfitLoss >= 0 ? .green : .red
                        )
                        ResultRow(
                            title: "Return",
                            value: formatPercentage(calculator.notExercisedReturn),
                            valueColor: calculator.notExercisedReturn >= 0 ? .green : .red
                        )
                    } header: {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("If Not Exercised")
                        }
                    } footer: {
                        Text("Scenario: Your previous option expired worthless, you still hold the position")
                    }
                    
                    // 详细说明
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("📊 How This Works")
                                .font(.headline)
                            
                            Text("**If Exercised:** Calculates P/L based on your old strike price (where stock was assigned) plus both premiums.")
                                .font(.subheadline)
                            
                            Text("**If Not Exercised:** Calculates P/L based on the new strike price plus both premiums.")
                                .font(.subheadline)
                            
                            Text("Use this to decide if the new strike and premium make sense for your rolling strategy.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("About This Calculator")
                    }
                }
            }
            .navigationTitle("Roll Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingStrategyPicker) {
                StrategyPickerView(
                    strategies: strategies,
                    selectedStrategy: $selectedStrategy
                )
            }
        }
    }
    
    // 创建计算器
    private func createCalculator() -> RollCalculator? {
        guard let strategy = selectedStrategy,
              let currentPriceValue = Double(currentPrice),
              let newStrikeValue = Double(newStrike),
              let newPremiumValue = Double(newPremium) else {
            return nil
        }
        
        return RollCalculator(
            strategy: strategy,
            currentPrice: currentPriceValue,
            newStrike: newStrikeValue,
            newPremium: newPremiumValue
        )
    }
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
    
    private func formatPercentage(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }
}

// MARK: - Result Row Component
struct ResultRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - Strategy Picker View
struct StrategyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let strategies: [OptionStrategy]
    @Binding var selectedStrategy: OptionStrategy?
    
    var body: some View {
        NavigationStack {
            List {
                if strategies.isEmpty {
                    ContentUnavailableView(
                        "No Strategies",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Add some option strategies first")
                    )
                } else {
                    ForEach(strategies) { strategy in
                        Button {
                            selectedStrategy = strategy
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(strategy.symbol)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    
                                    HStack {
                                        Text(strategy.optionType.displayName)
                                        Text("•")
                                        Text(formatPrice(strategy.strikePrice))
                                        Text("•")
                                        Text(formattedDate(strategy.expirationDate))
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if let selected = selectedStrategy,
                                   selected.id == strategy.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Strategy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
    
    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Roll Calculator Logic
struct RollCalculator {
    let strategy: OptionStrategy
    let currentPrice: Double
    let newStrike: Double
    let newPremium: Double
    
    // 每张合约的股数
    private let sharesPerContract: Double = 100
    
    // 总股数
    private var totalShares: Double {
        Double(strategy.contracts) * sharesPerContract
    }
    
    // 总的旧权利金收入
    private var totalOldPremium: Double {
        strategy.optionPrice * Double(strategy.contracts) * sharesPerContract
    }
    
    // 总的新权利金收入
    private var totalNewPremium: Double {
        newPremium * Double(strategy.contracts) * sharesPerContract
    }
    
    // 总权利金收入
    private var totalPremium: Double {
        totalOldPremium + totalNewPremium
    }
    
    // 情况1：被行权的盈亏
    // Call: 股票在旧的 strike 被卖出
    // Put: 股票在旧的 strike 被买入
    var exercisedProfitLoss: Double {
        if strategy.optionType.isCall {
            // Covered Call 或 Naked Call 被行权：股票在 old strike 卖出
            // 收益 = (old strike - avg cost) * shares + total premium
            return (strategy.strikePrice - strategy.averagePricePerShare) * totalShares + totalPremium
        } else {
            // Cash-Secured Put 或 Naked Put 被行权：股票在 old strike 买入
            // 成本 = old strike * shares
            // 如果之后在 new strike 卖出
            // 收益 = (new strike - old strike) * shares + total premium
            return (newStrike - strategy.strikePrice) * totalShares + totalPremium
        }
    }
    
    // 情况1的收益率
    var exercisedReturn: Double {
        let costBasis: Double
        if strategy.optionType.isCall {
            // Covered Call / Naked Call: 成本是原始股票成本
            costBasis = strategy.averagePricePerShare * totalShares
        } else {
            // Cash-Secured Put / Naked Put: 成本是行权时的买入成本
            costBasis = strategy.strikePrice * totalShares
        }
        
        guard costBasis > 0 else { return 0 }
        return exercisedProfitLoss / costBasis
    }
    
    // 情况2：未被行权的盈亏
    // Call: 股票仍持有，可能在新的 strike 被卖出
    // Put: 股票未被 put，现在卖新的 call
    var notExercisedProfitLoss: Double {
        if strategy.optionType.isCall {
            // Covered Call / Naked Call 未被行权：股票仍持有
            // 如果在 new strike 卖出
            // 收益 = (new strike - avg cost) * shares + total premium
            return (newStrike - strategy.averagePricePerShare) * totalShares + totalPremium
        } else {
            // Cash-Secured Put / Naked Put 未被行权：没有买入股票
            // 现在卖 Call，假设在当前价格买入再在 new strike 卖出
            // 收益 = (new strike - current price) * shares + total premium
            return (newStrike - currentPrice) * totalShares + totalPremium
        }
    }
    
    // 情况2的收益率
    var notExercisedReturn: Double {
        let costBasis: Double
        if strategy.optionType.isCall {
            // Covered Call / Naked Call 未行权：成本仍是原始股票成本
            costBasis = strategy.averagePricePerShare * totalShares
        } else {
            // Cash-Secured Put / Naked Put 未行权：假设现在买入的成本
            costBasis = currentPrice * totalShares
        }
        
        guard costBasis > 0 else { return 0 }
        return notExercisedProfitLoss / costBasis
    }
}

#Preview {
    RollCalculatorView()
        .modelContainer(for: OptionStrategy.self, inMemory: true)
}
