import XCTest
@testable import Ufrumae

/// Scannt den echten Mac (nur lesen, nichts löschen) und gibt eine Zusammenfassung aus.
/// Läuft nur mit:  TEST_RUNNER_UFRUMAE_LIVE=1 xcodebuild test …
final class LiveScanTests: XCTestCase {
    func testLiveScanSummary() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["UFRUMAE_LIVE"] == "1", "Nur auf Wunsch")
        let rules = RuleSnapshot()
        let cats = CategoryID.allCases.filter { ProcessInfo.processInfo.environment["UFRUMAE_SLOW"] == "1" || !$0.isSlow }
        await ScanEngine.run(cats, rules: rules) { r in
            let sel = r.items.filter(\.preselected)
            print("LIVE| \(r.category.title): \(r.items.count) Funde, \(r.totalSize.bytes) gesamt, vorgewählt \(sel.count) = \(sel.reduce(0) { $0 + $1.size }.bytes), \(String(format: "%.1f", r.duration))s \(r.notice ?? "")")
            for i in r.items.prefix(8) {
                print("LIVE|    [\(i.preselected ? "x" : " ")] \(i.title) – \(i.size.bytes) – \(i.method.label) \(i.warning ?? "")")
            }
        }
    }
}
