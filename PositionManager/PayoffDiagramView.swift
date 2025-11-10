//
//  PayoffDiagramView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/6/25.
//

import SwiftUI
import Charts

// MARK: - Payoff Data Models
struct PayoffPoint: Identifiable {
    let id = UUID()
    let underlyingPrice: Double
    let profit: Double
}

struct LegPayoff: Identifiable {
    let id = UUID()
    let strategy: OptionStrategy
    let points: [PayoffPoint]
    
    var displayName: String {
        "\(strategy.optionType.displayName) @ $\(String(format: "%.2f", strategy.strikePrice))"
    }
}

struct TotalPayoff {
    let points: [PayoffPoint]
}

// MARK: - Payoff Calculator
class PayoffCalculator {
    /// 计算单个期权腿的盈亏
    /// - Parameters:
    ///   - strategy: 期权策略
    ///   - underlyingPrice: 标的价格
    /// - Returns: 该价格下的盈亏
    static func calculateSingleLegPayoff(strategy: OptionStrategy, at underlyingPrice: Double) -> Double {
        let premium = strategy.optionPrice * Double(strategy.contracts) * 100
        let quantity = Double(strategy.contracts) * 100
        
        switch strategy.optionType {
        case .coveredCall:
            // Covered Call: 持有股票 + 卖出 Call
            // 股票盈亏：(当前价 - 成本价) * 数量，但收益上限是执行价
            // 期权盈亏：权利金收入 - 期权义务损失
            
            let stockCost = strategy.averagePricePerShare
            
            if underlyingPrice <= strategy.strikePrice {
                // 未被行权：股票盈亏 + 权利金全部保留
                let stockPnL = (underlyingPrice - stockCost) * quantity
                return stockPnL + premium
            } else {
                // 被行权：股票以执行价卖出
                let stockPnL = (strategy.strikePrice - stockCost) * quantity
                return stockPnL + premium
            }
            
        case .nakedCall:
            // Naked Call: 单纯卖出 Call，无股票保护
            // 盈亏：权利金 - max(当前价 - 执行价, 0) * 数量
            let intrinsicValue = max(underlyingPrice - strategy.strikePrice, 0)
            return premium - (intrinsicValue * quantity)
            
        case .cashSecuredPut:
            // Cash-Secured Put: 卖出 Put，准备现金买入股票
            // 如果未被行权：保留全部权利金
            // 如果被行权：以执行价买入，账面盈亏 = (当前价 - 执行价) * 数量 + 权利金
            
            if underlyingPrice >= strategy.strikePrice {
                // 未被行权：保留全部权利金
                return premium
            } else {
                // 被行权：以执行价买入股票，当前市价计算账面盈亏
                let stockPnL = (underlyingPrice - strategy.strikePrice) * quantity
                return stockPnL + premium
            }
            
        case .nakedPut:
            // Naked Put: 单纯卖出 Put
            // 盈亏：权利金 - max(执行价 - 当前价, 0) * 数量
            let intrinsicValue = max(strategy.strikePrice - underlyingPrice, 0)
            return premium - (intrinsicValue * quantity)
        }
    }
    
    /// 生成价格范围
    /// - Parameters:
    ///   - strategies: 期权策略列表
    ///   - steps: 计算点数
    /// - Returns: 价格范围数组
    static func generatePriceRange(for strategies: [OptionStrategy], steps: Int = 100) -> [Double] {
        guard !strategies.isEmpty else { return [] }
        
        let strikes = strategies.map { $0.strikePrice }
        let minStrike = strikes.min() ?? 0
        let maxStrike = strikes.max() ?? 100
        
        // 计算范围：左右各留 20% 空间
        let rangeWidth = maxStrike - minStrike
        let buffer = max(rangeWidth * 0.2, minStrike * 0.2) // 20% 缓冲
        
        let minPrice = max(0, minStrike - buffer)
        let maxPrice = maxStrike + buffer
        
        let step = (maxPrice - minPrice) / Double(steps)
        
        return stride(from: minPrice, through: maxPrice, by: step).map { $0 }
    }
    
    /// 计算所有期权腿的盈亏数据
    /// - Parameter strategies: 期权策略列表
    /// - Returns: 每条腿的盈亏和总盈亏
    static func calculatePayoffData(for strategies: [OptionStrategy]) -> (legs: [LegPayoff], total: TotalPayoff) {
        let priceRange = generatePriceRange(for: strategies, steps: 100)
        
        // 计算每条腿
        let legs = strategies.map { strategy in
            let points = priceRange.map { price in
                PayoffPoint(
                    underlyingPrice: price,
                    profit: calculateSingleLegPayoff(strategy: strategy, at: price)
                )
            }
            return LegPayoff(strategy: strategy, points: points)
        }
        
        // 计算总盈亏
        let totalPoints = priceRange.enumerated().map { index, price in
            let totalProfit = legs.reduce(0.0) { sum, leg in
                sum + leg.points[index].profit
            }
            return PayoffPoint(underlyingPrice: price, profit: totalProfit)
        }
        
        let total = TotalPayoff(points: totalPoints)
        
        return (legs, total)
    }
}

