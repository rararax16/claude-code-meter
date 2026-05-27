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
        let percent = usage.sessionPercent(limit: settings.sessionLimitUSD)
        let cost = usage.summary.sessionCostUSD
        let limit = settings.sessionLimitUSD
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("現在のセッション (過去5時間)")
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
                if let reset = usage.summary.sessionResetAt {
                    Text("リセット: \(timeString(reset))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var weeklyBlock: some View {
        let percent = usage.weeklyPercent(limit: settings.weeklyLimitUSD)
        let cost = usage.summary.weeklyCostUSD
        let limit = settings.weeklyLimitUSD
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("週間 (過去7日)")
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
}
