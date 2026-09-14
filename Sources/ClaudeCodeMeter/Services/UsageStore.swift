import Foundation
import Combine
import SwiftUI

enum DisplayMode: String, CaseIterable, Codable, Identifiable {
    case sessionPercent
    case weeklyPercent

    var id: String { rawValue }
    var label: String {
        switch self {
        case .sessionPercent: return "セッション %"
        case .weeklyPercent:  return "週間 %"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var plan: Plan {
        didSet { UserDefaults.standard.set(plan.rawValue, forKey: "plan") }
    }
    @Published var customSessionLimitUSD: Double {
        didSet { UserDefaults.standard.set(customSessionLimitUSD, forKey: "customSessionLimitUSD") }
    }
    @Published var customWeeklyLimitUSD: Double {
        didSet { UserDefaults.standard.set(customWeeklyLimitUSD, forKey: "customWeeklyLimitUSD") }
    }
    @Published var displayMode: DisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: "displayMode") }
    }
    @Published var refreshIntervalSeconds: Double {
        didSet { UserDefaults.standard.set(refreshIntervalSeconds, forKey: "refreshIntervalSeconds") }
    }
    // プラン消費の推定で cache read をどれだけ数えるか (0 = 数えない, 1 = API 定価で数える)。
    // Claude Code の /usage と突き合わせると全額計上が実測に一番近いので既定は 1。
    // (Anthropic 自身も「Longer sessions are more expensive even when cached」と表示する)
    @Published var cacheReadWeight: Double {
        didSet { UserDefaults.standard.set(cacheReadWeight, forKey: "cacheReadWeight") }
    }
    // 週次上限がリセットされる日時。ここから 7 日周期でウィンドウを切る。
    // 未来の日時 (次回リセット) を入れても過去の日時を入れても同じ周期に落ちる。
    @Published var weeklyResetAnchor: Date {
        didSet {
            UserDefaults.standard.set(weeklyResetAnchor.timeIntervalSince1970,
                                      forKey: "weeklyResetAnchor")
        }
    }

    init() {
        let ud = UserDefaults.standard
        self.plan = Plan(rawValue: ud.string(forKey: "plan") ?? "") ?? .max5x
        self.customSessionLimitUSD = ud.object(forKey: "customSessionLimitUSD") as? Double ?? 50.0
        self.customWeeklyLimitUSD = ud.object(forKey: "customWeeklyLimitUSD") as? Double ?? 300.0
        self.displayMode = DisplayMode(rawValue: ud.string(forKey: "displayMode") ?? "") ?? .sessionPercent
        self.refreshIntervalSeconds = ud.object(forKey: "refreshIntervalSeconds") as? Double ?? 60.0
        self.cacheReadWeight = (ud.object(forKey: "cacheReadWeight") as? Double ?? 1.0).clamped(to: 0...1)
        self.weeklyResetAnchor = Self.storedAnchor(ud)
    }

    // 保存が無ければ「次の月曜 00:00」を仮の起点にする。
    // 正しい値は /usage か claude.ai の使用量画面を見て設定してもらう。
    private static func storedAnchor(_ ud: UserDefaults) -> Date {
        if let stored = ud.object(forKey: "weeklyResetAnchor") as? Double {
            return Date(timeIntervalSince1970: stored)
        }
        var c = DateComponents()
        c.weekday = 2
        c.hour = 0
        c.minute = 0
        return Calendar.current.nextDate(after: Date(), matching: c, matchingPolicy: .nextTime)
            ?? Date()
    }

    // 実測 % と自前の集計額から上限を逆算する。
    // 「集計額が上限の observedPercent % にあたる」ので、上限 = 集計額 / (% / 100)。
    // 逆算できない入力 (0 以下, 非有限) では nil を返して呼び出し側で無視させる。
    nonisolated static func calibratedLimit(cost: Double, observedPercent: Double?) -> Double? {
        guard let p = observedPercent, p > 0, p.isFinite, cost > 0, cost.isFinite else {
            return nil
        }
        let limit = cost / (p / 100)
        guard limit.isFinite else { return nil }
        return (limit * 100).rounded() / 100
    }

    // /usage の実測値から上限を逆算して Custom に保存する (プラン既定値は上書きしない)。
    func calibrate(sessionPercent: Double?, weeklyPercent: Double?, summary: UsageSummary) {
        let w = cacheReadWeight
        if let limit = Self.calibratedLimit(
            cost: summary.sessionPlanCostUSD(cacheReadWeight: w), observedPercent: sessionPercent
        ) {
            customSessionLimitUSD = limit
        }
        if let limit = Self.calibratedLimit(
            cost: summary.weeklyPlanCostUSD(cacheReadWeight: w), observedPercent: weeklyPercent
        ) {
            customWeeklyLimitUSD = limit
        }
        plan = .custom
    }

    var sessionLimitUSD: Double {
        if plan == .custom { return customSessionLimitUSD }
        // plan != .custom なら Plan.defaultSessionLimitUSD は必ず non-nil。
        // それでも nil なら 0 を返して "上限0=0%" の安全側にフォールバック。
        return plan.defaultSessionLimitUSD ?? 0
    }

    var weeklyLimitUSD: Double {
        if plan == .custom { return customWeeklyLimitUSD }
        return plan.defaultWeeklyLimitUSD ?? 0
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// Claude Code の 5 時間セッションブロック 1 個ぶんの集計。
// ブロックは「最初のメッセージの時刻を UTC 時間単位に切り下げた時点」から始まり、
// ブロック開始から 5 時間経過するか、5 時間無活動が続くと次のブロックに移る。
struct SessionBlock: Equatable {
    let start: Date            // 時間単位に切り下げ済み
    var lastActivity: Date
    var apiCostUSD: Double = 0
    var cacheReadCostUSD: Double = 0
    var messageCount: Int = 0

    mutating func add(_ e: UsageEntry) {
        apiCostUSD += e.costUSD
        cacheReadCostUSD += e.cacheReadCostUSD
        messageCount += 1
        if e.timestamp > lastActivity { lastActivity = e.timestamp }
    }
}

// reload() の最後に precompute される、表示で使うサマリ。
// コストは「API 課金相当の総額」と「そのうち cache read 分」を分けて保持する。
// プラン消費の推定値は cacheReadWeight を掛けて表示側で合成するので、
// 係数を変えても再スキャンが要らない。
struct UsageSummary: Equatable {
    var sessionAPICostUSD: Double = 0
    var sessionCacheReadCostUSD: Double = 0
    var weeklyAPICostUSD: Double = 0
    var weeklyCacheReadCostUSD: Double = 0
    var sessionMessageCount: Int = 0
    var weeklyMessageCount: Int = 0
    var sessionStartAt: Date? = nil     // アクティブなブロックが無ければ nil
    var sessionResetAt: Date? = nil
    var weeklyStartAt: Date? = nil
    var weeklyResetAt: Date? = nil
    var scannedFiles: Int = 0
    var usedFiles: Int = 0
    var lastError: String? = nil

    // weight = 0 なら cache read を全額差し引く。weight = 1 なら API 総額そのまま。
    func sessionPlanCostUSD(cacheReadWeight w: Double) -> Double {
        max(0, sessionAPICostUSD - (1 - w) * sessionCacheReadCostUSD)
    }

    func weeklyPlanCostUSD(cacheReadWeight w: Double) -> Double {
        max(0, weeklyAPICostUSD - (1 - w) * weeklyCacheReadCostUSD)
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var summary = UsageSummary()
    @Published private(set) var lastUpdated: Date = .distantPast
    @Published private(set) var isLoading: Bool = false

    private var refreshTimer: Timer?
    // summarize() など nonisolated な集計から参照するので main actor から外す。
    // 不変の TimeInterval なので分離は不要。
    nonisolated static let sessionWindow: TimeInterval = 5 * 60 * 60
    // 週次ウィンドウは最大ちょうど 7 日になる。境界で取りこぼさないよう少し広めに読む。
    private let weeklyLookback: TimeInterval = 7 * 24 * 60 * 60 + 6 * 60 * 60

    // 週次ウィンドウの起点。SettingsStore と同じ UserDefaults を見て初期化し、
    // 設定変更時は ClaudeCodeMeterApp から更新される。
    var weeklyResetAnchor: Date

    // reload 中に来た再要求を取りこぼさないためのフラグ。
    // 週次アンカーのように「集計結果を変える設定」が起動直後に入ってくるので、
    // 単純な早期 return だと変更が次のタイマーまで反映されない。
    private var reloadRequestedWhileLoading = false

    init() {
        let ud = UserDefaults.standard
        if let stored = ud.object(forKey: "weeklyResetAnchor") as? Double {
            self.weeklyResetAnchor = Date(timeIntervalSince1970: stored)
        } else {
            self.weeklyResetAnchor = Date()
        }
        Task { await reload() }
    }

    deinit {
        // @MainActor クラスから main-actor の Timer.invalidate() を呼ぶのは Swift 6 で
        // 警告だが、Timer.invalidate() はスレッドセーフなので動作上は安全。
        refreshTimer?.invalidate()
    }

    func startAutoRefresh(interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reload() }
        }
    }

    func reload() async {
        if isLoading {
            reloadRequestedWhileLoading = true
            return
        }
        isLoading = true
        defer {
            isLoading = false
            if reloadRequestedWhileLoading {
                reloadRequestedWhileLoading = false
                Task { @MainActor in await self.reload() }
            }
        }

        let now = Date()
        // ロード範囲は「最大でも 7 日」。週次ウィンドウの起点は必ずこの中に入る。
        let cutoff = now.addingTimeInterval(-weeklyLookback)
        let anchor = weeklyResetAnchor

        // ファイル走査 + 集計はバックグラウンドで。Plain struct を返すので
        // @MainActor を跨いだ受け渡しでもデータ競合は無い。
        let computed: UsageSummary = await Task.detached(priority: .utility) {
            let loaded = JSONLLoader.load(since: cutoff)
            return Self.summarize(
                entries: loaded.entries,
                now: now,
                weeklyResetAnchor: anchor,
                scannedFiles: loaded.scannedFiles,
                usedFiles: loaded.usedFiles
            )
        }.value

        self.summary = computed
        self.lastUpdated = Date()
    }

    // MARK: - 集計

    nonisolated static func summarize(
        entries: [UsageEntry],
        now: Date,
        weeklyResetAnchor: Date,
        calendar: Calendar = .current,
        scannedFiles: Int = 0,
        usedFiles: Int = 0
    ) -> UsageSummary {
        var s = UsageSummary()
        s.scannedFiles = scannedFiles
        s.usedFiles = usedFiles

        // --- 週間: 固定アンカーからの経過分だけを数える ---
        let weekStart = weeklyWindowStart(now: now, anchor: weeklyResetAnchor, calendar: calendar)
        s.weeklyStartAt = weekStart
        s.weeklyResetAt = calendar.date(byAdding: .day, value: 7, to: weekStart)
                          ?? weekStart.addingTimeInterval(7 * 24 * 60 * 60)

        for e in entries where e.timestamp >= weekStart {
            s.weeklyAPICostUSD += e.costUSD
            s.weeklyCacheReadCostUSD += e.cacheReadCostUSD
            s.weeklyMessageCount += 1
        }

        // --- セッション: 5 時間ブロックを組み立てて、いま生きているものだけを見る ---
        let blocks = sessionBlocks(entries: entries)
        if let current = blocks.last, isActive(current, at: now) {
            s.sessionAPICostUSD = current.apiCostUSD
            s.sessionCacheReadCostUSD = current.cacheReadCostUSD
            s.sessionMessageCount = current.messageCount
            s.sessionStartAt = current.start
            s.sessionResetAt = current.start.addingTimeInterval(sessionWindow)
        }
        return s
    }

    // entries は古い順にソート済 (JSONLLoader.load)。
    nonisolated static func sessionBlocks(entries: [UsageEntry]) -> [SessionBlock] {
        var blocks: [SessionBlock] = []
        for e in entries {
            if var cur = blocks.last,
               e.timestamp.timeIntervalSince(cur.start) < sessionWindow,
               e.timestamp.timeIntervalSince(cur.lastActivity) < sessionWindow {
                cur.add(e)
                blocks[blocks.count - 1] = cur
            } else {
                var b = SessionBlock(start: floorToHourUTC(e.timestamp), lastActivity: e.timestamp)
                b.add(e)
                blocks.append(b)
            }
        }
        return blocks
    }

    // ブロック開始から 5 時間以内、かつ最終活動から 5 時間以内なら「まだ生きている」。
    nonisolated static func isActive(_ block: SessionBlock, at now: Date) -> Bool {
        now.timeIntervalSince(block.start) < sessionWindow
            && now.timeIntervalSince(block.lastActivity) < sessionWindow
    }

    // ローカルのカレンダーに依存しない UTC 時間切り下げ。
    // (インド/ネパールのような 30 分・45 分オフセットでも分がズレない)
    nonisolated static func floorToHourUTC(_ d: Date) -> Date {
        let t = d.timeIntervalSince1970
        return Date(timeIntervalSince1970: (t / 3600).rounded(.down) * 3600)
    }

    // anchor から 7 日周期で回して、now 以前の直近のリセット時刻を返す。
    // anchor は過去でも未来 (次回リセット) でも同じ周期に落ちる。ウィンドウ長は (0, 7日]。
    // 日数加算は Calendar 経由なので、DST のある地域でも壁時計の時刻が保たれる。
    nonisolated static func weeklyWindowStart(
        now: Date, anchor: Date, calendar: Calendar = .current
    ) -> Date {
        func shifted(_ weeks: Int) -> Date {
            calendar.date(byAdding: .day, value: 7 * weeks, to: anchor)
                ?? anchor.addingTimeInterval(Double(weeks) * 7 * 24 * 60 * 60)
        }
        var k = Int((now.timeIntervalSince(anchor) / (7 * 24 * 60 * 60)).rounded(.down))
        var start = shifted(k)
        while start > now {
            k -= 1
            start = shifted(k)
        }
        while true {
            let next = shifted(k + 1)
            if next <= now { k += 1; start = next } else { break }
        }
        return start
    }

    // MARK: - View helpers (% は 100% でキャップせず実値を返す)

    func sessionPercent(limit: Double, cacheReadWeight: Double) -> Double {
        guard limit > 0 else { return 0 }
        return summary.sessionPlanCostUSD(cacheReadWeight: cacheReadWeight) / limit * 100
    }

    func weeklyPercent(limit: Double, cacheReadWeight: Double) -> Double {
        guard limit > 0 else { return 0 }
        return summary.weeklyPlanCostUSD(cacheReadWeight: cacheReadWeight) / limit * 100
    }
}
