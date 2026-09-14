import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var usage: UsageStore

    // `/usage` の表示値。較正ボタンを押したときだけ設定に反映する。
    @State private var observedSessionPercent: Double?
    @State private var observedWeeklyPercent: Double?
    @State private var calibratedAt: Date?

    private var canCalibrate: Bool {
        let w = settings.cacheReadWeight
        let s = (observedSessionPercent ?? 0) > 0
            && usage.summary.sessionPlanCostUSD(cacheReadWeight: w) > 0
        let wk = (observedWeeklyPercent ?? 0) > 0
            && usage.summary.weeklyPlanCostUSD(cacheReadWeight: w) > 0
        return s || wk
    }

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

            Section("プラン消費の見積もり") {
                HStack {
                    Text("cache read の計上率")
                    Spacer()
                    Text(String(format: "%.0f%%", settings.cacheReadWeight * 100))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.cacheReadWeight, in: 0...1, step: 0.05)

                Text("既定の 100% は cache read を API 定価どおり計上します。Claude Code の `/usage` と突き合わせるとこれが実測に一番近く、Anthropic 自身も「長いセッションはキャッシュされていても高くつく」と説明しています。下げると Opus の長コンテキストで膨らむキャッシュ読み出し分を割り引けますが、実測とはズレます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("週次リセット") {
                DatePicker("リセット日時",
                           selection: $settings.weeklyResetAnchor,
                           displayedComponents: [.date, .hourAndMinute])

                Text("週間の集計はここを起点に 7 日周期で区切ります。**claude.ai の使用量画面**に出る正確なリセット日時を入れてください (`/usage` の「Resets in 2d」は丸められているので、そこから逆算すると最大 20% ずれます)。過去・未来どちらの日時でも同じ周期に落ちます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let start = usage.summary.weeklyStartAt,
                   let reset = usage.summary.weeklyResetAt {
                    HStack {
                        Text("今週の集計範囲")
                        Spacer()
                        Text("\(dateTimeString(start)) 〜 \(dateTimeString(reset))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("`/usage` で較正") {
                Text("Anthropic は上限の実数を公開しておらず、claude.ai や他デバイスの使用量もローカルには見えません。Claude Code で `/usage` を開き、表示されている % をそのまま入れると、このアプリ自身の集計額から上限を逆算します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("セッション (5hr)")
                    Spacer()
                    TextField("", value: $observedSessionPercent, format: .number)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Text("%")
                }
                HStack {
                    Text("週間 (7 day)")
                    Spacer()
                    TextField("", value: $observedWeeklyPercent, format: .number)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Text("%")
                }

                HStack {
                    Button("この値で較正") {
                        settings.calibrate(
                            sessionPercent: observedSessionPercent,
                            weeklyPercent: observedWeeklyPercent,
                            summary: usage.summary
                        )
                        calibratedAt = Date()
                    }
                    .disabled(!canCalibrate)
                    Spacer()
                    if let at = calibratedAt {
                        Text("較正: \(timeString(at)) → Custom に保存")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                let w = settings.cacheReadWeight
                HStack {
                    Text("較正に使う現在の集計額")
                    Spacer()
                    Text(String(format: "セッション $%.2f / 週間 $%.2f",
                                usage.summary.sessionPlanCostUSD(cacheReadWeight: w),
                                usage.summary.weeklyPlanCostUSD(cacheReadWeight: w)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
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
                Text("`~/.claude/projects/**/*.jsonl` を読み取り、過去7日分の assistant 応答の `usage`・`model`・`timestamp`・メッセージID を集計します。セッションは Claude Code と同じく「最初のメッセージを時間単位に切り下げた時点から5時間」を1ブロックとして扱います (直近5時間のローリングではありません)。JSON パースの都合上 1行全体が一瞬辞書に展開されますが、必要フィールドを取った後に破棄され、**永続化・ネットワーク送信は一切ありません**。")
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
                    Text("現在のブロック内 メッセージ")
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
        .frame(width: 520, height: 720)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func dateTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d(E) HH:mm"
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: date)
    }
}