// MARK: - Payoff Diagram View
struct PayoffDiagramView: View {
    let strategies: [OptionStrategy]
    
    @State private var selectedPrice: Double?
    @State private var selectedProfit: Double?
    @State private var showingLegends = true
    
    private var payoffData: (legs: [LegPayoff], total: TotalPayoff) {
        PayoffCalculator.calculatePayoffData(for: strategies)
    }
    
    // 获取当前悬停位置的详细数据
    private var selectedLegProfits: [(name: String, profit: Double)] {
        guard let price = selectedPrice else { return [] }
        
        return payoffData.legs.map { leg in
            let profit = PayoffCalculator.calculateSingleLegPayoff(strategy: leg.strategy, at: price)
            return (leg.displayName, profit)
        }
    }
    
    private var chartMinY: Double {
        let allProfits = payoffData.total.points.map { $0.profit }
        let minProfit = allProfits.min() ?? 0
        // 上下各留 20% 空间
        return minProfit - abs(minProfit) * 0.2
    }
    
    private var chartMaxY: Double {
        let allProfits = payoffData.total.points.map { $0.profit }
        let maxProfit = allProfits.max() ?? 0
        // 上下各留 20% 空间
        return maxProfit + abs(maxProfit) * 0.2
    }
    
    private var chartMinX: Double {
        payoffData.total.points.map { $0.underlyingPrice }.min() ?? 0
    }
    
