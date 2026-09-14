import Testing
import Foundation
@testable import ClaudeCodeMeter

@Suite("Session blocks & weekly window")
struct SessionBlockTests {

    private let hour: TimeInterval = 3600

    // 2026-01-05 (月) 00:00:00 UTC を基準にする。
    private let base = Date(timeIntervalSince1970: 1_767_571_200)

    private func entry(_ offset: TimeInterval,
                       id: String = UUID().uuidString,
                       cacheRead: Int = 0,
                       output: Int = 0) -> UsageEntry {
        UsageEntry(
            id: id,
            timestamp: base.addingTimeInterval(offset),
            model: "claude-opus-4-7",
            inputTokens: 0,
            outputTokens: output,
            cacheWriteTokens: 0,
            cacheReadTokens: cacheRead
        )
    }

    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // MARK: - ブロックの切り方

    @Test func blockStartIsFlooredToTheHour() {
        let blocks = UsageStore.sessionBlocks(entries: [entry(90 * 60)])  // 01:30
        #expect(blocks.count == 1)
        #expect(blocks[0].start == base.addingTimeInterval(hour))         // 01:00
    }

    @Test func entriesWithinFiveHoursOfBlockStartShareABlock() {
        // 00:10 と 04:50。ブロック開始は 00:00 なので両方 5h 未満に収まる。
        let blocks = UsageStore.sessionBlocks(entries: [
            entry(10 * 60), entry(4 * hour + 50 * 60)
        ])
        #expect(blocks.count == 1)
        #expect(blocks[0].messageCount == 2)
    }

    @Test func fiveHoursAfterBlockStartOpensANewBlock() {
        // 00:10 と 05:00。ブロック開始 00:00 からちょうど 5h なので切れる。
        let blocks = UsageStore.sessionBlocks(entries: [
            entry(10 * 60), entry(5 * hour)
        ])
        #expect(blocks.count == 2)
        #expect(blocks[1].start == base.addingTimeInterval(5 * hour))
    }

    @Test func fiveHoursOfSilenceOpensANewBlock() {
        // ブロック開始からは 5h 未満でも、無活動が 5h 続けば切れる…のを確かめるため
        // 00:00 -> 00:30 -> 05:40 と並べる。3 つ目は前の活動から 5h10m あいている。
        let blocks = UsageStore.sessionBlocks(entries: [
            entry(0), entry(30 * 60), entry(5 * hour + 40 * 60)
        ])
        #expect(blocks.count == 2)
        #expect(blocks[0].messageCount == 2)
        #expect(blocks[1].messageCount == 1)
    }

    @Test func blockIsActiveOnlyWithinItsFiveHourWindow() {
        let blocks = UsageStore.sessionBlocks(entries: [entry(10 * 60)])
        let b = blocks[0]
        #expect(UsageStore.isActive(b, at: base.addingTimeInterval(4 * hour)))
        #expect(!UsageStore.isActive(b, at: base.addingTimeInterval(5 * hour)))
    }

    // MARK: - ローリング窓との違い (今回のバグの回帰テスト)

    @Test func sessionCountsOnlyTheCurrentBlockNotARollingFiveHours() {
        // 前ブロック: 00:00〜04:00 に大量に使う (cacheRead 100M)
        // 現ブロック: 05:00 に少しだけ使う (cacheRead 1M)
        // now = 06:00。ローリング 5h (01:00〜06:00) なら前ブロックの大半を巻き込むが、
        // 実ブロックは 05:00 開始なので 05:00 以降だけが数えられるべき。
        var entries: [UsageEntry] = []
        for i in 0..<5 {
            entries.append(entry(Double(i) * hour, id: "old-\(i)", cacheRead: 20_000_000))
        }
        entries.append(entry(5 * hour, id: "new-0", cacheRead: 1_000_000))

        let now = base.addingTimeInterval(6 * hour)
        let s = UsageStore.summarize(
            entries: entries, now: now,
            weeklyResetAnchor: base, calendar: utcCalendar
        )

        #expect(s.sessionMessageCount == 1)
        #expect(s.sessionStartAt == base.addingTimeInterval(5 * hour))
        #expect(s.sessionResetAt == base.addingTimeInterval(10 * hour))
        // 1M cacheRead * $1.50/M = $1.50
        #expect(abs(s.sessionAPICostUSD - 1.50) < 0.001)
        // 週間は全部入るので 101M * $1.50/M = $151.50
        #expect(s.weeklyMessageCount == 6)
        #expect(abs(s.weeklyAPICostUSD - 151.50) < 0.001)
    }

    @Test func noActiveBlockWhenIdleForOverFiveHours() {
        let s = UsageStore.summarize(
            entries: [entry(0)], now: base.addingTimeInterval(9 * hour),
            weeklyResetAnchor: base, calendar: utcCalendar
        )
        #expect(s.sessionStartAt == nil)
        #expect(s.sessionMessageCount == 0)
        #expect(s.sessionAPICostUSD == 0)
    }

    // MARK: - cache read の重み

