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
            MyStrategyView()
                .tabItem {
                    Label("My Strategy", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(0)
            
            PortfolioView()
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

// Placeholder view for future pages
struct PlaceholderView: View {
    let title: String
    
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Coming Soon",
                systemImage: "hammer",
                description: Text("\(title) feature is under development")
            )
            .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: OptionStrategy.self, inMemory: true)
}
