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
            // initial:true で起動直後の保存済み interval も拾える。
            MenuBarLabelView(usage: usage, settings: settings)
                .onChange(of: settings.refreshIntervalSeconds, initial: true) { _, newInterval in
                    usage.startAutoRefresh(interval: newInterval)
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(usage)
        }
    }
}
