import AppKit
import Combine
import Foundation

@MainActor
final class CodexUsageManager: ObservableObject {
    static let shared = CodexUsageManager()

    @Published private(set) var snapshot: CodexUsageSnapshot?
    @Published private(set) var error: CodexUsageError?
    @Published private(set) var isRefreshing = false
    private(set) var isPreview = false
    private var previewStale = false
    private var pollingTask: Task<Void, Never>?
    private var wakeObserver: AnyCancellable?

    init() {
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--codex-preview"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
            isPreview = true
            loadPreview(ProcessInfo.processInfo.arguments[index + 1])
            Task { BoringViewCoordinator.shared.currentView = .codex }
            return
        }
        #endif
        wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in Task { @MainActor in await self?.refresh() } }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(self?.error == nil ? 120 : 300)) }
                catch { return }
            }
        }
    }

    func isStale(at date: Date) -> Bool {
        guard let snapshot else { return false }
        return previewStale || (!isPreview && (error != nil || date.timeIntervalSince(snapshot.fetchedAt) > 300))
    }

    func tabLabel(at date: Date) -> String {
        guard let snapshot, !isStale(at: date) else { return "—" }
        guard let window = snapshot.activeWindow else { return snapshot.credits?.unlimited == true ? "∞" : "—" }
        return window.remainingPercent > 0 ? window.percentageText : window.countdown(at: date)
    }

    func refreshIfNeeded() async {
        guard !isPreview else { return }
        let now = Date()
        let crossedReset = snapshot?.activeWindow?.resetDate.map {
            $0 <= now && (snapshot?.fetchedAt ?? .distantFuture) < $0
        } ?? false
        if snapshot == nil || now.timeIntervalSince(snapshot!.fetchedAt) > 60 || crossedReset { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing, !isPreview else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            snapshot = try await XPCHelperClient.shared.readCodexUsage()
            error = nil
        } catch {
            let reason = (error as? CodexUsageError) ?? .helperUnavailable
            self.error = reason
            if reason == .signedOut || reason == .unsupportedAccount { snapshot = nil }
        }
    }

    private var desktopAppURL: URL? {
        ["com.openai.codex", "com.openai.chat"].compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }.first
    }

    var setupActionLabel: String { desktopAppURL == nil ? "Setup guide" : "Open Codex" }

    func openCodex() {
        if let url = desktopAppURL {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else if let url = URL(string: "https://learn.chatgpt.com/docs/quickstart") {
            NSWorkspace.shared.open(url)
        }
    }

    #if DEBUG
    private func loadPreview(_ scenario: String) {
        let now = Date()
        func window(_ used: Double, minutes: Int, hoursUntilReset: Double) -> CodexQuotaWindow {
            .init(usedPercent: used, windowDurationMins: minutes,
                  resetsAt: Int64(now.addingTimeInterval(hoursUntilReset * 3_600).timeIntervalSince1970))
        }
        if scenario == "signed-out" { error = .signedOut; return }
        if scenario == "missing-cli" { error = .notInstalled; return }
        let weekly = scenario == "weekly" || scenario == "exhausted-weekly"
        let exhausted = scenario.hasPrefix("exhausted")
        let windows = weekly
            ? [window(exhausted ? 100 : 54, minutes: 10_080, hoursUntilReset: 68.333)]
            : [window(exhausted ? 100 : 59, minutes: 300, hoursUntilReset: 2.333),
               window(18, minutes: 10_080, hoursUntilReset: 148)]
        snapshot = .init(fetchedAt: now, plan: weekly ? "pro" : "plus", windows: windows,
                         credits: scenario == "unknown-credits" ? nil : .init(balance: "1250", hasCredits: true, unlimited: false),
                         availableResets: scenario == "unknown-credits" ? nil : 2)
        if scenario == "stale" { previewStale = true; error = .unavailable }
    }
    #endif
}
