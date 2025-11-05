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
    @State private var optionType: OptionType = .call
    @State private var expirationDate: Date = Date()
    @State private var strikePrice: String = ""
    @State private var optionPrice: String = ""
    @State private var averagePricePerShare: String = ""
    @State private var contracts: String = ""
    @State private var exerciseStatus: ExerciseStatus = .unknown
    
    // Validation states
    @State private var strikePriceError: Bool = false
    @State private var optionPriceError: Bool = false
    @State private var avgPriceError: Bool = false
    @State private var contractsError: Bool = false
    
    // Focus states
    @FocusState private var focusedField: Field?
    
    enum Field {
        case symbol, strikePrice, optionPrice, avgPrice, contracts
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
                            .onChange(of: strikePrice) { oldValue, newValue in
                                validateStrikePrice()
                            }
                        
                        if strikePriceError {
                            Text("Please enter a valid positive number")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Option Premium", text: $optionPrice)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .optionPrice)
                            .onChange(of: optionPrice) { oldValue, newValue in
                                validateOptionPrice()
                            }
                        
                        if optionPriceError {
                            Text("Please enter a valid positive number")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                Section("Position Information") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Average Price Per Share", text: $averagePricePerShare)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .avgPrice)
                            .onChange(of: averagePricePerShare) { oldValue, newValue in
                                validateAvgPrice()
                            }
                        
                        if avgPriceError {
                            Text("Please enter a valid positive number")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Number of Contracts", text: $contracts)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .contracts)
                            .onChange(of: contracts) { oldValue, newValue in
                                validateContracts()
                            }
                        
                        if contractsError {
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
                }
            }
            .navigationTitle(isEditMode ? "Edit Strategy" : "Add Strategy")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // 使用 task 替代 onAppear，确保在视图准备好后加载数据
                loadStrategyData()
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
    }
    
    // Validation functions
    private func validateStrikePrice() {
        // Don't show error if field is empty
        if strikePrice.isEmpty {
            strikePriceError = false
            return
        }
        
        // Show error if value is invalid or not positive
        if let value = Double(strikePrice), value > 0 {
            strikePriceError = false
        } else {
            strikePriceError = true
        }
    }
    
    private func validateOptionPrice() {
        // Don't show error if field is empty
        if optionPrice.isEmpty {
            optionPriceError = false
            return
        }
        
        // Show error if value is invalid or not positive
        if let value = Double(optionPrice), value > 0 {
            optionPriceError = false
        } else {
            optionPriceError = true
        }
    }
    
    private func validateAvgPrice() {
        // Don't show error if field is empty
        if averagePricePerShare.isEmpty {
            avgPriceError = false
            return
        }
        
        // Show error if value is invalid or not positive
        if let value = Double(averagePricePerShare), value > 0 {
            avgPriceError = false
        } else {
            avgPriceError = true
        }
    }
    
    private func validateContracts() {
        // Don't show error if field is empty
        if contracts.isEmpty {
            contractsError = false
            return
        }
        
        // Show error if value is invalid or not positive
        if let value = Int(contracts), value > 0 {
            contractsError = false
        } else {
            contractsError = true
        }
    }
    
    private var isFormValid: Bool {
        !symbol.isEmpty &&
        !strikePrice.isEmpty &&
        !optionPrice.isEmpty &&
        !averagePricePerShare.isEmpty &&
        !contracts.isEmpty &&
        !strikePriceError &&
        !optionPriceError &&
        !avgPriceError &&
        !contractsError
    }
    
    private func saveStrategy() {
        // Validate all fields one more time
        validateStrikePrice()
        validateOptionPrice()
        validateAvgPrice()
        validateContracts()
        
        // If there are any errors, don't save
        guard !strikePriceError && !optionPriceError && !avgPriceError && !contractsError else {
            return
        }
        
        // Parse values (we know they're valid at this point)
        guard let strikePriceValue = Double(strikePrice),
              let optionPriceValue = Double(optionPrice),
              let avgPriceValue = Double(averagePricePerShare),
              let contractsValue = Int(contracts) else {
            return
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
                exerciseStatus: exerciseStatus
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
        optionType: .call,
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
