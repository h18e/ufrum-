import XCTest
@testable import Ufrumae

final class RuleTests: XCTestCase {

    // MARK: DeviceSupport

    func testDeviceSupportKeepsNewestPerModel() {
        let names = [
            "iPhone12,1 27.0.1 (24A446)",
            "iPhone13,2 26.6.1 (23G83)",
            "iPhone13,2 26.6.2 (23G90)",
            "iPhone13,2 27.0.1 (24A446)",
            "iPhone14,2 18.1.1 (22B91)",
            "iPhone14,2 26.6.1 (23G83)",
            "iPhone14,2 27.0.1 (24A446)",
        ]
        let remove = DeviceSupportScanner.namesToRemove(names)
        XCTAssertEqual(remove, [
            "iPhone13,2 26.6.1 (23G83)", "iPhone13,2 26.6.2 (23G90)",
            "iPhone14,2 18.1.1 (22B91)", "iPhone14,2 26.6.1 (23G83)",
        ])
    }

    func testDeviceSupportOldNamingWithoutModel() {
        let remove = DeviceSupportScanner.namesToRemove(["17.0 (21A329)", "17.5.1 (21F90)", "9.3 (13E230)"])
        XCTAssertEqual(remove, ["17.0 (21A329)", "9.3 (13E230)"])
    }

    func testVersionCompareIsNumeric() {
        XCTAssertTrue(Version.isLess("9.3", "17.0"))
        XCTAssertTrue(Version.isLess("26.6.1", "26.6.2"))
        XCTAssertFalse(Version.isLess("27.0", "27"))
    }

    // MARK: Archives

    func testArchivesKeepNewestThreePerApp() {
        func a(_ name: String, _ days: Double) -> ArchivesScanner.Archive {
            .init(url: URL(fileURLWithPath: "/tmp/\(name)-\(days).xcarchive"), app: name, bundleID: "ch.test.\(name)",
                  date: Date(timeIntervalSince1970: days * 86400), version: "")
        }
        let archives = [a("Voki", 1), a("Voki", 2), a("Voki", 3), a("Voki", 4), a("Voki", 5), a("Hirni", 1)]
        let remove = ArchivesScanner.toRemove(archives, keep: 3)
        XCTAssertEqual(remove, [archives[0].url, archives[1].url])
    }

    // MARK: Simulator-Runtimes

    func testOutdatedRuntimes() {
        typealias R = SimulatorRuntimesScanner.Runtime
        let rs = [
            R(identifier: "a", version: "26.0", build: nil, platformIdentifier: "ios", sizeBytes: 1, deletable: true, state: nil, lastUsedAt: nil),
            R(identifier: "b", version: "27.2", build: nil, platformIdentifier: "ios", sizeBytes: 1, deletable: true, state: nil, lastUsedAt: nil),
            R(identifier: "c", version: "27.0", build: nil, platformIdentifier: "watch", sizeBytes: 1, deletable: true, state: nil, lastUsedAt: nil),
        ]
        XCTAssertEqual(SimulatorRuntimesScanner.outdated(rs), ["a"])
    }

    // MARK: Reste alter Apps

    func testBundleIDParsing() {
        XCTAssertEqual(AppLeftoversScanner.bundleID(from: "com.spotify.client.plist"), "com.spotify.client")
        XCTAssertEqual(AppLeftoversScanner.bundleID(from: "UBF8T346G9.com.microsoft.teams"), "com.microsoft.teams")
        XCTAssertEqual(AppLeftoversScanner.bundleID(from: "group.com.firma.app"), "com.firma.app")
        XCTAssertNil(AppLeftoversScanner.bundleID(from: "com.apple.Safari"))
        XCTAssertNil(AppLeftoversScanner.bundleID(from: "Google"))
        XCTAssertNil(AppLeftoversScanner.bundleID(from: "Adobe"))
    }

    func testInstalledMatchingIncludesHelpers() {
        let installed: Set<String> = ["com.firma.app"]
        XCTAssertTrue(AppLeftoversScanner.isInstalled("com.firma.app.helper", installed: installed))
        XCTAssertTrue(AppLeftoversScanner.isInstalled("COM.FIRMA.APP", installed: installed))
        XCTAssertFalse(AppLeftoversScanner.isInstalled("com.firma.other", installed: installed))
    }

    // MARK: Sicherheit

    func testSafetyGuard() {
        let home = URL(fileURLWithPath: "/Users/test")
        func check(_ p: String, _ prot: [String] = []) -> SafetyGuard.Verdict {
            SafetyGuard.check(URL(fileURLWithPath: p), home: home, protectedPaths: prot)
        }
        XCTAssertEqual(check("/Users/test/Library/Caches/com.foo"), .allowed)
        XCTAssertNotEqual(check("/Users/test/Library/Caches"), .allowed)
        XCTAssertNotEqual(check("/Users/test"), .allowed)
        XCTAssertNotEqual(check("/Applications/Xcode.app"), .allowed)
        XCTAssertNotEqual(check("/Users/other/Library/Caches/x"), .allowed)
        XCTAssertNotEqual(check("/Users/test/Pictures/Fotos.photoslibrary/originals/a.jpg"), .allowed)
        XCTAssertNotEqual(check("/Users/test/Downloads/wichtig/a.pdf", ["/Users/test/Downloads/wichtig"]), .allowed)
        // Elternordner eines geschützten Pfads darf auch nicht weg
        XCTAssertNotEqual(check("/Users/test/Downloads/wichtig", ["/Users/test/Downloads/wichtig/a.pdf"]), .allowed)
        XCTAssertEqual(check("/Users/test/Downloads/anderes.zip", ["/Users/test/Downloads/wichtig"]), .allowed)
    }

    func testDryRunDeletesNothing() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appending(path: "Library/Caches/ch.hebera.ufrumae.tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let item = CleanupItem(category: .caches, url: dir, title: "Test", size: 10, method: .direct, preselected: true)

        let dry = await Cleaner(dryRun: true, home: home, protectedPaths: []).clean([item])
        XCTAssertEqual(dry.processed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path), "Probelauf darf nichts löschen")

        let real = await Cleaner(dryRun: false, home: home, protectedPaths: []).clean([item])
        XCTAssertEqual(real.processed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testProtectedPathIsNeverDeleted() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appending(path: "Library/Caches/ch.hebera.ufrumae.tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let item = CleanupItem(category: .caches, url: dir, title: "Test", size: 10, method: .direct, preselected: true)
        let out = await Cleaner(dryRun: false, home: home, protectedPaths: [dir.path]).clean([item])
        XCTAssertEqual(out.processed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }
}
