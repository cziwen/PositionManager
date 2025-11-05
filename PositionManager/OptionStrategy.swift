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
    var createdAt: Date // 创建时间
    
    init(
        symbol: String,
        optionType: OptionType,
        expirationDate: Date,
        strikePrice: Double,
        optionPrice: Double,
        averagePricePerShare: Double,
        contracts: Int,
        exerciseStatus: ExerciseStatus = .unknown
    ) {
        self.symbol = symbol.uppercased()
        self.optionType = optionType
        self.expirationDate = expirationDate
        self.strikePrice = strikePrice
        self.optionPrice = optionPrice
        self.averagePricePerShare = averagePricePerShare
        self.contracts = contracts
        self.exerciseStatus = exerciseStatus
        self.createdAt = Date()
    }
}

// 期权类型
enum OptionType: String, Codable, CaseIterable {
    case call = "Call"
    case put = "Put"
    
    var displayName: String {
        self.rawValue
    }
}

// 行权状态
enum ExerciseStatus: String, Codable, CaseIterable {
    case yes = "是"
    case no = "否"
    case unknown = "未知"
    
    var displayName: String {
        self.rawValue
    }
}
