import Testing
@testable import Tabby

@Suite("Update check: version comparison")
struct UpdateCheckerTests {
    @Test("Newer versions are detected", arguments: [
        ("0.2.0", "0.1.0"),
        ("0.1.1", "0.1.0"),
        ("1.0.0", "0.9.9"),
        ("0.10.0", "0.9.3"),
        ("0.1.0.1", "0.1.0"),
    ])
    func newer(candidate: String, current: String) {
        #expect(UpdateChecker.isNewer(candidate, than: current))
    }

    @Test("Same or older versions are not offered", arguments: [
        ("0.1.0", "0.1.0"),
        ("0.1", "0.1.0"),
        ("0.0.9", "0.1.0"),
        ("0.9.3", "0.10.0"),
    ])
    func notNewer(candidate: String, current: String) {
        #expect(!UpdateChecker.isNewer(candidate, than: current))
    }
}
