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

    var costUSD: Double {
        ModelPricing.forModel(model).cost(
            input: inputTokens,
            output: outputTokens,
            cacheWrite: cacheWriteTokens,
            cacheRead: cacheReadTokens
        )
    }
}
