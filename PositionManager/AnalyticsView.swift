//
//  AnalyticsView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/5/25.
//

import SwiftUI
import SwiftData

struct AnalyticsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        RollCalculatorView()
                    } label: {
                        ToolRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Roll Calculator",
                            description: "Calculate returns when rolling options",
                            color: .blue
                        )
                    }
                } header: {
                    Text("Options Tools")
                } footer: {
                    Text("Tools for analyzing and planning option strategies")
                }
                
                Section {
                    ToolRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Break-Even Analysis",
                        description: "Coming Soon",
                        color: .green
                    )
                    .foregroundStyle(.secondary)
                    
                    ToolRow(
                        icon: "arrow.up.arrow.down",
                        title: "Volatility Calculator",
                        description: "Coming Soon",
                        color: .orange
                    )
                    .foregroundStyle(.secondary)
                    
                    ToolRow(
                        icon: "calendar.badge.clock",
                        title: "Time Decay Simulator",
                        description: "Coming Soon",
                        color: .purple
                    )
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Advanced Tools")
                } footer: {
                    Text("More analysis tools coming in future updates")
                }
            }
        }
    }
}

// MARK: - Tool Row Component
struct ToolRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AnalyticsView()
}
