//
//  OptionStrategy.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/4/25.
//

import Foundation
import SwiftData

@Model
final class OptionStrategy {
    var symbol: String // 股票代码
    var optionType: OptionType // 期权类型
    var expirationDate: Date // 执行日
    var strikePrice: Double // 执行价
    var optionPrice: Double // 期权价格
    var averagePricePerShare: Double // 每股均价
    var contracts: Int // 合同数
    var exerciseStatus: ExerciseStatus // 是否行权
    var marginCost: Double? // 保证金成本（仅用于 Naked Call/Put）
    var exerciseMarketPrice: Double? // 行权时的市场价格（仅用于 Naked Call/Put 被行权）
    var currentMarketPrice: Double? // 当前市场价格（用于未行权时计算未实现盈亏）
    var createdAt: Date // 创建时间
    
    init(
        symbol: String,
        optionType: OptionType,
        expirationDate: Date,
        strikePrice: Double,
        optionPrice: Double,
        averagePricePerShare: Double,
        contracts: Int,
        exerciseStatus: ExerciseStatus = .unknown,
        marginCost: Double? = nil,
        exerciseMarketPrice: Double? = nil,
        currentMarketPrice: Double? = nil
    ) {
        self.symbol = symbol.uppercased()
        self.optionType = optionType
        self.expirationDate = expirationDate
        self.strikePrice = strikePrice
        self.optionPrice = optionPrice
        self.averagePricePerShare = averagePricePerShare
        self.contracts = contracts
        self.exerciseStatus = exerciseStatus
        self.marginCost = marginCost
        self.exerciseMarketPrice = exerciseMarketPrice
        self.currentMarketPrice = currentMarketPrice
        self.createdAt = Date()
    }
    
    /// 计算或获取实际的保证金成本
    /// - Returns: 保证金成本
    func getMarginCost() -> Double {
        switch optionType {
        case .nakedCall:
            // 如果有输入 marginCost，使用输入值；否则估算为执行价的 20%
            if let margin = marginCost {
                return margin
            } else {
                return strikePrice * Double(contracts) * 100 * 0.20
            }
            
        case .nakedPut:
            // 如果有输入 marginCost，使用输入值；否则估算为执行价的 15%
            if let margin = marginCost {
                return margin
            } else {
                return strikePrice * Double(contracts) * 100 * 0.15
            }
            
        default:
            // 其他类型不使用保证金成本
            return 0
        }
    }
}

// Option Type
enum OptionType: String, Codable, CaseIterable {
    case coveredCall = "CoveredCall"
    case nakedCall = "NakedCall"
    case cashSecuredPut = "CashSecuredPut"
    case nakedPut = "NakedPut"
    
    var displayName: String {
        switch self {
        case .coveredCall:
            return "Sell Covered Call"
        case .nakedCall:
            return "Sell Naked Call"
        case .cashSecuredPut:
            return "Sell Cash-Secured Put"
        case .nakedPut:
            return "Sell Naked Put"
        }
    }
    
    // 辅助属性：判断是 Call 还是 Put
    var isCall: Bool {
        self == .coveredCall || self == .nakedCall
    }
    
    var isPut: Bool {
        self == .cashSecuredPut || self == .nakedPut
    }
    
    // 辅助属性：判断是否有担保
    var isSecured: Bool {
        self == .coveredCall || self == .cashSecuredPut
    }
    
    var isNaked: Bool {
        self == .nakedCall || self == .nakedPut
    }
}

// Exercise Status
enum ExerciseStatus: String, Codable, CaseIterable {
    case yes = "Yes"
    case no = "No"
    case unknown = "Unknown"
    
    var displayName: String {
        self.rawValue
    }
}
