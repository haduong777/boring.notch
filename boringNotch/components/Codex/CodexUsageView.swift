import SwiftUI

struct CodexUsageView: View {
    @ObservedObject private var usage = CodexUsageManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Group {
                if let snapshot = usage.snapshot {
                    content(snapshot, at: context.date)
                } else {
                    setupState
                }
            }
            .onChange(of: context.date) { _, date in
                if let reset = usage.snapshot?.activeWindow?.resetDate, reset <= date {
                    Task { await usage.refreshIfNeeded() }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 120, alignment: .top)
        .task { await usage.refreshIfNeeded() }
    }

    private func content(_ snapshot: CodexUsageSnapshot, at date: Date) -> some View {
        let window = snapshot.activeWindow
        let stale = usage.isStale(at: date)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Codex").font(.headline)
                Text(window?.label ?? "Account usage")
                    .font(.caption).foregroundStyle(.gray)
                Spacer()
                Text(snapshot.tierLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.white.opacity(0.1), in: Capsule())
                    .accessibilityLabel("Account tier: \(snapshot.tierLabel)")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(window.map { "\(stale ? "Last known: " : "")\($0.percentageText) remaining" } ?? "Usage not reported")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if let window, window.remainingPercent == 0 {
                        Text("Limit reached").font(.caption).foregroundStyle(.orange)
                    }
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule().fill(window?.remainingPercent == 0 ? Color.orange : Color.white)
                            .frame(width: geometry.size.width * CGFloat((window?.remainingPercent ?? 0) / 100))
                    }
                }
                .frame(height: 5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(window?.label ?? "Codex") allowance remaining")
                .accessibilityValue(window?.percentageText ?? "Unavailable")
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: window?.remainingPercent)
            }
            .opacity(stale ? 0.55 : 1)

            HStack(alignment: .top, spacing: 20) {
                metric(value: snapshot.availableResets.map { "\(max(0, $0))" } ?? "—", label: "Limit resets")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Available banked limit resets. Monitoring does not consume them.")
                metric(value: snapshot.credits?.label ?? "—", label: "Credits", alignment: .center)
                    .frame(maxWidth: .infinity)
                    .help(snapshot.credits == nil ? "Codex hasn't reported a credit balance." : "Credit balance reported by Codex, separate from included usage.")
                metric(value: window?.countdown(at: date) ?? "—", label: "Until reset", alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help(window?.resetDate.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Reset time unavailable")
            }
            .opacity(stale ? 0.55 : 1)

            Group {
                if stale {
                    Text("Couldn't refresh · showing previous usage")
                } else if let other = snapshot.windows.first(where: { $0 != window }) {
                    Text("\(other.label): \(other.percentageText) · \(other.countdown(at: date))")
                        .accessibilityLabel("\(other.label): \(other.percentageText) remaining, resets in \(other.countdown(at: date))")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.gray)
            .help("Last updated \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        .foregroundStyle(.white)
    }

    private func metric(value: String, label: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value).font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.gray)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value == "—" ? "Unavailable" : value)
    }

    private var setupState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Codex").font(.headline)
                Spacer()
                if usage.isRefreshing { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 12) {
                Image("CodexIcon").renderingMode(.template).resizable().scaledToFit().frame(width: 38, height: 38)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(usage.isRefreshing ? "Checking your allowance" : "Connect your Codex account")
                        .font(.system(size: 13, weight: .medium))
                    Text(usage.error?.message ?? "Reading usage from Codex…")
                        .font(.caption).foregroundStyle(.gray)
                }
                Spacer(minLength: 0)
            }
            Button(usage.setupActionLabel) { usage.openCodex() }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.white)
                .disabled(usage.isPreview)
        }
        .foregroundStyle(.white)
    }
}
