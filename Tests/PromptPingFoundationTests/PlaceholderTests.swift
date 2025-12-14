import Testing
@testable import PromptPingFoundation

@Suite("PromptPingFoundation Tests")
struct PromptPingFoundationTests {
    @Test("Version is defined")
    func versionIsDefined() {
        #expect(!PromptPingFoundation.version.isEmpty)
    }
}
