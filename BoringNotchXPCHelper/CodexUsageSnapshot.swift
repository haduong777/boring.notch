import Foundation

// Shared by the app and helper. Only these display fields cross the XPC boundary.
struct CodexUsageSnapshot: Codable, Sendable {
    let fetchedAt: Date
    let plan: String?
    let windows: [CodexQuotaWindow]
    let credits: CodexCreditBalance?
    let availableResets: Int?

    var activeWindow: CodexQuotaWindow? {
        // A depleted weekly window can block a still-available five-hour window.
        // If both are depleted, the later reset is the one that gates recovery.
        let exhausted = windows.filter { $0.remainingPercent == 0 }
        if let blocking = exhausted.max(by: { ($0.resetDate ?? .distantPast) < ($1.resetDate ?? .distantPast) }) {
            return blocking
        }
        return windows.first { $0.durationMinutes == 300 }
            ?? windows.first { $0.durationMinutes == 10_080 }
            ?? windows.first
    }

    var tierLabel: String {
        switch plan {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite": return "Pro Lite"
        case "promax": return "Pro Max"
        case "team", "business", "self_serve_business_prolite", "self_serve_business_usage_based": return "Business"
        case "edu", "edu_plus", "edu_pro": return "Edu"
        case "enterprise", "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based": return "Enterprise"
        default: return "Codex"
        }
    }

    static func decodeRPC(account: Data, limits: Data, now: Date = Date()) throws -> Self {
        let decoder = JSONDecoder()
        let account = try decoder.decode(CodexAccountResponse.self, from: account)
        guard let identity = account.account else { throw CodexUsageError.signedOut }
        guard identity.type != "apiKey", identity.type != "amazonBedrock" else {
            throw CodexUsageError.unsupportedAccount
        }
        let response = try decoder.decode(CodexRateLimitsResponse.self, from: limits)
        let bucket = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        let reportedPlan = bucket.planType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = reportedPlan.flatMap { $0.isEmpty || $0 == "unknown" ? nil : $0 } ?? identity.planType
        // Keep the authoritative Codex bucket together; never combine unrelated
        // model quotas or duplicate it with the backward-compatible response.
        return Self(fetchedAt: now, plan: plan,
                    windows: [bucket.primary, bucket.secondary].compactMap { $0 },
                    credits: bucket.credits, availableResets: response.rateLimitResetCredits?.availableCount)
    }
}

struct CodexQuotaWindow: Codable, Sendable, Equatable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Int64?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    var durationMinutes: Int? { windowDurationMins }
    var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: Double($0)) } }
    var label: String {
        guard let minutes = durationMinutes else { return "Usage window" }
        if minutes == 10_080 { return "Weekly" }
        if minutes == 300 { return "5-hour" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)-day" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
        return "\(minutes)-minute"
    }
    var percentageText: String { "\(remainingPercent > 0 ? max(1, Int(remainingPercent.rounded())) : 0)%" }
    func countdown(at now: Date) -> String {
        guard let resetDate else { return "—" }
        return CodexUsageFormatting.countdown(until: resetDate, now: now)
    }
}

struct CodexCreditBalance: Codable, Sendable {
    let balance: String?
    let hasCredits: Bool
    let unlimited: Bool

    var label: String {
        if unlimited { return "Unlimited" }
        guard let balance, let value = Decimal(string: balance, locale: Locale(identifier: "en_US_POSIX")) else {
            return hasCredits ? "Available" : "—"
        }
        if value > 0 && value < Decimal(string: "0.01")! { return "<0.01" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? balance
    }
}

enum CodexUsageFormatting {
    static func countdown(until reset: Date, now: Date) -> String {
        let minutes = max(0, Int(ceil(reset.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "Refreshing" }
        if minutes >= 1_440 { return "\(minutes / 1_440)d \((minutes % 1_440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

enum CodexUsageError: String, Error, Sendable {
    case notInstalled, signedOut, unsupportedAccount, timeout, unavailable, invalidResponse, helperUnavailable

    var message: String {
        switch self {
        case .notInstalled: return "Install Codex to see your usage here."
        case .signedOut: return "Sign in to Codex, then refresh."
        case .unsupportedAccount: return "Usage limits require a ChatGPT account."
        case .timeout: return "Codex took too long to respond. Try refreshing."
        case .unavailable: return "Codex usage is unavailable. Try refreshing."
        case .invalidResponse: return "Update Codex, then refresh your usage."
        case .helperUnavailable: return "Couldn't connect to the usage reader. Try refreshing."
        }
    }
}

private struct CodexAccountResponse: Decodable {
    struct Account: Decodable { let type: String; let planType: String? }
    let account: Account?
}
private struct CodexRateLimitsResponse: Decodable {
    struct Bucket: Decodable {
        let primary: CodexQuotaWindow?
        let secondary: CodexQuotaWindow?
        let credits: CodexCreditBalance?
        let planType: String?
    }
    struct ResetCredits: Decodable { let availableCount: Int }
    let rateLimits: Bucket
    let rateLimitsByLimitId: [String: Bucket]?
    let rateLimitResetCredits: ResetCredits?
}
