//
//  ContentView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/4/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            StrategyInfoView()
                .tabItem {
                    Label("Strategy Info", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(0)
            
            // 未来可以添加更多页面
            PlaceholderView(title: "Portfolio")
                .tabItem {
                    Label("Portfolio", systemImage: "briefcase")
                }
                .tag(1)
            
            PlaceholderView(title: "Analytics")
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
                .tag(2)
        }
    }
}

// 占位视图，用于未来的页面
struct PlaceholderView: View {
    let title: String
    
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "即将推出",
                systemImage: "hammer",
                description: Text("\(title) 功能正在开发中")
            )
            .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: OptionStrategy.self, inMemory: true)
}
