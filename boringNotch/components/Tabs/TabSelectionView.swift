//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Codex", icon: "CodexIcon", view: .codex)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var usage = CodexUsageManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var showShelf = true
    var showCodex = true
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.filter {
                switch $0.view {
                case .home: return true
                case .shelf: return showShelf
                case .codex: return showCodex
                }
            }) { tab in
                    Group {
                        if tab.view == .codex {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                Button {
                                    select(tab.view)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image("CodexIcon").renderingMode(.template).resizable().scaledToFit()
                                            .frame(width: 19, height: 19)
                                            .accessibilityHidden(true)
                                        Text(usage.tabLabel(at: context.date))
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .monospacedDigit().lineLimit(1)
                                    }
                                    .padding(.horizontal, 10)
                                    .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Codex usage")
                                .accessibilityValue(usage.tabLabel(at: context.date))
                                .accessibilityAddTraits(coordinator.currentView == .codex ? .isSelected : [])
                                .help("Codex usage and reset time")
                            }
                        } else {
                            TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                                select(tab.view)
                            }
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }

    private func select(_ view: NotchViews) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            coordinator.currentView = view
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
