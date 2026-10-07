import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    precondition(value(), message)
}
let now = Date(timeIntervalSince1970: 1_800_000_000)
func parse(_ limits: String, account: String = #"{"account":{"type":"chatgpt","planType":"plus"}}"#) throws -> CodexUsageSnapshot {
    try .decodeRPC(account: Data(account.utf8), limits: Data(limits.utf8), now: now)
}
let both = try parse(#"{"rateLimits":{"primary":{"usedPercent":59,"windowDurationMins":300,"resetsAt":1800008400},"secondary":{"usedPercent":18,"windowDurationMins":10080,"resetsAt":1800244800},"credits":{"balance":"0","hasCredits":false,"unlimited":false}},"rateLimitResetCredits":{"availableCount":2,"credits":[]}}"#)
check(both.activeWindow?.label == "5-hour", "Prefer the 5-hour window when both exist")
check(both.activeWindow?.percentageText == "41%", "Show remaining, not used")
check(both.credits?.label == "0", "Reported zero is distinct from unavailable")
check(both.availableResets == 2, "Use authoritative reset count, not detail row count")
check(both.activeWindow?.countdown(at: now) == "2h 20m", "Hour/minute countdown")
let weekly = try parse(#"{"rateLimits":{"primary":{"usedPercent":100,"windowDurationMins":10080,"resetsAt":1800246000},"planType":"pro"}}"#)
check(weekly.activeWindow?.label == "Weekly", "Weekly can be primary with no short window")
check(weekly.activeWindow?.countdown(at: now) == "2d 20h", "Day/hour countdown")
check(weekly.tierLabel == "Pro", "Fresh quota plan wins over account plan")
check(weekly.credits == nil && weekly.availableResets == nil, "Missing does not mean zero")
let blocked = try parse(#"{"rateLimits":{"primary":{"usedPercent":30,"windowDurationMins":300},"secondary":{"usedPercent":100,"windowDurationMins":10080,"resetsAt":1800246000}}}"#)
check(blocked.activeWindow?.label == "Weekly", "An exhausted weekly allowance blocks a usable short window")
let multiple = try parse(#"{"rateLimits":{"primary":{"usedPercent":100,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":20,"windowDurationMins":10080}},"other":{"primary":{"usedPercent":100,"windowDurationMins":15}}}}"#)
check(multiple.activeWindow?.percentageText == "80%", "Use authoritative Codex bucket, without unrelated/legacy duplicates")
let unknown = try parse(#"{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":60},"credits":{"balance":null,"hasCredits":true,"unlimited":true}},"extraFutureField":true}"#)
check(unknown.activeWindow?.label == "1-hour", "Unknown cadence labels are data-driven")
check(unknown.activeWindow?.countdown(at: now) == "—", "Missing reset stays unknown")
check(unknown.credits?.label == "Unlimited", "Honor unlimited credits")
check(CodexUsageFormatting.countdown(until: now, now: now) == "Refreshing", "A reset requires a new read, not an invented 100%")
check(CodexUsageFormatting.countdown(until: now.addingTimeInterval(1), now: now) == "1m", "Round countdown up")
let fractional = CodexQuotaWindow(usedPercent: 99.7, windowDurationMins: 300, resetsAt: nil)
check(fractional.percentageText == "1%", "Do not show 0% for a nonzero remainder")
for used in [-12.0, 0, 100, 120] {
    let window = CodexQuotaWindow(usedPercent: used, windowDurationMins: nil, resetsAt: nil)
    check((0...100).contains(window.remainingPercent), "Clamp percentages")
}
for (account, expected) in [(#"{"account":null}"#, CodexUsageError.signedOut), (#"{"account":{"type":"apiKey"}}"#, .unsupportedAccount)] {
    do { _ = try parse(#"{"rateLimits":{}}"#, account: account); preconditionFailure("Expected setup error") }
    catch let error as CodexUsageError { check(error == expected, "Correct setup error") }
}
let encoded = try JSONEncoder().encode(both)
check(!String(decoding: encoded, as: UTF8.self).contains("email"), "XPC snapshot excludes identity/credential fields")
let roundTrip = try JSONDecoder().decode(CodexUsageSnapshot.self, from: encoded)
check(roundTrip.windows.count == 2, "Snapshot round trip")

let unknownPlan = try parse(#"{"rateLimits":{"planType":"unknown"}}"#)
check(unknownPlan.tierLabel == "Plus", "Unknown quota plan falls back to known account tier")
check(CodexCreditBalance(balance: "0.001", hasCredits: true, unlimited: false).label == "<0.01", "Tiny positive credits do not round to zero")

// Exercise real pipes, JSONL notifications, fragmented responses and bounded cleanup
// with a fake CLI. No Codex login, network request or model task is involved.
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let cli = directory.appendingPathComponent("codex")
let script = #"""
#!/usr/bin/env python3
import sys, json, time
for line in sys.stdin:
    m = json.loads(line)
    if 'id' not in m: continue
    if m['method'] == 'initialize': r = {}
    elif m['method'] == 'account/read': r = {'account': {'type': 'chatgpt', 'planType': 'plus'}}
    elif m['method'] == 'account/rateLimits/read': r = {'rateLimits': {'primary': {'usedPercent': 22, 'windowDurationMins': 300}}}
    else: raise Exception('Unexpected RPC')
    print(json.dumps({'method': 'account/updated', 'params': {}}), flush=True)
    reply = json.dumps({'id': m['id'], 'result': r}) + '\n'
    sys.stdout.write(reply[:8]); sys.stdout.flush(); time.sleep(.01)
    sys.stdout.write(reply[8:]); sys.stdout.flush()
"""#
try script.write(to: cli, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
let probed = try CodexUsageReader.fetch(executable: cli, timeout: 3)
check(probed.activeWindow?.percentageText == "78%", "Fragmented RPC responses and notifications decode correctly")
try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: cli, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
let started = Date()
do { _ = try CodexUsageReader.fetch(executable: cli, timeout: 0.3); preconditionFailure("Expected timeout") }
catch let error as CodexUsageError { check(error == .timeout, "Timeout surfaces accurately") }
check(Date().timeIntervalSince(started) < 2, "Timeout cleanup is bounded")
print("Codex usage: \(checks) checks passed")