    private var chartMaxX: Double {
        payoffData.total.points.map { $0.underlyingPrice }.max() ?? 100
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 标题和说明
                VStack(spacing: 8) {
                    Text("Payoff Diagram")
                        .font(.title2.bold())
                    
                    Text("Shows profit/loss at expiration for different underlying prices")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                
                // 图表卡片
                VStack(spacing: 16) {
                    // 图表
                    Chart {
                        // 零线参考
                        RuleMark(y: .value("Break-even", 0))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        
                        // 各单腿（虚线）
                        if showingLegends {
                            ForEach(payoffData.legs) { leg in
                                ForEach(leg.points) { point in
                                    LineMark(
                                        x: .value("Price", point.underlyingPrice),
                                        y: .value("Profit", point.profit)
                                    )
                                    .foregroundStyle(by: .value("Leg", leg.displayName))
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                }
                            }
                        }
                        
                        // 总盈亏（实线）
                        ForEach(payoffData.total.points) { point in
                            LineMark(
                                x: .value("Price", point.underlyingPrice),
                                y: .value("Profit", point.profit)
                            )
                            .foregroundStyle(by: .value("Leg", "Total P&L"))
                            .lineStyle(StrokeStyle(lineWidth: 3))
                        }
                        
                        // 选中点的垂直线
                        if let price = selectedPrice {
                            RuleMark(x: .value("Selected Price", price))
                                .foregroundStyle(.blue.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .annotation(position: .top) {
                                    VStack(spacing: 4) {
                                        Text("$\(String(format: "%.2f", price))")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.blue)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                        }
                    }
                    .chartXScale(domain: chartMinX...chartMaxX)  // 固定 X 轴范围
                    .chartYScale(domain: chartMinY...chartMaxY)  // 固定 Y 轴范围
                    .chartXAxisLabel("Underlying Price")
                    .chartYAxisLabel("Profit / Loss")
                    .chartLegend(position: .bottom, spacing: 8)
                    .frame(height: 400)
                    .chartXSelection(value: $selectedPrice)
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    // 显示/隐藏单腿按钮
                    Button {
                        withAnimation {
                            showingLegends.toggle()
                        }
                    } label: {
                        Label(
                            showingLegends ? "Hide Individual Legs" : "Show Individual Legs",
                            systemImage: showingLegends ? "eye.slash" : "eye"
                        )
                        .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                
                // 悬停详情卡片
                if let price = selectedPrice, let profit = selectedProfit {
                    VStack(spacing: 12) {
                        HStack {
                            Text("At Price: $\(String(format: "%.2f", price))")
                                .font(.headline)
                            
                            Spacer()
                            
                            Text("Total: \(formatPrice(profit))")
                                .font(.headline)
                                .foregroundStyle(profit >= 0 ? .green : .red)
                        }
                        
                        Divider()
                        
                        VStack(spacing: 8) {
                            ForEach(selectedLegProfits, id: \.name) { leg in
                                HStack {
                                    Text(leg.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    
                                    Spacer()
                                    
                                    Text(formatPrice(leg.profit))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(leg.profit >= 0 ? .green : .red)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .padding(.horizontal)
                }
                
                // 策略摘要卡片
                strategyBreakdownCard
                    .padding(.horizontal)
                
                // 关键指标
                metricsCard
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .onChange(of: selectedPrice) { oldValue, newValue in
            if let price = newValue {
                // 找到最接近的点
                let closestPoint = payoffData.total.points.min { point1, point2 in
                    abs(point1.underlyingPrice - price) < abs(point2.underlyingPrice - price)
                }
                selectedProfit = closestPoint?.profit
            } else {
                selectedProfit = nil
            }
        }
    }
    
    // MARK: - Strategy Breakdown Card
    private var strategyBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Strategy Breakdown")
                .font(.headline)
            
            ForEach(strategies) { strategy in
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(strategy.optionType.displayName)
                                .font(.subheadline.weight(.semibold))
                            
                            Text("Strike: $\(String(format: "%.2f", strategy.strikePrice))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(strategy.contracts) contracts")
                                .font(.caption.weight(.medium))
                            
                            Text("Premium: $\(String(format: "%.2f", strategy.optionPrice))")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    if strategy != strategies.last {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Metrics Card
    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Metrics")
                .font(.headline)
            
            let maxProfit = payoffData.total.points.map { $0.profit }.max() ?? 0
            let maxLoss = payoffData.total.points.map { $0.profit }.min() ?? 0
            let breakEvenPoints = findBreakEvenPoints()
            
            VStack(spacing: 12) {
                MetricRow(title: "Max Profit", value: formatPrice(maxProfit), color: .green)
                Divider()
                MetricRow(title: "Max Loss", value: formatPrice(maxLoss), color: .red)
                Divider()
                
                HStack {
                    Text("Break-Even Points")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if breakEvenPoints.isEmpty {
                        Text("None")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                    } else {
                        VStack(alignment: .trailing, spacing: 4) {
                            ForEach(breakEvenPoints, id: \.self) { point in
                                Text("$\(String(format: "%.2f", point))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Helper Methods
    
    /// Calculate max profit from the payoff curve
    private func calculateMaxProfit() -> (value: Double, isUnlimited: Bool) {
        let hasNakedCall = strategies.contains { $0.optionType == .nakedCall }
        
        if hasNakedCall && strategies.count == 1 {
            return (0, true)  // Unlimited profit potential for naked call
        }
        
        let maxProfit = payoffData.total.points.map { $0.profit }.max() ?? 0
        return (maxProfit, false)
    }
    
    /// Calculate max loss from the payoff curve
    private func calculateMaxLoss() -> (value: Double, isUnlimited: Bool) {
        // Check if any strategy has unlimited risk
        let hasNakedCall = strategies.contains { $0.optionType == .nakedCall }
        
        // For combinations with naked calls, check if it's truly unlimited
        if hasNakedCall {
            // If it's a pure naked call position, unlimited risk
            if strategies.count == 1 && strategies[0].optionType == .nakedCall {
                return (0, true)
            }
            // For spreads or combinations, calculate actual max loss from curve
        }
        
        // For all other cases, use the minimum value from the payoff curve
        let minProfit = payoffData.total.points.map { $0.profit }.min() ?? 0
        return (minProfit, false)
    }
    
    /// Find break-even points where profit crosses zero
    private func findBreakEvenPoints() -> [Double] {
        var breakEvenPoints: [Double] = []
        let points = payoffData.total.points
        
        guard points.count >= 2 else { return [] }
        
        for i in 0..<(points.count - 1) {
            let current = points[i]
            let next = points[i + 1]
            
            // Check if profit crosses zero between these two points
            if (current.profit < 0 && next.profit > 0) || (current.profit > 0 && next.profit < 0) {
                // Use linear interpolation to find exact break-even point
                let profitDiff = next.profit - current.profit
                if abs(profitDiff) > 0.001 {  // Avoid division by very small numbers
                    let ratio = -current.profit / profitDiff
                    let priceDiff = next.underlyingPrice - current.underlyingPrice
                    let breakEven = current.underlyingPrice + ratio * priceDiff
                    breakEvenPoints.append(breakEven)
                }
            } else if abs(current.profit) < 0.01 {
                // If very close to zero, treat as break-even
                breakEvenPoints.append(current.underlyingPrice)
            }
        }
        
        // Remove duplicates (break-even points within $0.50 of each other)
        var uniquePoints: [Double] = []
        for point in breakEvenPoints.sorted() {
            if uniquePoints.isEmpty || abs(point - uniquePoints.last!) > 0.5 {
                uniquePoints.append(point)
            }
        }
        
        return uniquePoints
    }
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
}

// MARK: - Metric Row
struct MetricRow: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Preview
#Preview {
    let sampleStrategies = [
        OptionStrategy(
            symbol: "AAPL",
            optionType: .coveredCall,
            expirationDate: Date(),
            strikePrice: 180,
            optionPrice: 5.5,
            averagePricePerShare: 175,
            contracts: 2
        ),
        OptionStrategy(
            symbol: "AAPL",
            optionType: .cashSecuredPut,
            expirationDate: Date(),
            strikePrice: 170,
            optionPrice: 4.0,
            averagePricePerShare: 175,
            contracts: 2
        )
    ]
    
    NavigationStack {
        PayoffDiagramView(strategies: sampleStrategies)
            .navigationTitle("Payoff Diagram")
            .navigationBarTitleDisplayMode(.inline)
    }
}
