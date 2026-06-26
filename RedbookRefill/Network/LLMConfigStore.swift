//
//  LLMConfigStore.swift
//  RedbookRefill
//
//  大模型配置中心：集中管理「默认」/「自定义」两种模式下的 base URL、API Key、Model。
//
//  设计：
//  - 内置常见厂商（Agnes / DeepSeek / Kimi / MiniMax / 千问 / 豆包 / 自定义），baseURL 程序内置。
//  - 用户只填 API Key，「获取模型」按钮调 GET {baseURL}/models 拉取可选模型列表。
//  - 默认模式：单一厂商一组配置，文本/图片/视频共用（全模态厂商）。
//  - 自定义模式：文本/图片/视频三组独立配置；图片/视频只有 Agnes 支持。
//
//  所有调用方（LLMTextGenerator、AgnesService、LLMTester 等）都通过本 Store 读配置。
//

import Foundation

// MARK: - Provider

/// 内置大模型厂商（精简到 3 个常用 + Agnes 全模态）
enum LLMProvider: String, CaseIterable, Identifiable {
    case agnes    = "Agnes"
    case deepseek = "DeepSeek"
    case doubao   = "豆包"

    var id: String { rawValue }

    /// 内置的 base URL（OpenAI 兼容 chat completions 端点）
    var defaultBaseURL: String {
        switch self {
        case .agnes:    return "https://apihub.agnes-ai.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .doubao:   return "https://ark.cn-beijing.volces.com/api/v3"
        }
    }

    /// 该厂商的默认文本 model
    var defaultTextModel: String {
        switch self {
        case .agnes:    return "agnes-2.0-flash"
        case .deepseek: return "deepseek-chat"
        // 豆包文本：model 字段填接入点 ID（ep-xxx），用户需在方舟后台创建
        case .doubao:   return "ep-（方舟接入点 ID）"
        }
    }

    var defaultImageModel: String {
        switch self {
        case .agnes:    return "agnes-image-2.1-flash"
        // 豆包 Seedream 系列：直接用 model ID（官方写法，注意是 . 不是 -）
        case .doubao:   return "doubao-seedream-4.5"
        case .deepseek: return ""
        }
    }

    var defaultVideoModel: String {
        switch self {
        case .agnes:    return "agnes-video-v2.0"
        // 豆包 Seedance 系列：直接用 model ID
        // 官方文档（创建视频生成任务 API）+ CSDN 实战代码确认：model ID 是小写 pro
        case .doubao:   return "doubao-seedance-1-5-pro-251215"
        case .deepseek: return ""
        }
    }

    /// UI 上展示的副标题
    var subtitle: String {
        switch self {
        case .agnes:    return "全模态（文本 / 图片 / 视频）"
        case .deepseek: return "纯文本（价格便宜 / 长上下文）"
        case .doubao:   return "豆包 · 文本/图片/视频用 Bearer Token 同一 Key（文本 model 填 ep-xxx 接入点）"
        }
    }

    /// 是否支持图片生成（DeepSeek 不支持）
    var supportsImage: Bool { self != .deepseek }
    /// 是否支持视频生成（DeepSeek 不支持）
    var supportsVideo: Bool { self != .deepseek }
}

// MARK: - Capability

/// 大模型能力维度
enum LLMCapability: String, CaseIterable, Identifiable {
    case text  = "文本"
    case image = "图片"
    case video = "视频"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .text:  return "text.badge.star"
        case .image: return "photo.on.rectangle"
        case .video: return "video.fill"
        }
    }
}

// MARK: - Config Mode

/// 配置模式：默认（全模态共用） / 自定义（各模态独立）
enum LLMConfigMode: String, CaseIterable, Identifiable {
    case `default` = "default"
    case custom    = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "默认（全模态）"
        case .custom:  return "自定义（分模态）"
        }
    }

    var description: String {
        switch self {
        case .default:
            return "选一个全模态厂商（推荐 Agnes），文本 / 图片 / 视频 全部使用同一组 API。"
        case .custom:
            return "三种能力分别选厂商和填 Key，可混搭（如 DeepSeek 文本 + Agnes 图片视频）。"
        }
    }
}

