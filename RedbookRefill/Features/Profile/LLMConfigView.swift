import SwiftUI

struct LLMConfigView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - 内容生成（大模型 · OpenAI 兼容）

    @AppStorage("llm_content_url") private var contentURL = ""
    @AppStorage("llm_content_key") private var contentKey = ""
    /// 快速模型（默认走它），如 deepseek-chat。
    @AppStorage("llm_content_model") private var contentModel = ""
    /// 高质量模型（可选），开关启用且非空才用，如 deepseek-v4-pro。
    @AppStorage("llm_content_model_quality") private var contentModelQuality = ""

    // MARK: - 图片生成（火山引擎即梦 · AK/SK 签名）

    @AppStorage("llm_image_ak") private var imageAK = ""
    @AppStorage("llm_image_sk") private var imageSK = ""
    @AppStorage("llm_image_req_key") private var imageReqKey = ""
    @AppStorage("llm_image_ark_key") private var imageArkKey = ""

    // MARK: - 视频生成（火山引擎即梦 · AK/SK 签名）

    @AppStorage("llm_video_ak") private var videoAK = ""
    @AppStorage("llm_video_sk") private var videoSK = ""
    @AppStorage("llm_video_req_key") private var videoReqKey = ""
    @AppStorage("llm_video_ark_key") private var videoArkKey = ""

    // MARK: - Show/Hide toggles

    @State private var showContentKey = false
    @State private var showImageAK = false
    @State private var showImageSK = false
    @State private var showImageArkKey = false
    @State private var showVideoAK = false
    @State private var showVideoSK = false
    @State private var showVideoArkKey = false

    @State private var toastText = ""
    @State private var showToast = false

    // MARK: - 测试连接状态（4 个 endpoint 各一份）

    enum TestStatus: Equatable {
        case idle
        case testing
        case ok(String)
        case fail(String)
    }

    @State private var contentTestStatus: TestStatus = .idle
    @State private var imageTestStatus: TestStatus = .idle
    @State private var videoTestStatus: TestStatus = .idle

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.md) {
                    textGenCard
                    imageGenCard
                    videoGenCard

                    Button {
                        resetAll()
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - 文案生成卡片

    private var textGenCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(icon: "text.badge.sparkles", title: "文案生成")

            Divider().padding(.horizontal, Spacing.lg)

            sectionLabel("文案内容模型")
            fieldRow(label: "API URL", text: $contentURL, placeholder: "https://api.deepseek.com/v1")
            Divider().padding(.horizontal, Spacing.lg)
            keyFieldRow(label: "API Key", text: $contentKey, showKey: $showContentKey, placeholder: "sk-...")
            Divider().padding(.horizontal, Spacing.lg)
            fieldRow(label: "快速模型 ⚡", text: $contentModel, placeholder: "deepseek-v4-flash")
            modelPicker(selection: $contentModel)
            Divider().padding(.horizontal, Spacing.lg)
            fieldRow(label: "高质量模型 ✨ (可选)", text: $contentModelQuality, placeholder: "deepseek-v4-pro")
            modelPicker(selection: $contentModelQuality)
            qualityModeHint
            testConnectionRow(status: contentTestStatus) {
                await runContentTest()
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - 图片生成卡片（即梦 · AK/SK）

    private var imageGenCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(icon: "photo.on.rectangle.angled", title: "图片生成 · 即梦")

            Divider().padding(.horizontal, Spacing.lg)

            // 接口说明
            calloutRow(
                "火山引擎视觉智能平台 OpenAPI\n"
                + "Endpoint: https://visual.volcengineapi.com\n"
                + "Action: CVProcess · Version: 2022-08-31\n"
                + "认证方式: AK/SK HMAC-SHA256 签名"
            )

            akskHint

            Divider().padding(.horizontal, Spacing.lg)
            keyFieldRow(label: "Access Key", text: $imageAK, showKey: $showImageAK, placeholder: "AKLT...")
            Divider().padding(.horizontal, Spacing.lg)
            keyFieldRow(label: "Secret Key", text: $imageSK, showKey: $showImageSK, placeholder: "输入 Secret Key")
            Divider().padding(.horizontal, Spacing.lg)
            fieldRow(label: "模型标识 / Model", text: $imageReqKey, placeholder: "Ark 填方舟 model 名；AK/SK 填 req_key")

            Divider().padding(.horizontal, Spacing.lg)
            keyFieldRow(label: "Ark API Key (可选)", text: $imageArkKey, showKey: $showImageArkKey, placeholder: "用于 Ark 端点 Bearer 认证")
            arkKeyHint

            // 模型参考：填了 Ark Key 用 Ark model 名；否则用 Volc req_key。
            reqKeyHint([
                "Ark 路径（推荐，填 Ark Key 时）:",
                "  doubao-seedream-4-5-251128",
                "  doubao-seedream-3-0-t2i-250415",
                "AK/SK 路径（req_key）:",
                "  文生图4.6: jimeng_t2i_v46",
                "  文生图4.0: jimeng_t2i_v40",
                "  文生图3.1/3.0: jimeng_t2i_v31 / _v30",
                "  图生图3.0: jimeng_i2i_v30",
            ])

            testConnectionRow(status: imageTestStatus) {
                await runImageTest()
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - 视频生成卡片（即梦 · AK/SK）

    private var videoGenCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(icon: "video.badge.waveform", title: "视频生成 · 即梦")

            Divider().padding(.horizontal, Spacing.lg)

            calloutRow(
                "火山引擎视觉智能平台 OpenAPI\n"
                + "Endpoint: https://visual.volcengineapi.com\n"
                + "Action: CVProcess · Version: 2022-08-31\n"
                + "认证方式: AK/SK HMAC-SHA256 签名\n"
                + "注意: 视频生成为异步接口，需轮询任务结果"
            )

            akskHint

            Divider().padding(.horizontal, Spacing.lg)
            keyFieldRow(label: "Access Key", text: $videoAK, showKey: $showVideoAK, placeholder: "AKLT...")
            Divider().padding(.horizontal, Spacing.lg)
            keyFieldRow(label: "Secret Key", text: $videoSK, showKey: $showVideoSK, placeholder: "输入 Secret Key")
            Divider().padding(.horizontal, Spacing.lg)
            fieldRow(label: "模型标识 / Model", text: $videoReqKey, placeholder: "Ark 填方舟 model 名；AK/SK 填 req_key")

            Divider().padding(.horizontal, Spacing.lg)
            keyFieldRow(label: "Ark API Key (可选)", text: $videoArkKey, showKey: $showVideoArkKey, placeholder: "用于 Ark 端点 Bearer 认证")
            arkKeyHint

            reqKeyHint([
                "Ark 路径（推荐，填 Ark Key 时）:",
                "  doubao-seedance-1-0-pro-250528",
                "AK/SK 路径（req_key）:",
                "  视频3.0 Pro: jimeng_t2v_v30_pro",
                "  视频3.0 1080P: jimeng_t2v_v30_1080p",
                "  视频3.0 720P: jimeng_t2v_v30_720p",
                "  视频3.0: jimeng_t2v_v30",
                "  图生视频(首帧): jimeng_i2v_first_frame",
            ])

            testConnectionRow(status: videoTestStatus) {
                await runVideoTest()
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Reusable Components

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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.ink3)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func calloutRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.ink3)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 10)
    }

    /// "快速 vs 高质量" 字段说明 hint。
    private var qualityModeHint: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.ink3)
            Text("默认走 ⚡ 快速模型（~10s）。在生成页右上角切到「✨ 高质量」时改用这里的高质量模型（reasoning 类，~40s）。两个模型共用同一个 URL/Key。")
                .font(.system(size: 11))
                .foregroundStyle(Color.ink3)
                .lineSpacing(2)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .background(Color.surfaceMuted)
    }

    private var akskHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brand)
                Text("获取 AK/SK")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            Text("console.volcengine.com/iam/keymanage")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ink3)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .background(Color.brandSoft)
    }

    private var arkKeyHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brand)
                Text("获取 Ark API Key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            Text("console.volcengine.com/ark/region:ark+cn-beijing/apiKey")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ink3)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .background(Color.brandSoft)
    }

    /// 常见模型 ID 快速选择（DeepSeek 官方确认）
    private static let commonModels: [(name: String, models: [String])] = [
        ("DeepSeek ✅", [
            "deepseek-v4-flash",     // 1M 上下文 · 快速
            "deepseek-v4-pro",       // 1M 上下文 · 高质量
            "deepseek-chat",         // 旧兼容（2026/07/24 弃用）
            "deepseek-reasoner",     // 旧兼容（2026/07/24 弃用）
        ]),
    ]

    private func modelPicker(selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.commonModels, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.ink4)
                            .padding(.leading, 4)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(group.models, id: \.self) { model in
                                    Button {
                                        selection.wrappedValue = model
                                    } label: {
                                        Text(model)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(selection.wrappedValue == model ? Color.brand : Color.ink3)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(selection.wrappedValue == model ? Color.brandSoft : Color.surfaceMuted, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, 4)

            Text("💡 DeepSeek 模型来自官方文档。其他厂商模型请在输入框手动输入模型 ID。")
                .font(.system(size: 10))
                .foregroundStyle(Color.ink4)
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, 12)
        }
    }

    private func reqKeyHint(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.ink3.opacity(0.7))
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private func fieldRow(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ink3)
                .padding(.horizontal, Spacing.lg)

            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, 14)
        }
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
                .font(.system(size: 14))
                .textFieldStyle(.plain)

                Button {
                    showKey.wrappedValue.toggle()
                } label: {
                    Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, 14)
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

    // MARK: - 测试连接行（按钮 + 状态）

    private func testConnectionRow(status: TestStatus, action: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Spacing.sm) {
                Button {
                    Task { await action() }
                } label: {
                    HStack(spacing: 6) {
                        if case .testing = status {
                            ProgressView().scaleEffect(0.7)
                            Text("测试中...")
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 12, weight: .medium))
                            Text("测试连接")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.brandSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(status == .testing)

                statusBadge(status)
                Spacer(minLength: 0)
            }

            if case .ok(let msg) = status {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if case .fail(let msg) = status {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brand)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func statusBadge(_ status: TestStatus) -> some View {
        switch status {
        case .idle, .testing:
            EmptyView()
        case .ok:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("通")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.green)
        case .fail:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                Text("不通")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.brand)
        }
    }

    // MARK: - Run tests

    private func runContentTest() async {
        contentTestStatus = .testing
        let r = await LLMTester.testTextModel(url: contentURL, apiKey: contentKey, model: contentModel)
        contentTestStatus = r.ok ? .ok(r.message) : .fail(r.message)
    }

    private func runImageTest() async {
        imageTestStatus = .testing
        let r = await LLMTester.testImage(ak: imageAK, sk: imageSK, reqKey: imageReqKey, arkKey: imageArkKey)
        imageTestStatus = r.ok ? .ok(r.message) : .fail(r.message)
    }

    private func runVideoTest() async {
        videoTestStatus = .testing
        let r = await LLMTester.testVideo(ak: videoAK, sk: videoSK, reqKey: videoReqKey, arkKey: videoArkKey)
        videoTestStatus = r.ok ? .ok(r.message) : .fail(r.message)
    }

    // MARK: - Actions

    private func resetAll() {
        contentURL = ""; contentKey = ""; contentModel = ""; contentModelQuality = ""
        imageAK = ""; imageSK = ""; imageReqKey = ""; imageArkKey = ""
        videoAK = ""; videoSK = ""; videoReqKey = ""; videoArkKey = ""
        popToast("已恢复默认配置")
    }
}
