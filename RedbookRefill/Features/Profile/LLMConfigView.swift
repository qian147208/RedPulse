import SwiftUI

/// 大模型配置
///
/// **两种模式：**
/// - **默认（全模态）**：选一个厂商 → 填 API Key（**共用**，未填时 fallback 到内置 hardcoded Agnes Key）。
///   **三种能力各选 model**（文本/图片/视频分模态选），适合 Agnes（免费全模态）。
///   其他厂商的图/视频能力 fallback 到文本。
/// - **自定义（分模态）**：文本/图片/视频 三组独立选厂商、填 Key。图片和视频只 Agnes 支持。
///
/// **厂商列表（baseURL 内置）：**
/// Agnes / DeepSeek / Kimi / MiniMax / 千问 / 豆包 / 自定义
///
/// **获取模型：** 选中厂商填好 API Key 后点「获取模型」按钮，
/// 程序调 GET {baseURL}/models 拉取该厂商的可用模型列表，选择填回配置。
struct LLMConfigView: View {
    // 不再需要 dismiss — LLMConfigView 通过 NavigationLink push 进入，
    // 返回由系统的"← 大模型配置"返回按钮自动处理（pop 当前 view）

    // MARK: - State

    @AppStorage("llm_config_mode") private var modeRaw: String = LLMConfigMode.default.rawValue
    @AppStorage("llm_default_provider") private var defaultProviderRaw: String = LLMProvider.agnes.rawValue
    @AppStorage("api_base_url") private var defaultBaseURL: String = LLMProvider.agnes.defaultBaseURL
    @AppStorage("api_key") private var defaultAPIKey: String = ""

    @AppStorage("text_provider")  private var textProviderRaw:  String = LLMProvider.agnes.rawValue
    @AppStorage("text_base_url")  private var textBaseURL:  String = LLMProvider.agnes.defaultBaseURL
    @AppStorage("text_api_key")   private var textAPIKey:   String = ""
    @AppStorage("text_model")     private var textModel:    String = LLMProvider.agnes.defaultTextModel

    @AppStorage("image_provider") private var imageProviderRaw: String = LLMProvider.agnes.rawValue
    @AppStorage("image_base_url") private var imageBaseURL: String = LLMProvider.agnes.defaultBaseURL
    @AppStorage("image_api_key")  private var imageAPIKey:  String = ""
    @AppStorage("image_model")    private var imageModel:   String = LLMProvider.agnes.defaultImageModel

    @AppStorage("video_provider") private var videoProviderRaw: String = LLMProvider.agnes.rawValue
    @AppStorage("video_base_url") private var videoBaseURL: String = LLMProvider.agnes.defaultBaseURL
    @AppStorage("video_api_key")  private var videoAPIKey:  String = ""
    @AppStorage("video_model")    private var videoModel:   String = LLMProvider.agnes.defaultVideoModel

    @State private var showKey: Bool = false
    @State private var toastText: String = ""
    @State private var showToast: Bool = false
    @State private var showResetAlert: Bool = false

