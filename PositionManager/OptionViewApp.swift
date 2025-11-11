//
//  PositionManagerApp.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/4/25.
//

import SwiftUI
import SwiftData

@main
struct OptionViewApp: App {
    // 数据模型版本号 - 当模型结构改变时，增加这个版本号以触发数据库重建
    // 设置为 # 以清理包含旧格式数据的数据库
    private static let currentDataVersion = 1
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            OptionStrategy.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        // 检查数据版本
        let savedVersion = UserDefaults.standard.integer(forKey: "DataModelVersion")
        if savedVersion != Self.currentDataVersion {
            // 版本不匹配，删除旧数据库
            print("🔄 检测到数据模型版本变化 (\(savedVersion) -> \(Self.currentDataVersion))，清理旧数据库...")
            
            // 删除数据库文件
            // SwiftData 数据库文件通常存储在 Application Support 目录
            let fileManager = FileManager.default
            if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let storeURL = appSupportURL.appendingPathComponent("default.store")
                let shmURL = appSupportURL.appendingPathComponent("default.store-shm")
                let walURL = appSupportURL.appendingPathComponent("default.store-wal")
                
                try? fileManager.removeItem(at: storeURL)
                try? fileManager.removeItem(at: shmURL)
                try? fileManager.removeItem(at: walURL)
                
                print("✅ 已删除旧数据库文件")
            }
            
            // 更新版本号
            UserDefaults.standard.set(Self.currentDataVersion, forKey: "DataModelVersion")
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // 尝试读取数据以验证数据库是否正常
            // 如果读取失败（比如有旧数据无法解码），会抛出错误
            let context = container.mainContext
            let descriptor = FetchDescriptor<OptionStrategy>()
            do {
                _ = try context.fetch(descriptor)
            } catch {
                // 读取失败，说明数据库中有不兼容的数据，需要清理
                print("⚠️ 数据库读取失败（可能包含旧格式数据）: \(error)")
                print("🔄 清理数据库...")
                
                let fileManager = FileManager.default
                if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let storeURL = appSupportURL.appendingPathComponent("default.store")
                    let shmURL = appSupportURL.appendingPathComponent("default.store-shm")
                    let walURL = appSupportURL.appendingPathComponent("default.store-wal")
                    
                    try? fileManager.removeItem(at: storeURL)
                    try? fileManager.removeItem(at: shmURL)
                    try? fileManager.removeItem(at: walURL)
                }
                
                // 更新版本号
                UserDefaults.standard.set(Self.currentDataVersion, forKey: "DataModelVersion")
                
                // 重新创建容器
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            }
            
            return container
        } catch {
            // 如果创建失败，尝试删除数据库并重新创建
            print("⚠️ 数据库初始化失败: \(error)")
            print("🔄 尝试清理并重建数据库...")
            
            // 删除数据库文件
            let fileManager = FileManager.default
            if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let storeURL = appSupportURL.appendingPathComponent("default.store")
                let shmURL = appSupportURL.appendingPathComponent("default.store-shm")
                let walURL = appSupportURL.appendingPathComponent("default.store-wal")
                
                try? fileManager.removeItem(at: storeURL)
                try? fileManager.removeItem(at: shmURL)
                try? fileManager.removeItem(at: walURL)
            }
            
            // 更新版本号
            UserDefaults.standard.set(Self.currentDataVersion, forKey: "DataModelVersion")
            
            // 重新创建
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // ------------------- ⚠️ 测试数据 - 不需要时注释掉这一行 -------------------
                    addSampleDataIfNeeded()// ------------------- ⚠️ 测试数据 - 不需要时注释掉这一行 -------------------
                    // -------------------⚠️ 测试数据 - 不需要时注释掉这一行 -------------------
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    // MARK: - 测试数据生成
    // ⚠️ 注释掉下面的整个函数来禁用测试数据
    private func addSampleDataIfNeeded() {
        let context = sharedModelContainer.mainContext
        
        // 检查是否已经有数据
        // 使用 try? 来避免因为旧数据格式导致的崩溃
        let fetchDescriptor = FetchDescriptor<OptionStrategy>()
        let existingCount: Int
        do {
            existingCount = try context.fetchCount(fetchDescriptor)
        } catch {
            // 如果读取失败（比如有旧格式数据），返回 0 让系统重新生成测试数据
            print("⚠️ 读取数据失败（可能包含旧格式数据）: \(error)")
            print("🔄 将重新生成测试数据...")
            existingCount = 0
        }
        
        // 如果已经有数据，就不添加测试数据
        if existingCount > 0 {
            print("✅ 已有 \(existingCount) 条数据，跳过测试数据生成")
            return
        }
        
        print("🔧 生成测试数据...")
        
        // 创建日期
        let calendar = Calendar.current
        let today = Date()
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!
        let twoWeeks = calendar.date(byAdding: .day, value: 14, to: today)!
        let oneMonth = calendar.date(byAdding: .month, value: 1, to: today)!
        let twoMonths = calendar.date(byAdding: .month, value: 2, to: today)!
        
        // AAPL 策略 - 不同日期
        let aapl1 = OptionStrategy(
            symbol: "AAPL",
            optionType: .coveredCall,
            expirationDate: nextWeek,
            strikePrice: 180.0,
            optionPrice: 5.50,
            averagePricePerShare: 175.0,
            contracts: 5,
            exerciseStatus: .yes
        )
        
        let aapl2 = OptionStrategy(
            symbol: "AAPL",
            optionType: .cashSecuredPut,
            expirationDate: oneMonth,
            strikePrice: 165.0,
            optionPrice: 4.25,
            averagePricePerShare: 175.0,
            contracts: 3,
            exerciseStatus: .no
        )
        
        let aapl3 = OptionStrategy(
            symbol: "AAPL",
            optionType: .nakedCall,
            expirationDate: twoMonths,
            strikePrice: 185.0,
            optionPrice: 6.00,
            averagePricePerShare: 175.0,
            contracts: 4,
            exerciseStatus: .unknown
        )
        
        // TSLA 策略
        let tsla1 = OptionStrategy(
            symbol: "TSLA",
            optionType: .coveredCall,
            expirationDate: nextWeek,
            strikePrice: 250.0,
            optionPrice: 12.50,
            averagePricePerShare: 240.0,
            contracts: 2,
            exerciseStatus: .yes
        )
        
        let tsla2 = OptionStrategy(
            symbol: "TSLA",
            optionType: .cashSecuredPut,
            expirationDate: twoWeeks,
            strikePrice: 230.0,
            optionPrice: 10.00,
            averagePricePerShare: 240.0,
            contracts: 3,
            exerciseStatus: .no
        )
        
        // 插入所有策略
        let strategies = [
            aapl1, aapl2, aapl3,
            tsla1, tsla2
        ]
        
        for strategy in strategies {
            context.insert(strategy)
        }
        
        // 保存
        do {
            try context.save()
            print("✅ 成功添加 \(strategies.count) 条测试数据")
        } catch {
            print("❌ 保存测试数据失败: \(error)")
        }
    }
}
