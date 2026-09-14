import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var usage: UsageStore
    @ObservedObject var settings: SettingsStore

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            sessionBlock
            Divider()
            weeklyBlock
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("Claude Code 使用量")
                .font(.headline)
            Spacer()
            if usage.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await usage.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("再読み込み")
            }
        }
    }

    private var sessionBlock: some View {
        let w = settings.cacheReadWeight
        let percent = usage.sessionPercent(limit: settings.sessionLimitUSD, cacheReadWeight: w)
        let cost = usage.summary.sessionPlanCostUSD(cacheReadWeight: w)
        let limit = settings.sessionLimitUSD
        let active = usage.summary.sessionStartAt != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("現在のセッション")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(active ? String(format: "%.0f%%", percent) : "—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(active ? percentColor(percent) : .secondary)
            }
            ProgressView(value: min(percent / 100, 1.0))
                .tint(percentColor(percent))
            HStack {
                Text(String(format: "$%.2f / $%.2f", cost, limit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let start = usage.summary.sessionStartAt,
                   let reset = usage.summary.sessionResetAt {
                    Text("\(timeString(start))〜\(timeString(reset))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("アクティブなブロックなし")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if settings.cacheReadWeight < 1 {
                Text(String(format: "API 換算では $%.2f (cache read $%.2f を %.0f%% で計上)",
                            usage.summary.sessionAPICostUSD,
                            usage.summary.sessionCacheReadCostUSD,
                            settings.cacheReadWeight * 100))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var weeklyBlock: some View {
        let w = settings.cacheReadWeight
        let percent = usage.weeklyPercent(limit: settings.weeklyLimitUSD, cacheReadWeight: w)
        let cost = usage.summary.weeklyPlanCostUSD(cacheReadWeight: w)
        let limit = settings.weeklyLimitUSD
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("週間")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.0f%%", percent))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(percentColor(percent))
            }
            ProgressView(value: min(percent / 100, 1.0))
                .tint(percentColor(percent))
            HStack {
                Text(String(format: "$%.2f / $%.2f", cost, limit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("プラン: \(settings.plan.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let reset = usage.summary.weeklyResetAt {
                Text("リセット: \(dateTimeString(reset))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("更新: \(timeString(usage.lastUpdated))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("設定…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(.borderless)

            Button("終了") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
    }

    private func percentColor(_ p: Double) -> Color {
        switch p {
        case 0..<50:   return .green
        case 50..<80:  return .yellow
        case 80..<100: return .orange
        default:       return .red
        }
    }

    private func timeString(_ date: Date) -> String {
        guard date > .distantPast else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func dateTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d(E) HH:mm"
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: date)
    }
}