    private var mode: LLMConfigMode {
        get { LLMConfigMode(rawValue: modeRaw) ?? .default }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.md) {
                    modeCard
                    if mode == .default {
                        defaultConfigCard
                    } else {
                        customConfigCard
                    }
                    docsCard

                    Button {
                        showResetAlert = true
                    } label: {
                        Text("恢复默认")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.ink2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .padding(.top, Spacing.sm)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }

            if showToast { toastView }
        }
        .navigationTitle("大模型配置")
        .alert("恢复默认配置", isPresented: $showResetAlert) {
            Button("取消", role: .cancel) {}
            Button("确认恢复", role: .destructive, action: resetAll)
        } message: {
            Text("将清空所有 API Key 和模型选择，并切换回「默认 + Agnes」。此操作不可恢复。")
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - 模式选择

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(icon: "switch.2", title: "配置模式")
            Divider().padding(.horizontal, Spacing.lg)

            ForEach(Array(LLMConfigMode.allCases.enumerated()), id: \.element.id) { idx, m in
                if idx > 0 {
                    Divider().padding(.horizontal, Spacing.lg)
                }
                modeRow(m)
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func modeRow(_ m: LLMConfigMode) -> some View {
        let selected = mode == m
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                modeRaw = m.rawValue
            }
        } label: {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Color.brand : Color.ink4)
                    .frame(width: 24)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(m.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text(m.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 默认模式：单厂商 + key + 三种能力各选 model

    private var defaultConfigCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(icon: "key.fill", title: "默认配置（API Key 共用 / 模型可分模态选）")

            // 厂商选择
            Divider().padding(.horizontal, Spacing.lg)
            providerPicker(
                selectedRaw: $defaultProviderRaw,
                baseURL: $defaultBaseURL,
                capability: .text
            )
            // 补横向 padding — providerPicker 自身不带 horizontal padding，
            // 在 defaultConfigCard 里需要外层补一次才能跟其他行对齐
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 12)

            // API Key（共用一个）
            Divider().padding(.horizontal, Spacing.lg)
            keyFieldRow(label: "API Key（共用）", text: $defaultAPIKey, showKey: $showKey, placeholder: defaultAPIKey.isEmpty ? "（使用内置 Key，不可显示）" : "sk-...")

            // 提示：未填时使用内置 hardcoded Agnes Key
            if defaultAPIKey.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.success)
                    Text("未填 → 自动使用内置 Key")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.success)
                    Text("· 内置 Key 写死在代码里,不展示在 UI 上,点眼睛也看不到")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ink3)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, 4)
            } else {
                // 用户填了自己的 key,提示"恢复默认"的方式
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.brand)
                    Text("已使用您自己的 Key。清空后会自动切回内置 Key")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ink3)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, 4)
            }

            // 文本 / 图片 / 视频 — 三个 model 分开选
            VStack(spacing: 0) {
                Divider().padding(.horizontal, Spacing.lg)
                defaultCapabilityRow(
                    capability: .text,
                    model: defaultModelBinding(for: .text)
                )
                Divider().padding(.horizontal, Spacing.lg)
                defaultCapabilityRow(
                    capability: .image,
                    model: defaultModelBinding(for: .image)
                )
                Divider().padding(.horizontal, Spacing.lg)
                defaultCapabilityRow(
                    capability: .video,
                    model: defaultModelBinding(for: .video)
                )
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    /// 默认模式下的单条「能力 + model 选择器」（共用同一个 API Key + provider）
    private func defaultCapabilityRow(
        capability: LLMCapability,
        model: Binding<String>
    ) -> some View {
        let provider = LLMProvider(rawValue: defaultProviderRaw) ?? .agnes
        let disabled = !provider.supportsImage && capability == .image
                     || !provider.supportsVideo && capability == .video
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: capability.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.brand)
                Text(capability.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
                if disabled {
                    Text("\(provider.rawValue) 不支持，自动 fallback 到文本")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ink4)
                }
            }

            if disabled {
                // 不支持的厂商直接显示 fallback 提示，不让选
                Text("(共用到文本 \(provider.defaultTextModel))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.ink3)
            } else {
                modelPickerBlock(
                    baseURL: defaultBaseURL,
                    apiKey: defaultAPIKey,
                    provider: provider,
                    capability: capability,
                    model: model
                )
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
    }

    /// 默认模式下，UserDefaults 里的 model 字段 binding
    private func defaultModelBinding(for capability: LLMCapability) -> Binding<String> {
        Binding(
            get: { LLMConfigStore.defaultModel(for: capability) },
            set: { LLMConfigStore.setDefaultModel($0, for: capability) }
        )
    }

    // MARK: - 自定义模式：3 段独立配置

    private var customConfigCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(icon: "rectangle.3.group.fill", title: "分模态配置")

            VStack(spacing: 0) {
                Divider().padding(.horizontal, Spacing.lg)
                capabilityBlock(
                    capability: .text,
                    providerRaw: $textProviderRaw,
                    baseURL: $textBaseURL,
                    apiKey: $textAPIKey,
                    model: $textModel,
                    showKey: $showKey
                )
                Divider().padding(.horizontal, Spacing.lg)
                capabilityBlock(
                    capability: .image,
                    providerRaw: $imageProviderRaw,
                    baseURL: $imageBaseURL,
                    apiKey: $imageAPIKey,
                    model: $imageModel,
                    showKey: $showKey
                )
                Divider().padding(.horizontal, Spacing.lg)
                capabilityBlock(
                    capability: .video,
                    providerRaw: $videoProviderRaw,
                    baseURL: $videoBaseURL,
                    apiKey: $videoAPIKey,
                    model: $videoModel,
                    showKey: $showKey
                )
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - 单段配置块（自定义模式）

    @ViewBuilder
    private func capabilityBlock(
        capability: LLMCapability,
        providerRaw: Binding<String>,
        baseURL: Binding<String>,
        apiKey: Binding<String>,
        model: Binding<String>,
        showKey: Binding<Bool>
    ) -> some View {
        let provider = LLMProvider(rawValue: providerRaw.wrappedValue) ?? .agnes
        let disabled = !provider.supportsImage && capability == .image
                     || !provider.supportsVideo && capability == .video

        VStack(alignment: .leading, spacing: 6) {
            // 标题行
            HStack(spacing: Spacing.sm) {
                Image(systemName: capability.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .frame(width: 22)
                Text(capability.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            .padding(.top, 4)

            // 厂商
            providerPicker(
                selectedRaw: providerRaw,
                baseURL: baseURL,
                capability: capability
            )

            // API Key
            subKeyField(label: "API Key", text: apiKey, showKey: showKey, placeholder: "sk-...")

            // Model
            modelPickerBlock(
                baseURL: baseURL.wrappedValue,
                apiKey: apiKey.wrappedValue,
                provider: provider,
                capability: capability,
                model: model
            )

            if disabled {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text("\(provider.rawValue) 不支持\(capability.rawValue)，将自动 fallback 到文本")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color.warning)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 12)
    }

    // MARK: - 厂商平铺 Chip

    /// 默认模式只显示 Agnes（当前版本唯一支持的厂商）
    /// 自定义模式按能力过滤：DeepSeek 不支持图片/视频
    private func providerPicker(
        selectedRaw: Binding<String>,
        baseURL: Binding<String>,
        capability: LLMCapability
    ) -> some View {
        let current = LLMProvider(rawValue: selectedRaw.wrappedValue) ?? .agnes
        let isDefaultMode = (mode == .default)
        // 默认模式：只显示 Agnes（默认模式 = 全模态共用一个厂商，只 Agnes 能满足）
        // 自定义模式：按能力过滤（DeepSeek 不支持 image/video 时被排除）
        // docsCard 列出全部 3 个厂商的 API Key 入口，让用户知道还有 DeepSeek/豆包可换
        let available: [LLMProvider] = isDefaultMode
            ? [.agnes]
            : LLMProvider.allCases.filter { p in
                switch capability {
                case .text:  return true
                case .image, .video: return p != .deepseek
                }
            }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("厂商")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink3)
                Spacer(minLength: 4)
            }
            // 自动换行：当前能力下支持的厂商 chip 全部可见
            // 之前用 ScrollView(.horizontal) 在窄屏只能看到 1 个 chip
            // 默认显示全部 3 个 (Agnes / DeepSeek / 豆包)，图片/视频 tab 排除 DeepSeek
            FlowLayout(spacing: 6) {
                ForEach(available) { p in
                    let isSelected = p == current
                    Button {
                        // 点击 → 自动填上该厂商的 base URL
                        selectedRaw.wrappedValue = p.rawValue
                        baseURL.wrappedValue = p.defaultBaseURL
                    } label: {
                        HStack(spacing: 4) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(p.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.ink2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? Color.brand : Color.surfaceMuted,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // 当前选中厂商的副标题（说明该厂商支持哪些能力）
            Text(current.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color.ink4)
                .padding(.top, 2)
        }
    }

    // MARK: - Model 拉取 + 选择

    @ViewBuilder
    private func modelPickerBlock(
        baseURL: String,
        apiKey: String,
        provider: LLMProvider,
        capability: LLMCapability,
        model: Binding<String>
    ) -> some View {
        ModelPickerInline(
            baseURL: baseURL,
            apiKey: apiKey,
            provider: provider,
            model: model
        )
        .padding(.top, 2)
    }

    // MARK: - 文档卡

    private var docsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.brand)
                Text("获取 API Key")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
            }
            // 三个厂商的 API Key 申请入口（按用户偏好顺序：Agnes → DeepSeek → 豆包）
            VStack(alignment: .leading, spacing: 3) {
                providerDoc("Agnes",    "platform.agnes-ai.com/settings/apiKeys")
                providerDoc("DeepSeek", "platform.deepseek.com/api_keys")
                providerDoc("豆包(方舟)", "console.volcengine.com/ark/region:ark+cn-beijing/apikey")
            }
            Text("💡 Agnes 是新加坡 AI Lab，全球 Top 10，文本/图片/视频三模态**免费无限期**。Key 跟一个产品/应用绑定，不消耗个人额度。")
                .font(.system(size: 11))
                .foregroundStyle(Color.ink4)
                .lineSpacing(2)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .background(Color.brandSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func providerDoc(_ name: String, _ url: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("• \(name):")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.ink2)
                .layoutPriority(2)  // 名字不被压缩
            Text(url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ink3)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)  // URL 优先截断
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Reusable

    private func cardHeader(icon: String, title: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.brand)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.ink)
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
    }

    private func keyFieldRow(label: String, text: Binding<String>, showKey: Binding<Bool>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ink3)
                .padding(.horizontal, Spacing.lg)
            HStack(spacing: 8) {
                Group {
                    if showKey.wrappedValue {
                        TextField(placeholder, text: text)
                    } else {
                        SecureField(placeholder, text: text)
                    }
                }
                .font(.system(size: 14, design: .monospaced))
                .textFieldStyle(.plain)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif

                // 空 key 时不显示眼睛按钮 ——
                // 硬编码 K 永远不在 UI 显示，眼睛按钮在空状态下点也没意义
                if !text.wrappedValue.isEmpty {
                    Button {
                        showKey.wrappedValue.toggle()
                    } label: {
                        Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ink3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, 14)
        }
    }

    private func subKeyField(label: String, text: Binding<String>, showKey: Binding<Bool>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.ink4)
            HStack(spacing: 6) {
                Group {
                    if showKey.wrappedValue {
                        TextField(placeholder, text: text)
                    } else {
                        SecureField(placeholder, text: text)
                    }
                }
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
                Button {
                    showKey.wrappedValue.toggle()
                } label: {
                    Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Toast

    private var toastView: some View {
        VStack {
            Spacer()
            Text(toastText)
                .font(.system(size: 14))
                .foregroundStyle(Color.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(Color.black.opacity(0.85))
                .clipShape(Capsule())
                .padding(.bottom, 100)
        }
        .transition(.opacity)
    }

    private func popToast(_ text: String) {
        toastText = text
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { showToast = false }
        }
    }

    // MARK: - Actions

    private func resetAll() {
        modeRaw = LLMConfigMode.default.rawValue
        defaultProviderRaw = LLMProvider.agnes.rawValue
        defaultBaseURL = LLMProvider.agnes.defaultBaseURL
        defaultAPIKey = ""
        UserDefaults.standard.removeObject(forKey: "default_text_model")

        textProviderRaw  = LLMProvider.agnes.rawValue
        textBaseURL  = LLMProvider.agnes.defaultBaseURL
        textAPIKey   = ""
        textModel    = LLMProvider.agnes.defaultTextModel
        imageProviderRaw = LLMProvider.agnes.rawValue
        imageBaseURL = LLMProvider.agnes.defaultBaseURL
        imageAPIKey  = ""
        imageModel   = LLMProvider.agnes.defaultImageModel
        videoProviderRaw = LLMProvider.agnes.rawValue
        videoBaseURL = LLMProvider.agnes.defaultBaseURL
        videoAPIKey  = ""
        videoModel   = LLMProvider.agnes.defaultVideoModel

        popToast("已恢复默认配置")
    }
}

// MARK: - Model Picker Inline

/// 「获取模型」按钮 + 模型下拉选择
private struct ModelPickerInline: View {
    let baseURL: String
    let apiKey: String
    let provider: LLMProvider
    @Binding var model: String

    @State private var fetchedModels: [String] = []
    @State private var fetchState: FetchState = .idle

    enum FetchState: Equatable {
        case idle
        case fetching
        case ok
        case fail(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.ink4)

            HStack(spacing: 6) {
                if fetchedModels.isEmpty {
                    TextField("模型名称", text: $model)
                        .font(.system(size: 13, design: .monospaced))
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        #endif
                        .frame(maxWidth: .infinity)
                } else {
                    Menu {
                        ForEach(fetchedModels, id: \.self) { m in
                            Button {
                                model = m
                            } label: {
                                if m == model {
                                    Label(m, systemImage: "checkmark")
                                } else {
                                    Text(m)
                                }
                            }
                        }
                    } label: {
                        // 关键：dropdown label 自身约束在 .leading 范围内，
                        // model 文字长时按 .tail 截断，不会把「获取」按钮挤出容器
                        HStack(spacing: 4) {
                            Text(model.isEmpty ? "选择模型" : model)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(model.isEmpty ? Color.ink4 : Color.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .stroke(Color.border, lineWidth: BorderWidth.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1)  // dropdown 优先占用空间，「获取」按钮可缩
                }

                Button {
                    Task { await fetch() }
                } label: {
                    Group {
                        if fetchState == .fetching {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("获取")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                    }
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.brandSoft, in: Capsule())
                    // 按钮宽度固定缩略，不被挤压
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .disabled(fetchState == .fetching || baseURL.isEmpty || apiKey.isEmpty)
            }

            // 状态提示
            switch fetchState {
            case .fail(let msg):
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.warning)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .ok:
                Text("已拉取 \(fetchedModels.count) 个模型")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ink3)
            case .idle, .fetching:
                EmptyView()
            }
        }
    }

    private func fetch() async {
        fetchState = .fetching
        let result = await LLMModelListFetcher.fetch(baseURL: baseURL, apiKey: apiKey)
        if result.models.isEmpty {
            fetchState = .fail(result.rawError ?? "无可用模型")
        } else {
            fetchedModels = result.models
            fetchState = .ok
            if model.isEmpty, let first = result.models.first {
                model = first
            }
        }
    }
}
