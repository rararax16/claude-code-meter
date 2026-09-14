import SwiftUI

@main
struct ClaudeCodeMeterApp: App {
    @StateObject private var usage = UsageStore()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(usage: usage, settings: settings)
                .environmentObject(settings)
        } label: {
            // MenuBarExtra content の .onAppear はポップオーバーを最初に開いた時しか
            // 発火しないため、常にレンダリングされる label 側で初期化と変更検知を行う。
            // initial:true で起動直後の保存済み設定も拾える。
            MenuBarLabelView(usage: usage, settings: settings)
                .onChange(of: settings.refreshIntervalSeconds, initial: true) { _, newInterval in
                    usage.startAutoRefresh(interval: newInterval)
                }
                // 週次ウィンドウの起点は集計時に必要なので、変わったら再集計する。
                .onChange(of: settings.weeklyResetAnchor, initial: true) { _, _ in
                    syncWeeklyAnchor()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(usage)
        }
    }

    @MainActor
    private func syncWeeklyAnchor() {
        usage.weeklyResetAnchor = settings.weeklyResetAnchor
        Task { await usage.reload() }
    }
}
