//
//  PayoffMetricsCalculator.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/6/25.
//

import Foundation

// MARK: - Payoff Metrics Calculator
/// 计算期权策略的关键指标（Max Profit, Max Loss, Break-even Points）
/// 可用于任何需要绘制盈亏图表的场景
class PayoffMetricsCalculator {
    /// 计算单个策略的 Max Profit 和 Max Loss（使用公式）
    /// - Parameter strategy: 期权策略
    /// - Returns: (maxProfit, maxLoss, isMaxLossUnlimited, breakEvenPoints)
    ///   - maxProfit: 最大盈利
    ///   - maxLoss: 最大亏损
    ///   - isMaxLossUnlimited: 最大亏损是否无限（如 Naked Call）
    ///   - breakEvenPoints: Break-even 价格点数组（盈亏平衡点）
    static func calculateSingleStrategyMetrics(_ strategy: OptionStrategy) -> (maxProfit: Double, maxLoss: Double, isMaxLossUnlimited: Bool, breakEvenPoints: [Double]) {
        let K = strategy.strikePrice
        let P = strategy.optionPrice * Double(strategy.contracts) * 100  // Total premium received
        let S0 = strategy.averagePricePerShare
        let quantity = Double(strategy.contracts) * 100
        
        let maxProfit: Double
        let maxLoss: Double
        let isMaxLossUnlimited: Bool
        

        // 核心原则：收入-成本=盈亏
        switch strategy.optionType {
        case .coveredCall:
            // Max Profit: P - S₀ + K
            maxProfit = (K * quantity) + P - (S0 * quantity)
            // Max Loss: S₀ - P (when underlying price = 0)
            maxLoss = P - (S0 * quantity)
            isMaxLossUnlimited = false
            
        case .cashSecuredPut:
            // Max Profit: P (when option expires worthless)
            maxProfit = P
            // Max Loss: P - K (when underlying price = 0)
            maxLoss = P - (K * quantity)
            isMaxLossUnlimited = false
            
        case .nakedCall:
            // Max Profit: P (when option expires worthless)
            maxProfit = P
            // Max Loss: ∞ (theoretically unlimited)
            maxLoss = 0
            isMaxLossUnlimited = true
            
        case .nakedPut:
            // Max Profit: P (when option expires worthless)
            maxProfit = P
            // Max Loss: P - K (when underlying price = 0)
            maxLoss = P - (K * quantity)
            isMaxLossUnlimited = false
            
        case .buyCall:
            // Buy Call: 买入看涨期权
            // Max Profit: 理论上无限（当股价无限上涨时）
            maxProfit = Double.infinity
            // Max Loss: 权利金成本（当期权到期无价值时）
            maxLoss = -P  // 负数表示损失
            isMaxLossUnlimited = false
            
        case .buyPut:
            // Buy Put: 买入看跌期权
            // Max Profit: (执行价 - 0) × 数量 - 权利金成本（当股价为 0 时）
            maxProfit = (K * quantity) - P
            // Max Loss: 权利金成本（当期权到期无价值时）
            maxLoss = -P  // 负数表示损失
            isMaxLossUnlimited = false
        }
        
        // Calculate break-even points by scanning
        let data = generatePayoffDataPoints(strategies: [strategy])
        let breakEvenPoints = calculateBreakEvenPoints(from: data)
        
        return (maxProfit, maxLoss, isMaxLossUnlimited, breakEvenPoints)
    }
    
    /// 计算总盈亏（所有策略的组合）
    /// - Parameters:
    ///   - strategies: 策略列表
    ///   - underlyingPrice: 标的价格
    /// - Returns: 总盈亏
    static func calculateTotalProfitLoss(strategies: [OptionStrategy], at underlyingPrice: Double) -> Double {
        strategies.reduce(0.0) { sum, strategy in
            sum + PayoffCalculator.calculateSingleLegPayoff(strategy: strategy, at: underlyingPrice)
        }
    }
    
