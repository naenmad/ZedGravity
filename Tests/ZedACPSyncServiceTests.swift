import XCTest
@testable import ZedGravity

final class ZedACPSyncServiceTests: XCTestCase {
    func testZedACPInstallationAndRunningDetection() {
        let service = ZedACPSyncService.shared
        XCTAssertTrue(service.isZedInstalled, "Zed should be installed")
        XCTAssertTrue(service.isZedACPInstalled, "Zed ACP should be installed")
        print("Zed ACP Running Status:", service.isZedACPRunning)
    }

    func testGetActiveAccountMatches() {
        let accounts = AntiBoxAccountStore.shared.loadAccounts()
        let (detectedEmail, _) = ZedACPSyncService.shared.getActiveAccount(from: accounts)
        XCTAssertNotNil(detectedEmail)
        print("Now active in Zed ACP:", detectedEmail ?? "none")
    }
}
