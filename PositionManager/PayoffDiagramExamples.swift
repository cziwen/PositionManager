//
//  PayoffDiagramExamples.swift
//  PositionManager
//
//  示例和测试用例
//

import SwiftUI
import SwiftData

// MARK: - 示例策略生成器
struct PayoffDiagramExamples {
    
    /// 示例 1: Iron Condor (铁鹰式)
    /// 适合中性市场预期，赚取时间价值
    static func ironCondor() -> [OptionStrategy] {
        let symbol = "AAPL"
        let expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
//        let currentPrice = 175.0  // 当前股价，仅作参考
        
        return [
            // 卖出 OTM Call（Naked Call 不需要持股成本）
            OptionStrategy(
                symbol: symbol,
                optionType: .nakedCall,
                expirationDate: expirationDate,
                strikePrice: 185,
                optionPrice: 3.5,
                averagePricePerShare: 0,  // Naked Call 无持股成本
                contracts: 1
            ),
            // 卖出 OTM Put（Naked Put 不需要持股成本）
            OptionStrategy(
                symbol: symbol,
                optionType: .nakedPut,
                expirationDate: expirationDate,
                strikePrice: 165,
                optionPrice: 3.0,
                averagePricePerShare: 0,  // Naked Put 无持股成本
                contracts: 1
            )
        ]
    }
    
    /// 示例 2: Short Strangle
    /// 收取更多权利金，但风险较大
    static func shortStrangle() -> [OptionStrategy] {
        let symbol = "TSLA"
        let expirationDate = Calendar.current.date(byAdding: .day, value: 45, to: Date())!
//        let currentPrice = 250.0  // 当前股价，仅作参考
        
        return [
            // 卖出 Call（Naked Call 不需要持股成本）
            OptionStrategy(
                symbol: symbol,
                optionType: .nakedCall,
                expirationDate: expirationDate,
                strikePrice: 270,
                optionPrice: 8.5,
                averagePricePerShare: 0,  // Naked Call 无持股成本
                contracts: 2
            ),
            // 卖出 Put（Naked Put 不需要持股成本）
            OptionStrategy(
                symbol: symbol,
                optionType: .nakedPut,
                expirationDate: expirationDate,
                strikePrice: 230,
                optionPrice: 7.0,
                averagePricePerShare: 0,  // Naked Put 无持股成本
                contracts: 2
            )
        ]
    }
    
    /// 示例 3: Covered Call
    /// 持有股票，卖出 Call 收取权利金
    static func coveredCall() -> [OptionStrategy] {
        let symbol = "MSFT"
        let expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let stockCostBasis = 370.0  // 股票持仓成本（重要！）
        
        return [
            // 卖出 Covered Call（假设已持有 100 股，成本 $370）
            OptionStrategy(
                symbol: symbol,
                optionType: .coveredCall,
                expirationDate: expirationDate,
                strikePrice: 390,
                optionPrice: 6.5,
                averagePricePerShare: stockCostBasis,  // Covered Call 需要股票成本
                contracts: 1
            )
        ]
    }
    
    /// 示例 4: Cash-Secured Put
    /// 愿意以低价买入股票，卖出 Put
    static func cashSecuredPut() -> [OptionStrategy] {
        let symbol = "NVDA"
        let expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
//        let currentPrice = 500.0  // 当前股价，仅作参考
        
        return [
            // 卖出 Cash-Secured Put（准备以 $480 买入）
            OptionStrategy(
                symbol: symbol,
                optionType: .cashSecuredPut,
                expirationDate: expirationDate,
                strikePrice: 480,
                optionPrice: 12.0,
                averagePricePerShare: 0,  // Cash-Secured Put 还未持股，成本为 0
                contracts: 1
            )
        ]
    }
    
    /// 示例 5: Wheel Strategy (轮式策略)
    /// 结合 Covered Call 和 Cash-Secured Put
    static func wheelStrategy() -> [OptionStrategy] {
        let symbol = "AMD"
        let expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let stockCostBasis = 140.0  // 持有股票的成本价
        
        return [
            // 持有股票，卖出 Covered Call
            OptionStrategy(
                symbol: symbol,
                optionType: .coveredCall,
                expirationDate: expirationDate,
                strikePrice: 150,
                optionPrice: 5.0,
                averagePricePerShare: stockCostBasis,  // 股票成本 $140
                contracts: 1
            ),
            // 同时卖出 Cash-Secured Put（准备再买入）
            OptionStrategy(
                symbol: symbol,
                optionType: .cashSecuredPut,
                expirationDate: expirationDate,
                strikePrice: 130,
                optionPrice: 4.5,
                averagePricePerShare: 0,  // 还未持有这部分股票
                contracts: 1
            )
        ]
    }
    
