import SwiftUI
import AppKit

// 円リング + 中央数字。リングと数字は「使用量」表示 (使うほど増える)。
// SwiftUI のリング描画を ImageRenderer で NSImage に変換し、isTemplate=false を立てて
// メニューバーにフルカラーで表示する。直接 SwiftUI View を MenuBarExtra label に
// 渡すと macOS によってテンプレート化されて stroke が消える挙動がある。
struct MenuBarLabelView: View {
    @ObservedObject var usage: UsageStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        let percent = currentPercent
        let value = Int(percent.rounded())

        if let image = makeImage(percent: percent, value: value) {
            Image(nsImage: image)
        } else {
            Text("\(value)")
        }
    }

    @MainActor
    private func makeImage(percent: Double, value: Int) -> NSImage? {
        let drawing = RingDrawing(percent: percent, color: .white, value: value)
            .frame(width: 20, height: 20)
        let renderer = ImageRenderer(content: drawing)
        renderer.scale = 3
        guard let img = renderer.nsImage else { return nil }
        img.isTemplate = false
        return img
    }

    private var currentPercent: Double {
        switch settings.displayMode {
        case .sessionPercent:
            return usage.sessionPercent(limit: settings.sessionLimitUSD)
        case .weeklyPercent:
            return usage.weeklyPercent(limit: settings.weeklyLimitUSD)
        }
    }
}

// 使用量に応じてリングが増えていく描画。
// 0% 使用 → リング空 (薄いトラックのみ)、100% 使用 → リング満タン。
struct RingDrawing: View {
    let percent: Double   // 0..100+ 使用率
    let color: Color
    let value: Int

    private var progress: Double { min(1.0, max(0, percent / 100)) }

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 1.5)
                .stroke(Color.gray.opacity(0.4), lineWidth: 2.5)

            // 進捗リング (12時起点・時計回り、使用量で増える)
            Circle()
                .inset(by: 1.5)
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(value)")
                .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white)
        }
    }
}
