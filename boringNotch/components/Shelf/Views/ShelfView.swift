//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showClearControl = false
    @State private var clearArmed = false
    @State private var cornerHovered = false
    @State private var controlHovered = false
    @State private var clearDismissTask: Task<Void, Never>?
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
        .onChange(of: canClear) { _, allowed in
            if !allowed { dismissClearControl() }
        }
        .onDisappear { dismissClearControl() }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    cornerHovered = location.x >= geometry.size.width - (clearArmed ? 116 : 48)
                        && location.y <= 40
                case .ended:
                    cornerHovered = false
                }
                updateClearHover()
            }
            .overlay(alignment: .topTrailing) {
                clearControl.padding(.top, 8).padding(.trailing, 8)
            }
            .contextMenu {
                if canClear {
                    Button("Clear all…") {
                        clearDismissTask?.cancel()
                        withAnimation(clearAnimation) {
                            showClearControl = true
                            clearArmed = true
                        }
                    }
                }
            }
        }
    }

    private var canClear: Bool {
        !tvm.isEmpty && !tvm.isLoading && !selection.isDragging && !vm.anyDropZoneTargeting
            && !SharingStateManager.shared.preventNotchClose
    }

    private var clearAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85)
    }

    private var clearControl: some View {
        Button {
            guard canClear else { return }
            if clearArmed {
                quickLookService.hide()
                withAnimation(clearAnimation) {
                    tvm.removeAll()
                    dismissClearControl()
                }
            } else {
                withAnimation(clearAnimation) { clearArmed = true }
            }
        } label: {
            HStack(spacing: 6) {
                if clearArmed {
                    Text("Clear all")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(width: clearArmed ? 94 : 26, height: 26)
            .foregroundStyle(.white)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canClear)
        .opacity(showClearControl && canClear ? 1 : 0)
        .scaleEffect(showClearControl ? 1 : 0.75, anchor: .topTrailing)
        .allowsHitTesting(showClearControl && canClear)
        .accessibilityHidden(!showClearControl || !canClear)
        .accessibilityLabel(clearArmed ? "Clear all tray items" : "Show Clear all")
        .help(clearArmed ? "Remove all tray items. Original files are kept." : "Show Clear all")
        .onHover { hovered in
            controlHovered = hovered
            updateClearHover()
        }
    }

    private func updateClearHover() {
        clearDismissTask?.cancel()
        guard canClear else { dismissClearControl(); return }
        if cornerHovered || controlHovered {
            withAnimation(clearAnimation) { showClearControl = true }
        } else {
            clearDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                dismissClearControl()
            }
        }
    }

    private func dismissClearControl() {
        clearDismissTask?.cancel()
        clearDismissTask = nil
        withAnimation(clearAnimation) {
            showClearControl = false
            clearArmed = false
            cornerHovered = false
            controlHovered = false
        }
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
