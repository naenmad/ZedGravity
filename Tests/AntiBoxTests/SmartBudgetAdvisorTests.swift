import XCTest
@testable import ZedGravity

final class SmartBudgetAdvisorTests: XCTestCase {
    func testAccountQuotaCalculations() {
        let calendar = Calendar.current
        let resetDate = calendar.date(byAdding: .day, value: 10, to: Date()) ?? Date()

        let account = Account(
            name: "Test Claude",
            provider: .claude,
            tier: "Scale",
            totalQuotaTokens: 10_000_000,
            usedQuotaTokens: 8_500_000,
            resetDate: resetDate
        )

        XCTAssertEqual(account.remainingTokens, 1_500_000)
        XCTAssertEqual(account.remainingPercentage, 15.0)
        XCTAssertEqual(account.status, .critical)
    }

    func testBudgetAdvisorWithActivePool() {
        let calendar = Calendar.current
        let resetDate = calendar.date(byAdding: .day, value: 5, to: Date()) ?? Date()

        let acc1 = Account(
            name: "Gemini Pro",
            provider: .gemini,
            totalQuotaTokens: 10_000_000,
            usedQuotaTokens: 5_000_000, // 5M remaining
            resetDate: resetDate
        )

        let acc2 = Account(
            name: "Claude Scale",
            provider: .claude,
            totalQuotaTokens: 10_000_000,
            usedQuotaTokens: 5_000_000, // 5M remaining
            resetDate: resetDate
        )

        let recommendation = SmartBudgetAdvisor.shared.calculateRecommendation(accounts: [acc1, acc2])

        XCTAssertEqual(recommendation.totalRemainingTokens, 10_000_000)
        // 10M / 5 days = 2M / day
        XCTAssertEqual(recommendation.recommendedDailyBudget, 2_000_000)
        XCTAssertEqual(recommendation.burnRateStatus, .sustainable)
    }

    func testDepletedPoolAdvisor() {
        let calendar = Calendar.current
        let resetDate = calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date()

        let acc = Account(
            name: "Gemini Empty",
            provider: .gemini,
            totalQuotaTokens: 5_000_000,
            usedQuotaTokens: 5_000_000,
            resetDate: resetDate
        )

        let recommendation = SmartBudgetAdvisor.shared.calculateRecommendation(accounts: [acc])
        XCTAssertEqual(recommendation.totalRemainingTokens, 0)
        XCTAssertEqual(recommendation.recommendedDailyBudget, 0)
        XCTAssertEqual(recommendation.burnRateStatus, .aggressive)
    }
}
