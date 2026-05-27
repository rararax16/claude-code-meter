import Foundation

// Anthropic は Pro/Max/Team の正確な上限を「API換算 USD」で公表していない。
// 下の値はコミュニティ報告ベースの「目安」。Custom を選んだ場合は自分の値で上書きする。
enum Plan: String, CaseIterable, Codable, Identifiable {
    case pro = "Pro"
    case max5x = "Max 5x"
    case max20x = "Max 20x"
    case team = "Claude Team"
    case custom = "Custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pro: return "Pro"
        case .max5x: return "Max 5x"
        case .max20x: return "Max 20x"
        case .team: return "Claude Team"
        case .custom: return "Custom"
        }
    }

    // .custom は SettingsStore.customSessionLimitUSD を使うのでここでは nil。
    // この値は plan != .custom のときだけ参照される。
    var defaultSessionLimitUSD: Double? {
        switch self {
        case .pro:    return 5.0
        case .max5x:  return 30.0
        case .max20x: return 150.0
        case .team:   return 190.0
        case .custom: return nil
        }
    }

    var defaultWeeklyLimitUSD: Double? {
        switch self {
        case .pro:    return 30.0
        case .max5x:  return 200.0
        case .max20x: return 1000.0
        case .team:   return 3400.0
        case .custom: return nil
        }
    }
}