// MARK: - Config

/// 一组完整配置（Provider + URL + Key + Model）
struct LLMConfig: Equatable {
    var provider: LLMProvider
    var baseURL: String
    var apiKey: String
    var model: String

    var isValid: Bool { !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty }
}

// MARK: - ConfigStore

/// 大模型配置中心。内部按 capability + mode 查表。
///
/// 默认模式：`provider` + `apiKey` + `baseURL` 单一（共用），**但三种能力各选 model**（文本/图片/视频分模态选）。
/// 自定义模式：每种能力独立存一份 config（可混搭 provider）。
enum LLMConfigStore {

    private static let modeKey = "llm_config_mode"

    // ════════════════════════════════════════════════════════════════════════
    // ⚠️ 硬编码默认 API Key —— 这是产品方提供的 Agnes Key，新装用户开箱即用
    // ════════════════════════════════════════════════════════════════════════
    //
    // 行为约定：
    //  ① 只有"默认模式"下使用（custom 模式不读这个 key）
    //  ② 只有 UserDefaults 里 "api_key" 为空时才使用（用户填了就用用户的）
    //  ③ **这个 key 永远不进入 UI 渲染** —— LLMConfigView 输入框显示的是
    //     UserDefaults 里的值（默认空），用户看不到 hardcodedDefaultAPIKey
    //     本身，点眼睛也看不到（空 key 时眼睛按钮已隐藏）
    //
    // 安全注意：
    //  ⚠️ 这个 key 写死在代码里，会进 git 历史
    //  ⚠️ 如果以后要 push 公开仓库，请用 `git filter-repo` 清掉历史
    //  ⚠️ 或者后续迁移到环境变量 / Keychain（生产标准做法）
    // ════════════════════════════════════════════════════════════════════════
    private static let hardcodedDefaultAPIKey = "sk-zgjetHcRnpMnEsSpePhGD27N5yxBSf9FzStnDgz7pfbVl72s"

    // MARK: - 模式

    static var mode: LLMConfigMode {
        get {
            let raw = UserDefaults.standard.string(forKey: modeKey) ?? LLMConfigMode.default.rawValue
            return LLMConfigMode(rawValue: raw) ?? .default
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
        }
    }

    // MARK: - 取配置（按能力）

    /// 取某一能力的当前配置。
    static func config(for capability: LLMCapability) -> LLMConfig {
        switch mode {
        case .default:
            return defaultConfig(for: capability)
        case .custom:
            return customConfig(for: capability)
        }
    }

    /// 文本是否配齐（用于 GenerateView 决定真模型 vs Mock）
    static var isTextConfigured: Bool {
        config(for: .text).isValid
    }

    // MARK: - 内部

    /// 默认模式：所有能力共用同一 provider + baseURL + apiKey，
    /// **但 model 按 capability 分模态选**（独立存储在 UserDefaults，未设置时 fallback 到 provider 默认）。
    private static func defaultConfig(for capability: LLMCapability) -> LLMConfig {
        let provider = currentDefaultProvider
        let url = UserDefaults.standard.string(forKey: "api_base_url")
            ?? provider.defaultBaseURL
        // API Key：UserDefaults 优先（用户能改），未设置就用硬编码 fallback
        let storedKey = UserDefaults.standard.string(forKey: "api_key") ?? ""
        let key = storedKey.isEmpty ? hardcodedDefaultAPIKey : storedKey
        // Model：按能力独立存储（UserDefaults），未设置用 provider 的 defaultImageModel / defaultVideoModel
        let modelKey: String
        switch capability {
        case .text:  modelKey = "default_text_model"
        case .image: modelKey = "default_image_model"
        case .video: modelKey = "default_video_model"
        }
        let storedModel = UserDefaults.standard.string(forKey: modelKey) ?? ""
        let model: String = {
            if !storedModel.isEmpty { return storedModel }
            switch capability {
            case .text:  return provider.defaultTextModel
            case .image: return provider.defaultImageModel.isEmpty ? provider.defaultTextModel : provider.defaultImageModel
            case .video: return provider.defaultVideoModel.isEmpty ? provider.defaultTextModel : provider.defaultVideoModel
            }
        }()
        return LLMConfig(provider: provider, baseURL: url, apiKey: key, model: model)
    }

