import Foundation

struct UsageEntry: Identifiable, Hashable {
    let id: String          // messageId (dedup key)
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens
    }

    // API 課金相当の総額。cache read も定価で入る。
    var costUSD: Double {
        ModelPricing.forModel(model).cost(
            input: inputTokens,
            output: outputTokens,
            cacheWrite: cacheWriteTokens,
            cacheRead: cacheReadTokens
        )
    }

    // costUSD のうち cache read が占める分。
    // プラン消費の推定では cacheReadWeight で割り引くため、内訳を分けて持つ。
    var cacheReadCostUSD: Double {
        Double(cacheReadTokens) / 1_000_000 * ModelPricing.forModel(model).cacheRead
    }
}