    /// 生成盈亏数据点
    /// - Parameters:
    ///   - strategies: 策略列表
    ///   - steps: 数据点数量（默认 101，与 RollCalculatorView 一致）
    /// - Returns: [(price, profitLoss)] 数据点数组
    static func generatePayoffDataPoints(strategies: [OptionStrategy], steps: Int = 100) -> [(price: Double, profitLoss: Double)] {
        guard !strategies.isEmpty else { return [] }
        
        // Generate price range
        let strikes = strategies.map { $0.strikePrice }
        let minStrike = strikes.min() ?? 0
        let maxStrike = strikes.max() ?? 100
        
        let rangeWidth = maxStrike - minStrike
        let buffer = max(rangeWidth * 0.2, minStrike * 0.2)
        
        let minPrice = max(0, minStrike - buffer)
        let maxPrice = maxStrike + buffer
        let step = (maxPrice - minPrice) / Double(steps)
        
        var points: [(price: Double, profitLoss: Double)] = []
        
        for i in 0...steps {
            let price = minPrice + Double(i) * step
            let profitLoss = calculateTotalProfitLoss(strategies: strategies, at: price)
            points.append((price: price, profitLoss: profitLoss))
        }
        
        return points
    }
    
    /// 计算 Break-even Points
    /// - Parameter data: 盈亏数据点数组
    /// - Returns: Break-even 价格点数组
    static func calculateBreakEvenPoints(from data: [(price: Double, profitLoss: Double)]) -> [Double] {
        var breakEvenPoints: [Double] = []
        
        for i in 0..<(data.count - 1) {
            let current = data[i]
            let next = data[i + 1]
            
            if (current.profitLoss < 0 && next.profitLoss > 0) || (current.profitLoss > 0 && next.profitLoss < 0) {
                let profitDiff = next.profitLoss - current.profitLoss
                if abs(profitDiff) > 0.001 {
                    let ratio = -current.profitLoss / profitDiff
                    let priceDiff = next.price - current.price
                    let breakEven = current.price + ratio * priceDiff
                    breakEvenPoints.append(breakEven)
                }
            } else if abs(current.profitLoss) < 0.01 {
                // If very close to zero, treat as break-even
                breakEvenPoints.append(current.price)
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
    
    /// 计算策略组合的关键指标
    /// - Parameter strategies: 策略列表
    /// - Returns: (maxProfit, maxLoss, isMaxLossUnlimited, breakEvenPoints)
    ///   - maxProfit: 最大盈利
    ///   - maxLoss: 最大亏损
    ///   - isMaxLossUnlimited: 最大亏损是否无限（如 Naked Call）
    ///   - breakEvenPoints: Break-even 价格点数组（盈亏平衡点）
    static func calculateMetrics(for strategies: [OptionStrategy]) -> (maxProfit: Double, maxLoss: Double, isMaxLossUnlimited: Bool, breakEvenPoints: [Double]) {
        // For single strategy, use formula-based calculation
        if strategies.count == 1 {
            let singleMetrics = calculateSingleStrategyMetrics(strategies[0])
            return (singleMetrics.maxProfit, singleMetrics.maxLoss, singleMetrics.isMaxLossUnlimited, singleMetrics.breakEvenPoints)
        }
        
        // For multiple strategies (combinations), scan price range
        let data = generatePayoffDataPoints(strategies: strategies)
        
        // Max profit
        let maxProfit = data.map { $0.profitLoss }.max() ?? 0
        
        // Max loss - 需要考虑边界情况
        var maxLoss = data.map { $0.profitLoss }.min() ?? 0
        var isMaxLossUnlimited = false
        
        // 检查是否有 naked call
        let hasNakedCall = strategies.contains { $0.optionType == .nakedCall }
        
        // 根据策略类型检查边界情况
        if hasNakedCall {
            // Naked Call: 当股价无限上涨时，损失无限大
            // 检查在更高价格时的损失（比如当前最大价格的 10 倍）
            if let maxPrice = data.map({ $0.price }).max(), maxPrice > 0 {
                let extremePrice = maxPrice * 10
                let extremePL = calculateTotalProfitLoss(strategies: strategies, at: extremePrice)
                maxLoss = min(maxLoss, extremePL)
            }
            // Naked Call 的损失理论上无限（股价可以无限上涨）
            isMaxLossUnlimited = true
        }
        
        // Check at price = 0 for strategies that might have max loss there
        if !isMaxLossUnlimited {
            let plAtZero = calculateTotalProfitLoss(strategies: strategies, at: 0)
            maxLoss = min(maxLoss, plAtZero)
        }
        
        // Break-even points
        let breakEvenPoints = calculateBreakEvenPoints(from: data)
        
        return (maxProfit, maxLoss, isMaxLossUnlimited, breakEvenPoints)
    }
}