    @Test func cacheReadWeightScalesPlanCostOnly() {
        // cacheRead 10M ($15) + output 1M ($75) = API $90
        let entries = [entry(0, id: "a", cacheRead: 10_000_000, output: 1_000_000)]
        let s = UsageStore.summarize(
            entries: entries, now: base.addingTimeInterval(hour),
            weeklyResetAnchor: base, calendar: utcCalendar
        )
        #expect(abs(s.sessionAPICostUSD - 90.0) < 0.001)
        #expect(abs(s.sessionCacheReadCostUSD - 15.0) < 0.001)
        // weight 0 → cache read を丸ごと除外
        #expect(abs(s.sessionPlanCostUSD(cacheReadWeight: 0) - 75.0) < 0.001)
        // weight 1 → API 総額と一致
        #expect(abs(s.sessionPlanCostUSD(cacheReadWeight: 1) - 90.0) < 0.001)
        // weight 0.5 → 中間
        #expect(abs(s.sessionPlanCostUSD(cacheReadWeight: 0.5) - 82.5) < 0.001)
    }

    // MARK: - 週次ウィンドウ

    @Test func weeklyWindowStartIsTheMostRecentAnchorBefore() {
        // アンカー = base。now = base + 2日12時間。起点は base のまま。
        let now = base.addingTimeInterval(2 * 24 * hour + 12 * hour)
        let start = UsageStore.weeklyWindowStart(now: now, anchor: base, calendar: utcCalendar)
        #expect(start == base)
    }

    @Test func weeklyWindowStartRollsForwardEverySevenDays() {
        // now = base + 9日 → 起点は base + 7日。
        let now = base.addingTimeInterval(9 * 24 * hour)
        let start = UsageStore.weeklyWindowStart(now: now, anchor: base, calendar: utcCalendar)
        #expect(start == base.addingTimeInterval(7 * 24 * hour))
    }

    @Test func futureAnchorLandsOnTheSameCycle() {
        // 「次回リセット」として未来の日時を入れても、同じ 7 日周期に落ちる。
        // アンカー = base + 2日 (now より未来) なら、起点は base - 5日。
        let now = base
        let anchor = base.addingTimeInterval(2 * 24 * hour)
        let start = UsageStore.weeklyWindowStart(now: now, anchor: anchor, calendar: utcCalendar)
        #expect(start == base.addingTimeInterval(-5 * 24 * hour))
    }

    @Test func weeklyWindowIsAtMostSevenDays() {
        // アンカーが過去・未来どちらでも、ウィンドウ長は必ず (0, 7日] に収まる。
        for anchorDays in [-20, -3, 0, 3, 20] {
            let anchor = base.addingTimeInterval(Double(anchorDays) * 24 * hour + 9 * hour)
            for offsetHours in stride(from: 0, through: 24 * 14, by: 7) {
                let now = base.addingTimeInterval(Double(offsetHours) * hour + 1)
                let start = UsageStore.weeklyWindowStart(now: now, anchor: anchor, calendar: utcCalendar)
                let span = now.timeIntervalSince(start)
                #expect(span > 0)
                #expect(span <= 7 * 24 * hour)
            }
        }
    }

    // MARK: - /usage からの較正

    @Test func calibratedLimitInvertsThePercentage() {
        // 集計額 $66 が実測 31% なら、上限は 66 / 0.31 = $212.90
        let limit = SettingsStore.calibratedLimit(cost: 66.0, observedPercent: 31)
        #expect(limit != nil)
        #expect(abs((limit ?? 0) - 212.90) < 0.01)
        // 較正後の % は実測値に一致する
        #expect(abs(66.0 / (limit ?? 1) * 100 - 31) < 0.01)
    }

    @Test func calibratedLimitRejectsUnusableInput() {
        #expect(SettingsStore.calibratedLimit(cost: 66.0, observedPercent: nil) == nil)
        #expect(SettingsStore.calibratedLimit(cost: 66.0, observedPercent: 0) == nil)
        #expect(SettingsStore.calibratedLimit(cost: 66.0, observedPercent: -5) == nil)
        #expect(SettingsStore.calibratedLimit(cost: 0, observedPercent: 31) == nil)
        #expect(SettingsStore.calibratedLimit(cost: .nan, observedPercent: 31) == nil)
    }

    @Test func weeklyTotalsIgnoreEntriesBeforeTheAnchor() {
        // アンカー = base。base の 3 時間前のエントリは週間から外れる。
        let entries = [
            entry(-3 * hour, id: "before", cacheRead: 10_000_000),
            entry(hour, id: "after", cacheRead: 10_000_000)
        ]
        let s = UsageStore.summarize(
            entries: entries, now: base.addingTimeInterval(2 * hour),
            weeklyResetAnchor: base, calendar: utcCalendar
        )
        #expect(s.weeklyMessageCount == 1)
        #expect(s.weeklyStartAt == base)
        #expect(s.weeklyResetAt == base.addingTimeInterval(7 * 24 * hour))
    }
}
