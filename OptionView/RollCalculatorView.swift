//
//  RollCalculatorView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/9/25.
//

import SwiftUI
import SwiftData
import Charts
import UIKit

// MARK: - Roll Calculator View
struct RollCalculatorView: View {
    @Query private var allStrategies: [OptionStrategy]
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedOldStrategy: OptionStrategy?
    @State private var closePrice: Double = 0.0  // 平仓价（买入平仓的成本 per share）
    @State private var contractsToRoll: Int = 1  // 要 roll 的合约数量
    
    @State private var newStrikePrice: Double = 0.0
    @State private var newPremium: Double = 0.0
    
    @State private var selectedPrice: Double?
    @State private var selectedProfit: Double?
    
    // 缓存计算好的图表数据
    @State private var cachedPayoffData: [RollPayoffDataPoint]?
    @State private var cachedXRange: ClosedRange<Double>?
    @State private var cachedMetrics: RollMetrics?
    @State private var isCalculating = false
    
    private var calculator: RollCalculator? {
        guard let oldStrategy = selectedOldStrategy,
              closePrice > 0,
              contractsToRoll > 0,
              contractsToRoll <= oldStrategy.contracts,
              newStrikePrice > 0,
              newPremium > 0 else {
            return nil
        }
        
        return RollCalculator(
            oldStrategy: oldStrategy,
            closePrice: closePrice,
            contractsToRoll: contractsToRoll,
            newStrikePrice: newStrikePrice,
            newPremium: newPremium
        )
    }
    
    private var strategies: [OptionStrategy] {
        // Roll Calculator 只处理卖出策略，过滤掉 Buy Call 和 Buy Put
        allStrategies.filter { strategy in
            strategy.optionType != .buyCall && strategy.optionType != .buyPut
        }
    }
    
