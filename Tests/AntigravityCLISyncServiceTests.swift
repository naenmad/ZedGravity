import XCTest
@testable import ZedGravity

final class AntigravityCLISyncServiceTests: XCTestCase {
    func testCLIInstallationAndRunningDetection() {
        let service = AntigravityCLISyncService.shared
        XCTAssertTrue(service.isCLIInstalled, "Antigravity CLI or Ghostex should be detected on this machine")
        print("Antigravity CLI Running Status:", service.isGhostexOrCLIRunning)
    }

    func testGetActiveCLIAccount() {
        let accounts = AntiBoxAccountStore.shared.loadAccounts()
        let (detectedEmail, _) = AntigravityCLISyncService.shared.getActiveAccount(from: accounts)
        XCTAssertNotNil(detectedEmail, "Should detect currently active CLI account email")
        print("Now active in Antigravity CLI:", detectedEmail ?? "none")
    }
}
