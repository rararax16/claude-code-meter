import Testing
import Foundation
@testable import ClaudeCodeMeter

@Suite("Pricing & UsageEntry")
struct PricingTests {

    @Test func sonnetPricingDefaultForUnknown() {
        let p = ModelPricing.forModel("claude-fizz-buzz")
        #expect(p.input == 3.0)
        #expect(p.output == 15.0)
    }

    @Test func opusPricingHigher() {
        let p = ModelPricing.forModel("claude-opus-4-7")
        #expect(p.input == 15.0)
        #expect(p.output == 75.0)
    }

    @Test func haikuPricingCheapest() {
        let p = ModelPricing.forModel("claude-haiku-4-5")
        #expect(p.input == 1.0)
        #expect(p.output == 5.0)
    }

    @Test func costCalculationForOpus() {
        // 1M input + 1M output トークンの Opus = $15 + $75 = $90
        let entry = UsageEntry(
            id: "x", timestamp: Date(),
            model: "claude-opus-4-7",
            inputTokens: 1_000_000, outputTokens: 1_000_000,
            cacheWriteTokens: 0, cacheReadTokens: 0
        )
        #expect(entry.costUSD == 90.0)
    }

    @Test func planLimitsAreDistinct() {
        // 単純に "Pro < Max5x < Max20x" の順を確認 (具体額は変わり得るので不等号のみ)
        let pro = Plan.pro.defaultWeeklyLimitUSD ?? 0
        let max5 = Plan.max5x.defaultWeeklyLimitUSD ?? 0
        let max20 = Plan.max20x.defaultWeeklyLimitUSD ?? 0
        #expect(pro < max5)
        #expect(max5 < max20)
    }

    @Test func customPlanHasNilDefaults() {
        #expect(Plan.custom.defaultSessionLimitUSD == nil)
        #expect(Plan.custom.defaultWeeklyLimitUSD == nil)
    }
}
