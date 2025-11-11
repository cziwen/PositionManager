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
    
    // 缓存数据，避免每次视图更新都重新计算
    @State private var cachedPayoffData: (legs: [LegPayoff], total: TotalPayoff)?
    @State private var cachedChartMinY: Double?
    @State private var cachedChartMaxY: Double?
    @State private var cachedChartMinX: Double?
    @State private var cachedChartMaxX: Double?
    @State private var cachedMetrics: (maxProfit: Double, maxLoss: Double, isMaxLossUnlimited: Bool, breakEvenPoints: [Double])?
    @State private var strategiesHash: Int = 0
    
    // 计算策略列表的哈希值，用于检测变化
    private func hashStrategies() -> Int {
        var hasher = Hasher()
        for strategy in strategies {
            hasher.combine(strategy.id)
            hasher.combine(strategy.strikePrice)
            hasher.combine(strategy.optionPrice)
            hasher.combine(strategy.contracts)
            hasher.combine(strategy.averagePricePerShare)
        }
        return hasher.finalize()
    }
    
    // 只使用缓存的数据，不进行任何计算
    private var payoffData: (legs: [LegPayoff], total: TotalPayoff)? {
        cachedPayoffData
    }
    
    // 从缓存数据中获取当前悬停位置的详细数据
    private var selectedLegProfits: [(name: String, profit: Double)] {
        guard let price = selectedPrice,
              let data = cachedPayoffData else {
            return []
        }
        
        // 从缓存的数据中查找最接近的价格点
        return data.legs.map { leg in
            // 找到最接近的价格点
            let closestPoint = leg.points.min { point1, point2 in
                abs(point1.underlyingPrice - price) < abs(point2.underlyingPrice - price)
            }
            let profit = closestPoint?.profit ?? 0
            let displayName = "\(leg.strategy.optionType.displayName) @ $\(String(format: "%.2f", leg.strategy.strikePrice))"
            return (displayName, profit)
        }
    }
    
    private var chartMinY: Double {
        cachedChartMinY ?? 0
    }
    
    private var chartMaxY: Double {
        cachedChartMaxY ?? 100
    }
    
    private var chartMinX: Double {
        cachedChartMinX ?? 0
    }
    
    private var chartMaxX: Double {
        cachedChartMaxX ?? 100
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
                    // 图表 - 只在有缓存数据时显示
                    if let data = payoffData {
                        Chart {
                            // 零线参考
                            RuleMark(y: .value("Zero", 0))
                                .foregroundStyle(.secondary.opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            
                            // 各单腿（虚线）
                            if showingLegends {
                                ForEach(data.legs) { leg in
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
                            ForEach(data.total.points) { point in
                                LineMark(
                                    x: .value("Price", point.underlyingPrice),
                                    y: .value("Profit", point.profit)
                                )
                                .foregroundStyle(.primary)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                            
                            // 选中点的标记
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
                        .chartXScale(domain: chartMinX...chartMaxX)
                        .chartYScale(domain: chartMinY...chartMaxY)
                        .chartXSelection(value: $selectedPrice)
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
                    } else {
                        // 数据未准备好时显示占位符
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
                    }
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
            // 从缓存数据中查找总盈亏，避免重新计算
            if let price = newValue, let data = cachedPayoffData {
                // 从总盈亏数据中查找最接近的价格点
                let closestPoint = data.total.points.min { point1, point2 in
                    abs(point1.underlyingPrice - price) < abs(point2.underlyingPrice - price)
                }
                selectedProfit = closestPoint?.profit
            } else {
                selectedProfit = nil
            }
        }
        .task(id: hashStrategies()) {
            // 当策略列表变化时，更新缓存
            let newPayoffData = PayoffCalculator.calculatePayoffData(for: strategies)
            let allProfits = newPayoffData.total.points.map { $0.profit }
            let minProfit = allProfits.min() ?? 0
            let maxProfit = allProfits.max() ?? 0
            let range = maxProfit - minProfit
            let bufferY = max(abs(range) * 0.4, abs(minProfit) * 0.4)
            let newChartMinY = minProfit - bufferY
            let newChartMaxY = maxProfit + bufferY
            let newChartMinX = newPayoffData.total.points.map { $0.underlyingPrice }.min() ?? 0
            let newChartMaxX = newPayoffData.total.points.map { $0.underlyingPrice }.max() ?? 100
            let newMetrics = PayoffMetricsCalculator.calculateMetrics(for: strategies)
            
            await MainActor.run {
                cachedPayoffData = newPayoffData
                cachedChartMinY = newChartMinY
                cachedChartMaxY = newChartMaxY
                cachedChartMinX = newChartMinX
                cachedChartMaxX = newChartMaxX
                cachedMetrics = (newMetrics.maxProfit, newMetrics.maxLoss, newMetrics.isMaxLossUnlimited, newMetrics.breakEvenPoints)
                strategiesHash = hashStrategies()
            }
        }
        .onAppear {
            // 首次出现时，如果缓存为空，立即计算（同步，避免闪烁）
            if cachedPayoffData == nil {
                let newPayoffData = PayoffCalculator.calculatePayoffData(for: strategies)
                let allProfits = newPayoffData.total.points.map { $0.profit }
                let minProfit = allProfits.min() ?? 0
                let maxProfit = allProfits.max() ?? 0
                let range = maxProfit - minProfit
                let bufferY = max(abs(range) * 0.4, abs(minProfit) * 0.4)
                cachedPayoffData = newPayoffData
                cachedChartMinY = minProfit - bufferY
                cachedChartMaxY = maxProfit + bufferY
                cachedChartMinX = newPayoffData.total.points.map { $0.underlyingPrice }.min() ?? 0
                cachedChartMaxX = newPayoffData.total.points.map { $0.underlyingPrice }.max() ?? 100
                cachedMetrics = {
                    let metrics = PayoffMetricsCalculator.calculateMetrics(for: strategies)
                    return (metrics.maxProfit, metrics.maxLoss, metrics.isMaxLossUnlimited, metrics.breakEvenPoints)
                }()
                strategiesHash = hashStrategies()
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
            
            // 只使用缓存的 metrics，不进行任何计算
            if let metrics = cachedMetrics {
                let maxProfit = metrics.maxProfit
                let maxLoss = metrics.maxLoss
                let isMaxLossUnlimited = metrics.isMaxLossUnlimited
                let breakEvenPoints = metrics.breakEvenPoints
            
            VStack(spacing: 12) {
                if maxProfit.isInfinite {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Max Profit")
                        Spacer()
                        Text("Unlimited")
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                } else {
                    MetricRow(title: "Max Profit", value: formatPriceWithSign(maxProfit), color: .green)
                }
                Divider()
                
                // Max Loss - 对于 naked call 显示特殊文本
                if isMaxLossUnlimited {
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
                    MetricRow(title: "Max Loss", value: formatPriceWithSign(maxLoss), color: .red)
                }
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
            } else {
                // Metrics 未准备好
                VStack(spacing: 12) {
                    Text("Metrics will appear when chart data is ready")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Helper Methods
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
    
    private func formatPriceWithSign(_ price: Double) -> String {
        if price >= 0 {
            return String(format: "+$%.2f", price)
        } else {
            return String(format: "$%.2f", price)
        }
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