    // 异步计算图表数据
    private func calculatePayoffData() {
        guard let calc = calculator else {
            // 如果参数无效，清空缓存
            cachedPayoffData = nil
            cachedXRange = nil
            cachedMetrics = nil
            isCalculating = false
            return
        }
        
        // 如果正在计算，不重复计算
        guard !isCalculating else { return }
        
        isCalculating = true
        
        Task.detached(priority: .userInitiated) {
            // 在后台线程计算数据
            let newData = calc.generatePayoffData()
            
            // 从数据中计算 X 轴范围，避免重复调用 generatePayoffData()
            let newXRange: ClosedRange<Double>? = {
                guard let minDataPrice = newData.map({ $0.stockPrice }).min(),
                      let maxDataPrice = newData.map({ $0.stockPrice }).max() else {
                    return nil
                }
                
                // 使用实际数据范围，左右各留一点缓冲
                let range = maxDataPrice - minDataPrice
                let buffer = max(range * 0.005, minDataPrice * 0.005)  // 0.5% 缓冲
                
                let chartMin = max(0, minDataPrice - buffer)
                let chartMax = maxDataPrice + buffer
                
                return chartMin...chartMax
            }()
            
            // 计算 metrics（使用已生成的数据，避免重复计算）
            let newMetrics = calc.calculateMetrics(from: newData)
            
            await MainActor.run {
                cachedPayoffData = newData
                cachedXRange = newXRange
                cachedMetrics = newMetrics
                isCalculating = false
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 标题和说明
                VStack(spacing: 8) {
                    Text("Roll Calculator")
                        .font(.title2.bold())
                    
                    Text("Calculate payoff when closing a position and opening a new one")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                .padding(.top)
                
                // 输入表单
                VStack(spacing: 20) {
                    // 选择旧仓位
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Old Position", systemImage: "1.circle.fill")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Select Position to Roll")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Picker("Select Strategy", selection: $selectedOldStrategy) {
                                Text("None").tag(nil as OptionStrategy?)
                                ForEach(strategies) { strategy in
                                    Text("\(strategy.symbol) \(strategy.optionType.displayName) @ $\(String(format: "%.0f", strategy.strikePrice))")
                                        .tag(strategy as OptionStrategy?)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selectedOldStrategy) { oldValue, newValue in
                                if let newStrategy = newValue {
                                    // 当选择新策略时，默认 roll 所有合约
                                    contractsToRoll = newStrategy.contracts
                                } else {
                                    // 如果没有选择策略，重置为 1
                                    contractsToRoll = 1
                                }
                            }
                            
                            if let strategy = selectedOldStrategy {
                                VStack(alignment: .leading, spacing: 8) {
                                    StrategyDetailRow(label: "Symbol", value: strategy.symbol)
                                    StrategyDetailRow(label: "Strategy", value: strategy.optionType.displayName)
                                    StrategyDetailRow(label: "Strike", value: "$\(String(format: "%.2f", strategy.strikePrice))")
                                    StrategyDetailRow(label: "Premium", value: "$\(String(format: "%.2f", strategy.optionPrice))")
                                    
                                    // 根据策略类型显示不同的字段
                                    switch strategy.optionType {
                                    case .nakedCall, .nakedPut:
                                        // Naked Call/Put: 显示 Margin Cost
                                        let marginCost = strategy.getMarginCost()
                                        StrategyDetailRow(label: "Margin Cost", value: "$\(String(format: "%.2f", marginCost))")
                                    case .cashSecuredPut:
                                        // Cash-Secured Put: 显示 Cost Basis per Share (strike price)
                                        StrategyDetailRow(label: "Cost Basis per Share", value: "$\(String(format: "%.2f", strategy.strikePrice))")
                                    case .coveredCall:
                                        // Covered Call: 显示 Cost Basis per Share
                                        StrategyDetailRow(label: "Cost Basis per Share", value: "$\(String(format: "%.2f", strategy.averagePricePerShare))")
                                    case .buyCall, .buyPut:
                                        // Buy Call/Put: Roll Calculator 只处理卖出策略
                                        EmptyView()
                                    }
                                    
                                    StrategyDetailRow(label: "Contracts", value: "\(strategy.contracts)")
                                }
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    // 平仓信息
                    if selectedOldStrategy != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Close Position", systemImage: "xmark.circle.fill")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                RollInputRow(
                                    title: "Close Price",
                                    description: "Cost per share to buy-to-close the option",
                                    value: $closePrice
                                )
                                
                                if let oldStrategy = selectedOldStrategy {
                                    Stepper(
                                        "Contracts to Roll: \(contractsToRoll)",
                                        value: $contractsToRoll,
                                        in: 1...oldStrategy.contracts
                                    )
                                    
                                    if contractsToRoll < oldStrategy.contracts {
                                        Text("Note: Rolling \(contractsToRoll) of \(oldStrategy.contracts) contracts")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                
                                if let calc = calculator {
                                    Divider()
                                    
                                    HStack {
                                        Text("Realized P/L from Closing:")
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text("$\(String(format: "%.2f", calc.closeProfitLoss))")
                                            .fontWeight(.bold)
                                            .foregroundStyle(calc.closeProfitLoss >= 0 ? .green : .red)
                                    }
                                    .font(.callout)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    
                    // 新仓位信息
                    if selectedOldStrategy != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("New Position", systemImage: "2.circle.fill")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                RollInputRow(
                                    title: "New Strike Price",
                                    description: "Strike price for the new position",
                                    value: $newStrikePrice
                                )
                                
                                RollInputRow(
                                    title: "New Premium",
                                    description: "Premium to receive per share for new position",
                                    value: $newPremium
                                )
                                
                                if let calc = calculator {
                                    Divider()
                                    
                                    HStack {
                                        Text("New Contracts:")
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text("\(calc.newContracts)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.callout)
                                    
                                    // 根据策略类型显示不同的字段
                                    switch calc.oldStrategy.optionType {
                                    case .nakedCall, .nakedPut:
                                        // Naked Call/Put: 显示提示信息
                                        HStack {
                                            Text("New Margin Cost:")
                                                .fontWeight(.medium)
                                            Spacer()
                                            Text("Check with broker")
                                                .foregroundStyle(.secondary)
                                                .font(.caption)
                                        }
                                        .font(.callout)
                                    case .cashSecuredPut:
                                        // Cash-Secured Put: 显示 New Cost Basis per Share
                                        HStack {
                                            Text("New Cost Basis per Share:")
                                                .fontWeight(.medium)
                                            Spacer()
                                            Text("$\(String(format: "%.2f", calc.newCostBasis))")
                                                .foregroundStyle(.secondary)
                                        }
                                        .font(.callout)
                                    case .coveredCall:
                                        // Covered Call: 显示 New Cost Basis per Share
                                        HStack {
                                            Text("New Cost Basis per Share:")
                                                .fontWeight(.medium)
                                            Spacer()
                                            Text("$\(String(format: "%.2f", calc.newCostBasis))")
                                                .foregroundStyle(.secondary)
                                        }
                                        .font(.callout)
                                    case .buyCall, .buyPut:
                                        // Buy Call/Put: Roll Calculator 只处理卖出策略
                                        EmptyView()
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.horizontal)
                
                // Payoff Diagram
                if let calc = calculator {
                    VStack(spacing: 16) {
                        // 显示图表或加载状态
                        if let data = cachedPayoffData, let xRange = cachedXRange {
                            RollPayoffChartView(
                                data: data,
                                xRange: xRange,
                                selectedPrice: $selectedPrice,
                                selectedProfit: $selectedProfit
                            )
                            .padding()
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        } else if isCalculating {
                            // 加载状态
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Calculating chart data...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        } else {
                            // 数据未准备好（参数可能无效）
                            VStack(spacing: 12) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("Chart will appear when all parameters are entered")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                        
                        // Selected Price Info Card
                        if let price = selectedPrice, let profit = selectedProfit {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Selected Price")
                                    .font(.headline)
                                
                                Divider()
                                
                                HStack {
                                    Text("Stock Price:")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("$\(String(format: "%.2f", price))")
                                        .font(.subheadline.weight(.medium))
                                }
                                
                                HStack {
                                    Text("P/L:")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("$\(String(format: "%.2f", profit))")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(profit >= 0 ? .green : .red)
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                        
                        // Key Metrics Card
                        if let metrics = cachedMetrics {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Key Metrics")
                                    .font(.headline)
                                
                                Divider()
                                
                                RollKeyPointRow(
                                    label: "Max Profit",
                                    value: metrics.maxProfit,
                                    color: .green
                                )
                                
                                Divider()
                                
                                // Max Loss - 对于 naked call 显示特殊文本
                                if metrics.isMaxLossUnlimited {
                                    HStack {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                        Text("Max Loss")
                                        Spacer()
                                        Text("Theoretically Uncapped")
                                            .fontWeight(.medium)
                                            .foregroundStyle(.red)
                                    }
                                } else {
                                    RollKeyPointRow(
                                        label: "Max Loss",
                                        value: metrics.maxLoss,
                                        color: .red
                                    )
                                }
                                
                                Divider()
                                
                                if let breakEven = metrics.breakEvenPrice {
                                    RollKeyPointRow(
                                        label: "Break-Even Point",
                                        value: breakEven,
                                        color: .blue
                                    )
                                } else {
                                    HStack {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 8, height: 8)
                                        Text("Break-Even Point")
                                        Spacer()
                                        Text("N/A")
                                            .fontWeight(.medium)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Roll Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    // 关闭键盘
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onChange(of: selectedOldStrategy) { _, _ in
            calculatePayoffData()
        }
        .onChange(of: closePrice) { _, _ in
            calculatePayoffData()
        }
        .onChange(of: contractsToRoll) { _, _ in
            calculatePayoffData()
        }
        .onChange(of: newStrikePrice) { _, _ in
            calculatePayoffData()
        }
        .onChange(of: newPremium) { _, _ in
            calculatePayoffData()
        }
        .onChange(of: selectedPrice) { oldValue, newValue in
            // 直接计算该价格点的盈亏，避免重新生成所有数据点
            if let price = newValue, let calc = calculator {
                let newPL = calc.calculateNewProfitLoss(at: price)
                let totalPL = calc.closeProfitLoss + newPL
                selectedProfit = totalPL
            } else {
                selectedProfit = nil
            }
        }
        .onAppear {
            // 首次出现时计算数据
            calculatePayoffData()
        }
    }
}

// MARK: - Strategy Detail Row
struct StrategyDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
        }
    }
}

// MARK: - Input Row Component
struct RollInputRow: View {
    let title: String
    let description: String
    @Binding var value: Double
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool
    var onCommit: (() -> Void)? = nil
    
    // 初始化文本值的辅助函数
    private func updateTextValue() {
        if value == 0 {
            textValue = ""
        } else {
            textValue = String(format: "%.2f", value)
        }
    }
    
    // 完成编辑并关闭键盘
    private func commitEditing() {
        // 将文本转换为 Double
        if let doubleValue = Double(textValue) {
            value = doubleValue
        } else if textValue.isEmpty {
            value = 0.0
            textValue = ""
        } else {
            // 如果输入无效，恢复原值
            updateTextValue()
        }
        // 关闭键盘
        isFocused = false
        onCommit?()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                TextField("0.00", text: $textValue)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                    .focused($isFocused)
                    .onAppear {
                        updateTextValue()
                    }
                    .onChange(of: isFocused) { oldValue, newValue in
                        if newValue {
                            // 用户开始编辑时，如果值为 0，清空输入框
                            if value == 0 {
                                textValue = ""
                            }
                        } else {
                            // 用户完成编辑时，将文本转换为 Double（避免循环）
                            if !textValue.isEmpty {
                                if let doubleValue = Double(textValue) {
                                    value = doubleValue
                                } else {
                                    updateTextValue()
                                }
                            } else {
                                value = 0.0
                            }
                        }
                    }
                    .onChange(of: value) { oldValue, newValue in
                        // 当外部值改变时，更新文本（但不在编辑中时）
                        if !isFocused && oldValue != newValue {
                            updateTextValue()
                        }
                    }
            }
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Key Point Row
struct RollKeyPointRow: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
            Spacer()
            Text("$\(String(format: "%.2f", value))")
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Payoff Chart View
struct RollPayoffChartView: View {
    let data: [RollPayoffDataPoint]
    let xRange: ClosedRange<Double>
    @Binding var selectedPrice: Double?
    @Binding var selectedProfit: Double?
    
    var body: some View {
        Chart {
            // Payoff curve - 简化，只用线条
            ForEach(data) { point in
                LineMark(
                    x: .value("Stock Price", point.stockPrice),
                    y: .value("P/L", point.profitLoss)
                )
                .foregroundStyle(.primary)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            
            // Zero line
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            
            // 选中点的标记 - 直接使用 selectedPrice 和 selectedProfit，避免查找数据点
            if let price = selectedPrice, let profit = selectedProfit {
                // 垂直线标记选中的价格
                RuleMark(x: .value("Selected Price", price))
                    .foregroundStyle(.blue.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                
                // 选中的点
                PointMark(
                    x: .value("Stock Price", price),
                    y: .value("P/L", profit)
                )
                .foregroundStyle(.blue)
                .symbolSize(120)
            }
        }
        .chartXSelection(value: $selectedPrice)
        .chartXScale(domain: xRange)
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        // 如果是整数，不显示小数；否则显示一位小数
                        let formattedPrice = abs(price - Double(Int(price))) < 0.0001
                            ? "$\(Int(price))"
                            : "$\(String(format: "%.1f", price))"
                        Text(formattedPrice)
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let pl = value.as(Double.self) {
                        Text("$\(Int(pl))")
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 300)
    }
}

// MARK: - Roll Calculator Model

struct RollCalculator {
    let oldStrategy: OptionStrategy
    let closePrice: Double  // 平仓价（买入平仓的成本 per share）
    let contractsToRoll: Int  // 要 roll 的合约数量
    let newStrikePrice: Double
    let newPremium: Double
    
    /// 新仓位的合约数量（与要 roll 的合约数量相同）
    var newContracts: Int {
        contractsToRoll
    }
    
    /// Calculate P/L from closing the old position
    /// 滚仓只是平仓，不涉及行权，所以只计算期权部分的盈亏
    /// 只计算要 roll 的合约数量的盈亏
    var closeProfitLoss: Double {
        let quantity = Double(contractsToRoll) * 100  // 只计算要 roll 的合约数量
        let originalPremium = oldStrategy.optionPrice * quantity  // 收到的权利金（按比例）
        let closeCost = closePrice * quantity  // 平仓成本（按比例）
        
        // 所有策略类型：平仓 P/L = 收到的权利金 - 平仓成本
        // Covered Call: 股票还在，不计算股票盈亏
        // Cash-Secured Put/Naked: 没有股票，只计算期权盈亏
        return originalPremium - closeCost
    }
    
    /// New position cost basis
    var newCostBasis: Double {
        switch oldStrategy.optionType {
        case .coveredCall:
            // Covered Call: 股票还在，继承原 cost basis
            return oldStrategy.averagePricePerShare
            
        case .cashSecuredPut:
            // Cash-Secured Put: 如果被行权，会以 strike price 买入股票
            // 所以 cost basis 应该是新的 strike price
            return newStrikePrice
            
        case .nakedCall, .nakedPut:
            // 这些策略类型在平仓后没有股票
            // 但 PayoffCalculator 需要 cost basis，对于 naked call，cost basis 概念上不适用，但计算时需要
            // 对于 naked put，使用原值（虽然不会被行权，但 PayoffCalculator 可能需要）
            return oldStrategy.averagePricePerShare
            
        case .buyCall, .buyPut:
            // Buy Call/Put: Roll Calculator 只处理卖出策略，这里不应该被调用
            // 但为了编译通过，返回 0
            return 0
        }
    }
    
    /// Calculate new position P/L at a given stock price
    func calculateNewProfitLoss(at stockPrice: Double) -> Double {
        // 使用 PayoffCalculator 计算新仓位的 payoff
        // 新仓位使用相同的策略类型
        let tempStrategy = OptionStrategy(
            symbol: oldStrategy.symbol,
            optionType: oldStrategy.optionType,  // 保持相同的策略类型
            expirationDate: Date(),
            strikePrice: newStrikePrice,
            optionPrice: newPremium,
            averagePricePerShare: newCostBasis,
            contracts: newContracts
        )
        
        return PayoffCalculator.calculateSingleLegPayoff(strategy: tempStrategy, at: stockPrice)
    }
    
    /// Generate payoff data points
    func generatePayoffData() -> [RollPayoffDataPoint] {
        // 生成价格范围
        let strikes = [oldStrategy.strikePrice, newStrikePrice]
        let minStrike = strikes.min() ?? 0
        let maxStrike = strikes.max() ?? 100
        
        let rangeWidth = maxStrike - minStrike
        let buffer = max(rangeWidth * 0.2, minStrike * 0.2)
        
        let minPrice = max(0, minStrike - buffer)
        let maxPrice = maxStrike + buffer
        let step = (maxPrice - minPrice) / 100
        
        var points: [RollPayoffDataPoint] = []
        
        for i in 0...100 {
            let stockPrice = minPrice + Double(i) * step
            
            // 计算新仓位在这个价格下的 P/L
            let newPL = calculateNewProfitLoss(at: stockPrice)
            
            // 总 P/L = 平仓实现的 P/L + 新仓位在到期时的 P/L
            let totalPL = closeProfitLoss + newPL
            
            points.append(RollPayoffDataPoint(stockPrice: stockPrice, profitLoss: totalPL))
        }
        
        return points
    }
    
    /// Calculate key metrics
    func calculateMetrics() -> RollMetrics {
        let data = generatePayoffData()
        
        // Max profit
        let maxProfit = data.map { $0.profitLoss }.max() ?? 0
        
        // Max loss - 需要考虑边界情况
        var maxLoss = data.map { $0.profitLoss }.min() ?? 0
        var isMaxLossUnlimited = false
        
        // 根据策略类型检查边界情况
        switch oldStrategy.optionType {
        case .nakedCall:
            // Naked Call: 当股价无限上涨时，损失无限大
            // 检查在更高价格时的损失（比如当前最大价格的 10 倍）
            if let maxPrice = data.map({ $0.stockPrice }).max(), maxPrice > 0 {
                let extremePrice = maxPrice * 10
                let extremePL = closeProfitLoss + calculateNewProfitLoss(at: extremePrice)
                maxLoss = min(maxLoss, extremePL)
            }
            // Naked Call 的损失理论上无限（股价可以无限上涨）
            isMaxLossUnlimited = true
            
        case .nakedPut, .cashSecuredPut:
            // Naked Put / Cash-Secured Put: 当股价为 0 时，损失最大
            let plAtZero = closeProfitLoss + calculateNewProfitLoss(at: 0)
            maxLoss = min(maxLoss, plAtZero)
            
        case .coveredCall:
            // Covered Call: 当股价为 0 时，损失最大（股票价值为 0）
            let plAtZero = closeProfitLoss + calculateNewProfitLoss(at: 0)
            maxLoss = min(maxLoss, plAtZero)
            
        case .buyCall, .buyPut:
            // Buy Call/Put: Roll Calculator 只处理卖出策略，这里不应该被调用
            // 但为了编译通过，使用默认处理
            let plAtZero = closeProfitLoss + calculateNewProfitLoss(at: 0)
            maxLoss = min(maxLoss, plAtZero)
        }
        
        // Break-even point - 使用 PayoffMetricsCalculator 计算
        let dataPoints = data.map { (price: $0.stockPrice, profitLoss: $0.profitLoss) }
        let breakEvenPoints = PayoffMetricsCalculator.calculateBreakEvenPoints(from: dataPoints)
        // RollCalculator 只返回第一个 break-even point（与原有逻辑保持一致）
        let breakEvenPrice = breakEvenPoints.first
        
        return RollMetrics(
            maxProfit: maxProfit,
            maxLoss: maxLoss,
            isMaxLossUnlimited: isMaxLossUnlimited,
            breakEvenPrice: breakEvenPrice
        )
    }
    
    /// Calculate key metrics from pre-computed data (avoids regenerating data)
    func calculateMetrics(from data: [RollPayoffDataPoint]) -> RollMetrics {
        // Max profit
        let maxProfit = data.map { $0.profitLoss }.max() ?? 0
        
        // Max loss - 需要考虑边界情况
        var maxLoss = data.map { $0.profitLoss }.min() ?? 0
        var isMaxLossUnlimited = false
        
        // 根据策略类型检查边界情况
        switch oldStrategy.optionType {
        case .nakedCall:
            // Naked Call: 当股价无限上涨时，损失无限大
            // 检查在更高价格时的损失（比如当前最大价格的 10 倍）
            if let maxPrice = data.map({ $0.stockPrice }).max(), maxPrice > 0 {
                let extremePrice = maxPrice * 10
                let extremePL = closeProfitLoss + calculateNewProfitLoss(at: extremePrice)
                maxLoss = min(maxLoss, extremePL)
            }
            // Naked Call 的损失理论上无限（股价可以无限上涨）
            isMaxLossUnlimited = true
            
        case .nakedPut, .cashSecuredPut:
            // Naked Put / Cash-Secured Put: 当股价为 0 时，损失最大
            let plAtZero = closeProfitLoss + calculateNewProfitLoss(at: 0)
            maxLoss = min(maxLoss, plAtZero)
            
        case .coveredCall:
            // Covered Call: 当股价为 0 时，损失最大（股票价值为 0）
            let plAtZero = closeProfitLoss + calculateNewProfitLoss(at: 0)
            maxLoss = min(maxLoss, plAtZero)
            
        case .buyCall, .buyPut:
            // Buy Call/Put: Roll Calculator 只处理卖出策略，这里不应该被调用
            // 但为了编译通过，使用默认处理
            let plAtZero = closeProfitLoss + calculateNewProfitLoss(at: 0)
            maxLoss = min(maxLoss, plAtZero)
        }
        
        // Break-even point - 使用 PayoffMetricsCalculator 计算
        let dataPoints = data.map { (price: $0.stockPrice, profitLoss: $0.profitLoss) }
        let breakEvenPoints = PayoffMetricsCalculator.calculateBreakEvenPoints(from: dataPoints)
        // RollCalculator 只返回第一个 break-even point（与原有逻辑保持一致）
        let breakEvenPrice = breakEvenPoints.first
        
        return RollMetrics(
            maxProfit: maxProfit,
            maxLoss: maxLoss,
            isMaxLossUnlimited: isMaxLossUnlimited,
            breakEvenPrice: breakEvenPrice
        )
    }
    
    /// Key point annotations
    var keyPoints: [RollPayoffAnnotation] {
        let metrics = calculateMetrics()
        var annotations: [RollPayoffAnnotation] = []
        
        // Break-even point
        if let breakEven = metrics.breakEvenPrice, breakEven > 0 {
            let plAtBreakEven = closeProfitLoss + calculateNewProfitLoss(at: breakEven)
            annotations.append(RollPayoffAnnotation(
                stockPrice: breakEven,
                profitLoss: plAtBreakEven,
                label: "Break-Even",
                color: .blue,
                showLabel: true
            ))
        }
        
        // Max profit point - 找到最大利润对应的价格
        let data = generatePayoffData()
        if let maxProfitPoint = data.max(by: { $0.profitLoss < $1.profitLoss }) {
            annotations.append(RollPayoffAnnotation(
                stockPrice: maxProfitPoint.stockPrice,
                profitLoss: maxProfitPoint.profitLoss,
                label: "Max Profit",
                color: .green,
                showLabel: true
            ))
        }
        
        return annotations
    }
    
    /// Calculate X axis range based on actual data range
    var chartXRange: ClosedRange<Double>? {
        let data = generatePayoffData()
        
        // 基于实际数据范围，确保线条能填满整个图表
        guard let minDataPrice = data.map({ $0.stockPrice }).min(),
              let maxDataPrice = data.map({ $0.stockPrice }).max() else {
            return nil
        }
        
        // 使用实际数据范围，左右各留一点缓冲
        let range = maxDataPrice - minDataPrice
        let buffer = max(range * 0.005, minDataPrice * 0.005)  // 0.5% 缓冲
        
        let chartMin = max(0, minDataPrice - buffer)
        let chartMax = maxDataPrice + buffer
        
        return chartMin...chartMax
    }
}

// MARK: - Roll Metrics
struct RollMetrics {
    let maxProfit: Double
    let maxLoss: Double
    let isMaxLossUnlimited: Bool  // 对于 naked call，损失理论上无限
    let breakEvenPrice: Double?
}

// MARK: - Chart Data Models (Roll-specific)
struct RollPayoffDataPoint: Identifiable {
    let id = UUID()
    let stockPrice: Double
    let profitLoss: Double
}

struct RollPayoffAnnotation: Identifiable {
    let id = UUID()
    let stockPrice: Double
    let profitLoss: Double
    let label: String
    let color: Color
    let showLabel: Bool
}

// MARK: - Preview Helper View
private struct PreviewWithSamples: View {
    @State private var container: ModelContainer?
    
    var body: some View {
        Group {
            if let container = container {
                NavigationStack {
                    RollCalculatorView()
                        .modelContainer(container)
                }
            } else {
                ProgressView()
                    .task {
                        await setupContainer()
                    }
            }
        }
    }
    
    @MainActor
    private func setupContainer() async {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let newContainer = try! ModelContainer(for: OptionStrategy.self, configurations: config)
        
        // 添加示例数据 - 每个策略类型各一个
        let sampleStrategies = [
            // Covered Call
            OptionStrategy(
                symbol: "AAPL",
                optionType: .coveredCall,
                expirationDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date(),
                strikePrice: 180,
                optionPrice: 5.5,
                averagePricePerShare: 175,
                contracts: 2
            ),
            // Naked Call
            OptionStrategy(
                symbol: "NVDA",
                optionType: .nakedCall,
                expirationDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date(),
                strikePrice: 500,
                optionPrice: 15.0,
                averagePricePerShare: 480,
                contracts: 1
            ),
            // Cash-Secured Put
            OptionStrategy(
                symbol: "TSLA",
                optionType: .cashSecuredPut,
                expirationDate: Calendar.current.date(byAdding: .day, value: 21, to: Date()) ?? Date(),
                strikePrice: 250,
                optionPrice: 8.5,
                averagePricePerShare: 260,
                contracts: 3
            ),
            // Naked Put
            OptionStrategy(
                symbol: "SPY",
                optionType: .nakedPut,
                expirationDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
                strikePrice: 450,
                optionPrice: 12.0,
                averagePricePerShare: 460,
                contracts: 2
            )
        ]
        
        // 将示例数据插入到 container
        sampleStrategies.forEach { strategy in
            newContainer.mainContext.insert(strategy)
        }
        
        container = newContainer
    }
}

// MARK: - Preview
#Preview {
    PreviewWithSamples()
}
