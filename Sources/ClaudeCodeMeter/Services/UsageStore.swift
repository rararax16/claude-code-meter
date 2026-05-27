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

    init() {
        let ud = UserDefaults.standard
        self.plan = Plan(rawValue: ud.string(forKey: "plan") ?? "") ?? .max5x
        self.customSessionLimitUSD = ud.object(forKey: "customSessionLimitUSD") as? Double ?? 50.0
        self.customWeeklyLimitUSD = ud.object(forKey: "customWeeklyLimitUSD") as? Double ?? 300.0
        self.displayMode = DisplayMode(rawValue: ud.string(forKey: "displayMode") ?? "") ?? .sessionPercent
        self.refreshIntervalSeconds = ud.object(forKey: "refreshIntervalSeconds") as? Double ?? 60.0
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

// reload() の最後に precompute される、表示で使うサマリ。
struct UsageSummary: Equatable {
    var sessionCostUSD: Double = 0
    var weeklyCostUSD: Double = 0
    var sessionMessageCount: Int = 0
    var weeklyMessageCount: Int = 0
    var sessionResetAt: Date? = nil
    var scannedFiles: Int = 0
    var usedFiles: Int = 0
    var lastError: String? = nil
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var summary = UsageSummary()
    @Published private(set) var lastUpdated: Date = .distantPast
    @Published private(set) var isLoading: Bool = false

    private var refreshTimer: Timer?
    private let sessionWindow: TimeInterval = 5 * 60 * 60
    private let weeklyWindow: TimeInterval  = 7 * 24 * 60 * 60

    init() {
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
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        let now = Date()
        let cutoff = now.addingTimeInterval(-weeklyWindow)
        let sessionWindow = self.sessionWindow

        // ファイル走査 + 集計はバックグラウンドで。Plain struct を返すので
        // @MainActor を跨いだ受け渡しでもデータ競合は無い。
        let computed: UsageSummary = await Task.detached(priority: .utility) {
            let loaded = JSONLLoader.load(since: cutoff)
            return Self.summarize(
                entries: loaded.entries,
                now: now,
                sessionWindow: sessionWindow,
                scannedFiles: loaded.scannedFiles,
                usedFiles: loaded.usedFiles
            )
        }.value

        self.summary = computed
        self.lastUpdated = Date()
    }

    nonisolated private static func summarize(
        entries: [UsageEntry],
        now: Date,
        sessionWindow: TimeInterval,
        scannedFiles: Int,
        usedFiles: Int
    ) -> UsageSummary {
        let sessionStart = now.addingTimeInterval(-sessionWindow)
        var s = UsageSummary()
        s.scannedFiles = scannedFiles
        s.usedFiles = usedFiles

        // entries は古い順にソート済 (JSONLLoader.load)
        var firstSessionTs: Date?
        for e in entries {
            s.weeklyCostUSD += e.costUSD
            s.weeklyMessageCount += 1
            if e.timestamp >= sessionStart {
                s.sessionCostUSD += e.costUSD
                s.sessionMessageCount += 1
                if firstSessionTs == nil { firstSessionTs = e.timestamp }
            }
        }
        if let t = firstSessionTs {
            s.sessionResetAt = t.addingTimeInterval(sessionWindow)
        }
        return s
    }

    // MARK: - View helpers (% は 100% でキャップせず実値を返す)

    func sessionPercent(limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return summary.sessionCostUSD / limit * 100
    }

    func weeklyPercent(limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return summary.weeklyCostUSD / limit * 100
    }
}
