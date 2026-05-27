import Foundation

// 1M tokens あたりの USD 単価 (2026 年時点の概算)。
// 公式 docs: https://docs.claude.com/en/docs/about-claude/pricing
struct ModelPricing {
    let input: Double
    let output: Double
    let cacheWrite: Double  // cache creation
    let cacheRead: Double

    static let `default` = ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30)

    static func forModel(_ rawName: String) -> ModelPricing {
        let lower = rawName.lowercased()
        if lower.contains("opus") {
            return ModelPricing(input: 15.0, output: 75.0, cacheWrite: 18.75, cacheRead: 1.50)
        }
        if lower.contains("haiku") {
            return ModelPricing(input: 1.0, output: 5.0, cacheWrite: 1.25, cacheRead: 0.10)
        }
        // sonnet / unknown は sonnet 価格
        return ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30)
    }

    func cost(input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        let i = Double(input)    / 1_000_000 * self.input
        let o = Double(output)   / 1_000_000 * self.output
        let cw = Double(cacheWrite) / 1_000_000 * self.cacheWrite
        let cr = Double(cacheRead)  / 1_000_000 * self.cacheRead
        return i + o + cw + cr
    }
}