    /// 写默认 model（UI 改了存这里）
    static func setDefaultModel(_ model: String, for capability: LLMCapability) {
        let key: String
        switch capability {
        case .text:  key = "default_text_model"
        case .image: key = "default_image_model"
        case .video: key = "default_video_model"
        }
        UserDefaults.standard.set(model, forKey: key)
    }

    /// 读默认 model（UI 初始化用）
    static func defaultModel(for capability: LLMCapability) -> String {
        return defaultConfig(for: capability).model
    }

    /// 自定义模式：每种能力独立存。
    private static func customConfig(for capability: LLMCapability) -> LLMConfig {
        let prefix = customPrefix(for: capability)
        let providerRaw = UserDefaults.standard.string(forKey: prefix + "_provider")
        let provider = providerRaw.flatMap(LLMProvider.init(rawValue:)) ?? .agnes
        let url = UserDefaults.standard.string(forKey: prefix + "_base_url") ?? provider.defaultBaseURL
        let key = UserDefaults.standard.string(forKey: prefix + "_api_key") ?? ""
        let model = UserDefaults.standard.string(forKey: prefix + "_model")
            ?? defaultModelName(provider: provider, capability: capability)
        return LLMConfig(provider: provider, baseURL: url, apiKey: key, model: model)
    }

    private static func defaultModelName(provider: LLMProvider, capability: LLMCapability) -> String {
        switch capability {
        case .text:  return provider.defaultTextModel
        case .image: return provider.defaultImageModel
        case .video: return provider.defaultVideoModel
        }
    }

    private static func customPrefix(for capability: LLMCapability) -> String {
        switch capability {
        case .text:  return "text"
        case .image: return "image"
        case .video: return "video"
        }
    }

    // MARK: - 默认模式 provider

    /// 默认模式当前选的厂商（控制 baseURL/apiKey 来源）
    static var currentDefaultProvider: LLMProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: "llm_default_provider")
            return raw.flatMap(LLMProvider.init(rawValue:)) ?? .agnes
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "llm_default_provider")
        }
    }

    /// 默认模式 key 仍用老 key（向后兼容）
    static var defaultModeAPIKey: String {
        get { UserDefaults.standard.string(forKey: "api_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "api_key") }
    }

    static var defaultModeBaseURL: String {
        get { UserDefaults.standard.string(forKey: "api_base_url") ?? LLMProvider.agnes.defaultBaseURL }
        set { UserDefaults.standard.set(newValue, forKey: "api_base_url") }
    }

    // MARK: - 自定义模式读写

    static func setCustomConfig(_ config: LLMConfig, for capability: LLMCapability) {
        let prefix = customPrefix(for: capability)
        UserDefaults.standard.set(config.provider.rawValue, forKey: prefix + "_provider")
        UserDefaults.standard.set(config.baseURL, forKey: prefix + "_base_url")
        UserDefaults.standard.set(config.apiKey, forKey: prefix + "_api_key")
        UserDefaults.standard.set(config.model, forKey: prefix + "_model")
    }

    // MARK: - 重置

    /// 恢复默认：清空 mode + 清空所有自定义 key。
    /// 老的 `api_base_url` / `api_key` 不动（保持用户原始输入）。
    static func resetAll() {
        mode = .default
        currentDefaultProvider = .agnes
        for cap in LLMCapability.allCases {
            let prefix = customPrefix(for: cap)
            UserDefaults.standard.removeObject(forKey: prefix + "_provider")
            UserDefaults.standard.removeObject(forKey: prefix + "_base_url")
            UserDefaults.standard.removeObject(forKey: prefix + "_api_key")
            UserDefaults.standard.removeObject(forKey: prefix + "_model")
        }
    }
}
