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
    
    @State private var symbol: String = ""
    @State private var optionType: OptionType = .call
    @State private var expirationDate: Date = Date()
    @State private var strikePrice: String = ""
    @State private var optionPrice: String = ""
    @State private var averagePricePerShare: String = ""
    @State private var contracts: String = ""
    @State private var exerciseStatus: ExerciseStatus = .unknown
    
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("股票信息") {
                    TextField("股票代码", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                
                Section("期权信息") {
                    Picker("期权类型", selection: $optionType) {
                        ForEach(OptionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    DatePicker("执行日", selection: $expirationDate, displayedComponents: .date)
                    
                    TextField("执行价", text: $strikePrice)
                        .keyboardType(.decimalPad)
                    
                    TextField("期权价格", text: $optionPrice)
                        .keyboardType(.decimalPad)
                }
                
                Section("持仓信息") {
                    TextField("每股均价", text: $averagePricePerShare)
                        .keyboardType(.decimalPad)
                    
                    TextField("合同数", text: $contracts)
                        .keyboardType(.numberPad)
                }
                
                Section("行权状态") {
                    Picker("是否行权", selection: $exerciseStatus) {
                        ForEach(ExerciseStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("添加策略")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveStrategy()
                    }
                    .disabled(!isFormValid)
                }
            }
            .alert("输入错误", isPresented: $showingError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var isFormValid: Bool {
        !symbol.isEmpty &&
        !strikePrice.isEmpty &&
        !optionPrice.isEmpty &&
        !averagePricePerShare.isEmpty &&
        !contracts.isEmpty
    }
    
    private func saveStrategy() {
        // 验证数值输入
        guard let strikePriceValue = Double(strikePrice),
              let optionPriceValue = Double(optionPrice),
              let avgPriceValue = Double(averagePricePerShare),
              let contractsValue = Int(contracts) else {
            errorMessage = "请确保所有数值输入正确"
            showingError = true
            return
        }
        
        // 验证正数
        guard strikePriceValue > 0,
              optionPriceValue > 0,
              avgPriceValue > 0,
              contractsValue > 0 else {
            errorMessage = "所有数值必须大于0"
            showingError = true
            return
        }
        
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
        
        dismiss()
    }
}

#Preview {
    AddStrategyView()
        .modelContainer(for: OptionStrategy.self, inMemory: true)
}