    /// 示例 6: 多腿复杂策略
    /// 同一标的，多个执行价和到期日
    static func complexStrategy() -> [OptionStrategy] {
        let symbol = "SPY"
        let expiration1 = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let expiration2 = Calendar.current.date(byAdding: .day, value: 60, to: Date())!
//        let currentPrice = 450.0  // 当前股价，仅作参考
        
        return [
            // 近期 Call（Naked Call）
            OptionStrategy(
                symbol: symbol,
                optionType: .nakedCall,
                expirationDate: expiration1,
                strikePrice: 460,
                optionPrice: 5.0,
                averagePricePerShare: 0,  // Naked Call 无持股成本
                contracts: 2
            ),
            // 近期 Put（Naked Put）
            OptionStrategy(
                symbol: symbol,
                optionType: .nakedPut,
                expirationDate: expiration1,
                strikePrice: 440,
                optionPrice: 4.5,
                averagePricePerShare: 0,  // Naked Put 无持股成本
                contracts: 2
            ),
            // 远期 Call（Naked Call）
            OptionStrategy(
                symbol: symbol,
                optionType: .nakedCall,
                expirationDate: expiration2,
                strikePrice: 465,
                optionPrice: 7.0,
                averagePricePerShare: 0,  // Naked Call 无持股成本
                contracts: 1
            ),
            // 远期 Put（Naked Put）
            OptionStrategy(
                symbol: symbol,
                optionType: .nakedPut,
                expirationDate: expiration2,
                strikePrice: 435,
                optionPrice: 6.5,
                averagePricePerShare: 0,  // Naked Put 无持股成本
                contracts: 1
            )
        ]
    }
}

// MARK: - 示例预览视图
#Preview("Iron Condor") {
    NavigationStack {
        PayoffDiagramView(strategies: PayoffDiagramExamples.ironCondor())
            .navigationTitle("Iron Condor")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Short Strangle") {
    NavigationStack {
        PayoffDiagramView(strategies: PayoffDiagramExamples.shortStrangle())
            .navigationTitle("Short Strangle")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Covered Call") {
    NavigationStack {
        PayoffDiagramView(strategies: PayoffDiagramExamples.coveredCall())
            .navigationTitle("Covered Call")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Cash-Secured Put") {
    NavigationStack {
        PayoffDiagramView(strategies: PayoffDiagramExamples.cashSecuredPut())
            .navigationTitle("Cash-Secured Put")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Wheel Strategy") {
    NavigationStack {
        PayoffDiagramView(strategies: PayoffDiagramExamples.wheelStrategy())
            .navigationTitle("Wheel Strategy")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Complex Multi-Leg") {
    NavigationStack {
        PayoffDiagramView(strategies: PayoffDiagramExamples.complexStrategy())
            .navigationTitle("Complex Strategy")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 测试不同场景的辅助视图
struct PayoffDiagramTestView: View {
    @State private var selectedExample = 0
    
    let examples: [(name: String, strategies: [OptionStrategy])] = [
        ("Iron Condor", PayoffDiagramExamples.ironCondor()),
        ("Short Strangle", PayoffDiagramExamples.shortStrangle()),
        ("Covered Call", PayoffDiagramExamples.coveredCall()),
        ("Cash-Secured Put", PayoffDiagramExamples.cashSecuredPut()),
        ("Wheel Strategy", PayoffDiagramExamples.wheelStrategy()),
        ("Complex Strategy", PayoffDiagramExamples.complexStrategy())
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 示例选择器
                Picker("Strategy Example", selection: $selectedExample) {
                    ForEach(examples.indices, id: \.self) { index in
                        Text(examples[index].name).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .background(Color(.systemGroupedBackground))
                
                // Payoff Diagram
                PayoffDiagramView(strategies: examples[selectedExample].strategies)
            }
            .navigationTitle("Payoff Examples")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("Test All Examples") {
    PayoffDiagramTestView()
}
