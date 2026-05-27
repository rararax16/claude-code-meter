import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var usage: UsageStore

    var body: some View {
        Form {
            Section("プラン") {
                Picker("プラン", selection: $settings.plan) {
                    ForEach(Plan.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Text("公式の正確な上限は公開されていないので、下の値はあくまで目安です。実値とズレが大きい場合は Custom を選んで自分で値を入れてください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.plan == .custom {
                Section("Custom 上限 (USD 換算)") {
                    HStack {
                        Text("5時間セッション")
                        Spacer()
                        TextField("", value: $settings.customSessionLimitUSD, format: .number)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                        Text("$")
                    }
                    HStack {
                        Text("週間")
                        Spacer()
                        TextField("", value: $settings.customWeeklyLimitUSD, format: .number)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                        Text("$")
                    }
                }
            } else {
                Section("現在の上限 (目安)") {
                    HStack {
                        Text("5時間セッション")
                        Spacer()
                        Text(String(format: "$%.2f", settings.sessionLimitUSD))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("週間")
                        Spacer()
                        Text(String(format: "$%.2f", settings.weeklyLimitUSD))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("メニューバーの表示") {
                Picker("表示", selection: $settings.displayMode) {
                    ForEach(DisplayMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Section("自動更新") {
                Picker("更新間隔", selection: $settings.refreshIntervalSeconds) {
                    Text("10秒").tag(10.0)
                    Text("30秒").tag(30.0)
                    Text("1分 (デフォルト)").tag(60.0)
                    Text("5分").tag(300.0)
                    Text("15分").tag(900.0)
                }
                .pickerStyle(.menu)

                HStack {
                    Button("いま再読み込み") {
                        Task { await usage.reload() }
                    }
                    if usage.lastUpdated > .distantPast {
                        Text("最終更新: \(timeString(usage.lastUpdated))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("データソース") {
                Text("`~/.claude/projects/**/*.jsonl` を読み取り、過去7日分の assistant 応答の `usage`・`model`・`timestamp`・メッセージID を集計します。JSON パースの都合上 1行全体が一瞬辞書に展開されますが、必要フィールドを取った後に破棄され、**永続化・ネットワーク送信は一切ありません**。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("最後のスキャン")
                    Spacer()
                    Text("\(usage.summary.scannedFiles) ファイル / \(usage.summary.usedFiles) 件採用")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("セッション内 メッセージ")
                    Spacer()
                    Text("\(usage.summary.sessionMessageCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("週間 メッセージ")
                    Spacer()
                    Text("\(usage.summary.weeklyMessageCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let err = usage.summary.lastError {
                    Text("エラー: \(err)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("**含まれないもの:** claude.ai (ブラウザ) や Claude Desktop からの使用。Anthropic はこれらを内部で独自指標で合算しているため、本アプリの $ 換算 % とは原理的に一致しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 580)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
