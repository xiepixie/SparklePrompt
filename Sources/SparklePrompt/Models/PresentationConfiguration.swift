import AppKit
import SwiftUI

struct PromptPresentationStyle {
    let backgroundColor: Color
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let codeTextColor: Color
    let accentColor: Color
    let textOpacityMultiplier: Double
    let panelOpacityMultiplier: Double
    let hintOpacity: Double
    let dividerOpacity: Double
    let subtleFillOpacity: Double
    let panelBorderOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat
    let blurRadius: CGFloat
    let fontSize: CGFloat
}

/// Represents a keyboard shortcut with modifiers and a key.
struct Shortcut: Codable, Equatable {
    var key: String
    var keyCode: UInt16
    var modifiers: UInt

    var normalizedModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection([.command, .option, .shift, .control])
    }

    var displayString: String {
        let displayKey = key == " " ? "Space" : key.uppercased()
        return keySymbols.joined() + displayKey
    }

    var keySymbols: [String] {
        var symbols: [String] = []
        let flags = normalizedModifiers
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }
}

struct AIRole: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var prompt: String
}

enum AIProvider: String, Codable, CaseIterable {
    case deepseek = "DeepSeek"
    case openAICompatible1 = "OpenAI 兼容 1"
    case openAICompatible2 = "OpenAI 兼容 2"
    case anthropic = "Anthropic"
    case ollama = "Ollama 原生"
    case mstyOllama = "Msty Ollama"
    case mstyMLX = "Msty MLX"

    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .openAICompatible1, .openAICompatible2: return "https://api.openai.com"
        case .anthropic: return "https://api.anthropic.com"
        case .ollama: return "http://localhost:11434"
        case .mstyOllama: return "http://localhost:11964/v1"
        case .mstyMLX: return "http://localhost:11973/v1"
        }
    }

    var isLocal: Bool {
        switch self {
        case .ollama, .mstyOllama, .mstyMLX:
            return true
        default:
            return false
        }
    }
}

enum ProviderStatus: Equatable {
    case notConfigured
    case localReady
    case waitingForTest
    case testing
    case success(modelCount: Int)
    case configError(code: Int, message: String)
    case networkError(message: String)
    case customError(message: String)

    var displayText: String {
        switch self {
        case .notConfigured: return "未配置 API Key"
        case .localReady: return "本地服务就绪"
        case .waitingForTest: return "等待测试连接"
        case .testing: return "正在验证连接..."
        case .success(let count): return "测试成功，可使用 \(count) 个模型"
        case .configError(let code, let msg): return "配置错误 (HTTP \(code)): \(msg)"
        case .networkError(let msg): return "网络错误: \(msg)"
        case .customError(let msg): return msg
        }
    }

    var color: Color {
        switch self {
        case .localReady, .success: return .green
        case .configError, .networkError, .notConfigured: return .red
        case .waitingForTest, .testing, .customError: return .yellow
        }
    }
}

enum ShortcutAction: String, CaseIterable, Codable {
    case playPause = "播放/暂停"
    case reset = "重置"
    case toggleLibrary = "剧本库"
    case prevScript = "上一个剧本"
    case nextScript = "下一个剧本"
    case aiPrompt = "AI 面板"
    case toggleControls = "控制栏"
    case toggleAlwaysOnTop = "置顶"
    case paste = "粘贴"
    case toggleTimer = "计时器开关"
    case resetTimer = "计时器重置"
    case toggleEdit = "编辑剧本"
    case prevWorkspace = "上一个工作区"
    case nextWorkspace = "下一个工作区"
    case increaseFontSize = "增大字号"
    case decreaseFontSize = "减小字号"
    case increaseBgOpacity = "增加背景暗度"
    case decreaseBgOpacity = "减小背景暗度"
    case increaseTextOpacity = "增加文字不透明度"
    case decreaseTextOpacity = "减小文字不透明度"
    case togglePrivacy = "隐私防护"
    case toggleMirrorH = "水平镜像"
    case toggleMirrorV = "垂直镜像"
}
