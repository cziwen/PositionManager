//
//  AddStrategyView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/4/25.
//

import SwiftUI
import SwiftData

struct AddStrategyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // 编辑模式：传入已存在的策略
    var strategyToEdit: OptionStrategy?
    
    @State private var symbol: String = ""
    @State private var optionType: OptionType = .coveredCall
    @State private var expirationDate: Date = Date()
    @State private var strikePrice: String = ""
    @State private var optionPrice: String = ""
    @State private var averagePricePerShare: String = ""
    @State private var marginCost: String = ""  // 新增：保证金成本
    @State private var contracts: String = ""
    @State private var exerciseStatus: ExerciseStatus = .unknown
    @State private var exerciseMarketPrice: String = ""  // 新增：行权时的市场价格
    @State private var currentMarketPrice: String = ""  // 新增：当前市场价格（未行权时）
    
    // 缺失的错误状态（用于保存前校验）
    @State private var strikePriceError: Bool = false
    @State private var optionPriceError: Bool = false
    @State private var avgPriceError: Bool = false
    @State private var marginCostError: Bool = false
    @State private var exerciseMarketPriceError: Bool = false  // 新增
    @State private var currentMarketPriceError: Bool = false  // 新增
    @State private var contractsError: Bool = false
    
    // Focus states
    @FocusState private var focusedField: Field?
    
    enum Field {
        case symbol, strikePrice, optionPrice, avgPrice, marginCost, exerciseMarketPrice, currentMarketPrice, contracts
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Stock Information") {
                    TextField("Stock Symbol", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .symbol)
                        .disabled(isEditMode) // 编辑模式下不能修改 symbol
                }
                
                Section("Option Details") {
                    Picker("Option Strategy Type", selection: $optionType) {
                        ForEach(OptionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    DatePicker("Expiration Date", selection: $expirationDate, displayedComponents: .date)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Strike Price", text: $strikePrice)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .strikePrice)
                        
                        if !strikePrice.isEmpty && !strikePrice.isValidPositiveNumber {
                            Text("Please enter a valid positive number")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Option Premium", text: $optionPrice)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .optionPrice)
                        
                        if !optionPrice.isEmpty && !optionPrice.isValidPositiveNumber {
                            Text("Please enter a valid positive number")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                Section("Position Information") {
                    // 只有 Covered Call 需要输入股票均价
                    if optionType == .coveredCall {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Stock Cost Basis (Average Price Per Share)", text: $averagePricePerShare)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .avgPrice)
                            
                            if !averagePricePerShare.isEmpty && !averagePricePerShare.isValidPositiveNumber {
                                Text("Please enter a valid positive number")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            
                            Text("Enter the cost basis of your stock position")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Naked Call/Put 可以输入保证金成本（可选）
                    if optionType == .nakedCall || optionType == .nakedPut {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Margin Cost (Optional)", text: $marginCost)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .marginCost)
                            
                            if !marginCost.isEmpty && !marginCost.isValidPositiveNumber {
                                Text("Please enter a valid positive number")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            
                            // 显示估算值
                            if let strike = Double(strikePrice), let contractsInt = Int(contracts), contractsInt > 0 {
                                let estimatedRate = optionType == .nakedCall ? 0.20 : 0.15
                                let estimated = strike * Double(contractsInt) * 100 * estimatedRate
                                
                                Text("If left empty, will estimate at \(Int(estimatedRate * 100))% of strike value ≈ $\(String(format: "%.2f", estimated))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Number of Contracts", text: $contracts)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .contracts)
                        
                        if !contracts.isEmpty && !contracts.isValidPositiveInteger {
                            Text("Please enter a valid positive integer")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                Section("Exercise Status") {
                    Picker("Will Exercise", selection: $exerciseStatus) {
                        ForEach(ExerciseStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Covered Call 未行权时（No），强制输入当前市价
                    if optionType == .coveredCall && exerciseStatus == .no {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Current Market Price (Required)", text: $currentMarketPrice)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .currentMarketPrice)
                            
                            if !currentMarketPrice.isEmpty && !currentMarketPrice.isValidPositiveNumber {
                                Text("Please enter a valid positive number")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            
                            if currentMarketPrice.isEmpty {
                                Text("Required: Enter current market price for P/L calculation")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Current market price for calculating unrealized gains/losses")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // Cash-Secured Put 被行权时（Yes），需要输入市场价格
                    if optionType == .cashSecuredPut && exerciseStatus == .yes {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Market Price at Exercise (Required)", text: $exerciseMarketPrice)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .exerciseMarketPrice)
                            
                            if !exerciseMarketPrice.isEmpty && !exerciseMarketPrice.isValidPositiveNumber {
                                Text("Please enter a valid positive number")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            
                            if exerciseMarketPrice.isEmpty {
                                Text("Required: Enter market price at exercise for P/L calculation")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Market price when put was exercised (P/L = Market Price - Strike Price + Premium)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // Naked Call/Put 被行权时（仅 Yes），需要输入市场价格
                    if (optionType == .nakedCall || optionType == .nakedPut) && exerciseStatus == .yes {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Market Price at Exercise", text: $exerciseMarketPrice)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .exerciseMarketPrice)
                            
                            if !exerciseMarketPrice.isEmpty && !exerciseMarketPrice.isValidPositiveNumber {
                                Text("Please enter a valid positive number")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            
                            // 显示说明
                            if optionType == .nakedCall {
                                Text("Enter the market price when call was exercised (for calculating actual loss)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Enter the market price when put was exercised (for calculating actual loss)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditMode ? "Edit Strategy" : "Add Strategy")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // 使用 task 替代 onAppear，确保在视图准备好后加载数据
                loadStrategyData()
            }
            .onChange(of: optionType) { oldValue, newValue in
                // 当切换到非 Covered Call 时，清空均价字段
                if newValue != .coveredCall {
                    averagePricePerShare = ""
                }
                // 当切换到非 Naked 策略时，清空保证金字段
                if newValue != .nakedCall && newValue != .nakedPut {
                    marginCost = ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveStrategy()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }
    
    // MARK: - 辅助属性和方法
    
    private var isEditMode: Bool {
        strategyToEdit != nil
    }
    
    // 加载策略数据（编辑模式）
    private func loadStrategyData() {
        guard let strategy = strategyToEdit else { return }
        
        symbol = strategy.symbol
        optionType = strategy.optionType
        expirationDate = strategy.expirationDate
        strikePrice = String(format: "%.2f", strategy.strikePrice)
        optionPrice = String(format: "%.2f", strategy.optionPrice)
        averagePricePerShare = String(format: "%.2f", strategy.averagePricePerShare)
        contracts = String(strategy.contracts)
        exerciseStatus = strategy.exerciseStatus
        
        // 加载保证金成本（如果有）
        if let margin = strategy.marginCost {
            marginCost = String(format: "%.2f", margin)
        }
        
        // 加载行权市场价格（如果有）
        if let marketPrice = strategy.exerciseMarketPrice {
            exerciseMarketPrice = String(format: "%.2f", marketPrice)
        }
        
        // 加载当前市场价格（如果有）
        if let currentPrice = strategy.currentMarketPrice {
            currentMarketPrice = String(format: "%.2f", currentPrice)
        }
    }
    
    // Validation functions
    private func validateStrikePrice() {
        if strikePrice.isEmpty {
            strikePriceError = false
            return
        }
        if let value = Double(strikePrice), value > 0 {
            strikePriceError = false
        } else {
            strikePriceError = true
        }
    }
    
    private func validateOptionPrice() {
        if optionPrice.isEmpty {
            optionPriceError = false
            return
        }
        if let value = Double(optionPrice), value > 0 {
            optionPriceError = false
        } else {
            optionPriceError = true
        }
    }
    
    private func validateAvgPrice() {
        if averagePricePerShare.isEmpty {
            avgPriceError = false
            return
        }
        if let value = Double(averagePricePerShare), value > 0 {
            avgPriceError = false
        } else {
            avgPriceError = true
        }
    }
    
    private func validateContracts() {
        if contracts.isEmpty {
            contractsError = false
            return
        }
        if let value = Int(contracts), value > 0 {
            contractsError = false
        } else {
            contractsError = true
        }
    }
    
    private var isFormValid: Bool {
        let basicValid = !symbol.isEmpty &&
                        strikePrice.isValidPositiveNumber &&
                        optionPrice.isValidPositiveNumber &&
                        contracts.isValidPositiveInteger
        
        // Covered Call 需要验证股票均价
        if optionType == .coveredCall {
            let avgPriceValid = averagePricePerShare.isValidPositiveNumber
            
            // 如果 exercise 状态为 No，还需要验证当前市价
            if exerciseStatus == .no {
                return basicValid && avgPriceValid && currentMarketPrice.isValidPositiveNumber
            }
            
            return basicValid && avgPriceValid
        }
        
        // Cash-Secured Put 被行权时（Yes），需要验证市场价格
        if optionType == .cashSecuredPut && exerciseStatus == .yes {
            return basicValid && exerciseMarketPrice.isValidPositiveNumber
        }
        
        // 其他策略类型不需要均价
        return basicValid
    }
    
    private func saveStrategy() {
        // Validate all fields one more time
        validateStrikePrice()
        validateOptionPrice()
        validateContracts()
        
        // Only validate avg price for Covered Call
        if optionType == .coveredCall {
            validateAvgPrice()
            guard !avgPriceError else { return }
        }
        
        // If there are any errors, don't save
        guard !strikePriceError && !optionPriceError && !contractsError else {
            return
        }
        
        guard let strikePriceValue = Double(strikePrice),
              let optionPriceValue = Double(optionPrice),
              let contractsValue = Int(contracts) else {
            return
        }
        
        // 根据策略类型设置均价
        let avgPriceValue: Double
        if optionType == .coveredCall {
            guard let value = Double(averagePricePerShare) else { return }
            avgPriceValue = value
        } else {
            // 其他策略类型均价设为 0
            avgPriceValue = 0
        }
        
        // 处理保证金成本（仅用于 Naked Call/Put）
        let marginCostValue: Double?
        if optionType == .nakedCall || optionType == .nakedPut {
            if !marginCost.isEmpty, let value = Double(marginCost) {
                marginCostValue = value
            } else {
                marginCostValue = nil  // 留空，将使用默认估算
            }
        } else {
            marginCostValue = nil
        }
        
        // 处理行权市场价格
        let exerciseMarketPriceValue: Double?
        if exerciseStatus == .yes {
            // 被行权时需要市场价格的策略类型：Cash-Secured Put, Naked Call, Naked Put
            if optionType == .cashSecuredPut || optionType == .nakedCall || optionType == .nakedPut {
                if !exerciseMarketPrice.isEmpty, let value = Double(exerciseMarketPrice) {
                    exerciseMarketPriceValue = value
                } else {
                    exerciseMarketPriceValue = nil
                }
            } else {
                exerciseMarketPriceValue = nil
            }
        } else {
            exerciseMarketPriceValue = nil
        }
        
        // 处理当前市场价格（仅用于 Covered Call 且状态为 No）
        let currentMarketPriceValue: Double?
        if optionType == .coveredCall && exerciseStatus == .no {
            if !currentMarketPrice.isEmpty, let value = Double(currentMarketPrice) {
                currentMarketPriceValue = value
            } else {
                currentMarketPriceValue = nil
            }
        } else {
            currentMarketPriceValue = nil
        }
        
        if let existingStrategy = strategyToEdit {
            // 编辑模式：更新现有策略
            existingStrategy.optionType = optionType
            existingStrategy.expirationDate = expirationDate
            existingStrategy.strikePrice = strikePriceValue
            existingStrategy.optionPrice = optionPriceValue
            existingStrategy.averagePricePerShare = avgPriceValue
            existingStrategy.contracts = contractsValue
            existingStrategy.exerciseStatus = exerciseStatus
            existingStrategy.marginCost = marginCostValue
            existingStrategy.exerciseMarketPrice = exerciseMarketPriceValue
            existingStrategy.currentMarketPrice = currentMarketPriceValue
        } else {
            // 添加模式：创建新策略
            let newStrategy = OptionStrategy(
                symbol: symbol,
                optionType: optionType,
                expirationDate: expirationDate,
                strikePrice: strikePriceValue,
                optionPrice: optionPriceValue,
                averagePricePerShare: avgPriceValue,
                contracts: contractsValue,
                exerciseStatus: exerciseStatus,
                marginCost: marginCostValue,
                exerciseMarketPrice: exerciseMarketPriceValue,
                currentMarketPrice: currentMarketPriceValue
            )
            modelContext.insert(newStrategy)
        }
        
        dismiss()
    }
}

#Preview("Add Mode") {
    AddStrategyView(strategyToEdit: nil)
        .modelContainer(for: OptionStrategy.self, inMemory: true)
}

#Preview("Edit Mode") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: OptionStrategy.self, configurations: config)
    
    let sampleStrategy = OptionStrategy(
        symbol: "AAPL",
        optionType: .coveredCall,
        expirationDate: Date(),
        strikePrice: 150.0,
        optionPrice: 5.50,
        averagePricePerShare: 145.0,
        contracts: 10,
        exerciseStatus: .unknown
    )
    container.mainContext.insert(sampleStrategy)
    
    return AddStrategyView(strategyToEdit: sampleStrategy)
        .modelContainer(container)
}
