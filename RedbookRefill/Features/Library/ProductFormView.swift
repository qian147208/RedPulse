import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct ProductFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let editingProduct: Product?

    // 表单状态
    @State private var name: String
    @State private var sellingPoint: String
    @State private var targetAudience: String
    @State private var scenario: String
    @State private var imageStyle: String
    @State private var styleImagePaths: [String]

    // UI 状态
    @State private var showDeleteAlert = false
    @State private var toastMessage: String?
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var showSourceDialog = false
    @State private var showPhotoLibrary = false
    #if os(iOS) && !targetEnvironment(macCatalyst)
    @State private var showCamera = false
    #endif
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    @State private var showFileImporter = false
    #endif

    private static let presetStyles: [String] = [
        "极简白背景", "自然光场景", "复古胶片", "韩系清新",
        "高级灰", "日系杂志", "暗调氛围", "ins风"
    ]

    private static let maxImages = 5

    init(product: Product?) {
        self.editingProduct = product
        _name = State(initialValue: product?.name ?? "")
        _sellingPoint = State(initialValue: product?.sellingPoint ?? "")
        _targetAudience = State(initialValue: product?.targetAudience ?? "")
        _scenario = State(initialValue: product?.scenario ?? "")
        _imageStyle = State(initialValue: product?.imageStyle ?? "")
        _styleImagePaths = State(initialValue: product?.styleImagePaths ?? [])
    }

    private var isEditing: Bool { editingProduct != nil }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    basicFieldsCard
                    styleCard
                }
                .padding(.horizontal, Adaptive.horizontalPageMargin)
                .padding(.vertical, Spacing.lg)
            }

            // 浮动操作栏 — 底部留66pt避开Tab栏
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    bottomActions
                        .frame(maxWidth: 760)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Adaptive.horizontalPageMargin)
                .padding(.vertical, Spacing.md)
                #if os(iOS)
                .padding(.bottom, 66)
                #endif
                .background(Color.surface)
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle(isEditing ? "编辑产品" : "添加产品")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                toastView(msg)
                    .padding(.bottom, 80)
            }
        }
        .alert("删除产品", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let p = editingProduct {
                    modelContext.delete(p)
                    try? modelContext.save()
                    dismiss()
                }
            }
        } message: {
            Text("确定要删除该产品吗？关联的本地图片也会一并清除。")
        }
    }

    // MARK: - Basic Fields Card

    private var basicFieldsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // 产品名称
            FieldHeader(title: "产品名称", required: true, count: name.count, max: 30)
            TextField("如：红书极光精华", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
                .padding(Spacing.md)
                .background(Color.bg, in: RoundedRectangle(cornerRadius: Radius.sm))
                .onChange(of: name) { _, newValue in
                    if newValue.count > 30 { name = String(newValue.prefix(30)) }
                }

            // 核心卖点
            FieldHeader(title: "核心卖点", required: true, count: sellingPoint.count, max: 100)
            multilineEditor(text: $sellingPoint, placeholder: "抗糖抗氧，提亮肤色...", minHeight: 80, limit: 100)

            // 目标人群
            FieldHeader(title: "目标人群", required: false, count: targetAudience.count, max: 50)
            TextField("如：油皮、干皮、敏感肌、学生党、职场白领、宝妈、成分党、熬夜党、精致懒人……由你自己描述",
                      text: $targetAudience, axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
                .padding(Spacing.md)
                .background(Color.bg, in: RoundedRectangle(cornerRadius: Radius.sm))
                .onChange(of: targetAudience) { _, newValue in
                    if newValue.count > 50 { targetAudience = String(newValue.prefix(50)) }
                }

            // 使用场景
            FieldHeader(title: "使用场景", required: false, count: scenario.count, max: 80)
            multilineEditor(text: $scenario, placeholder: "如：夏天通勤、约会前护肤...", minHeight: 70, limit: 80)
        }
        .padding(Spacing.lg)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Style Card

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("图片风格参考")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ink)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 4), spacing: Spacing.sm) {
                ForEach(Self.presetStyles, id: \.self) { style in
                    let selected = (imageStyle == style)
                    Button {
                        if selected {
                            imageStyle = ""
                        } else {
                            imageStyle = style
                        }
                    } label: {
                        Text(style)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.brand : Color.ink2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm)
                                    .fill(selected ? Color.brandSoft : Color.bg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm)
                                    .stroke(selected ? Color.brand : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("或输入自定义风格描述...", text: $imageStyle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Color.ink)
                .padding(Spacing.md)
                .background(Color.bg, in: RoundedRectangle(cornerRadius: Radius.sm))
                .onChange(of: imageStyle) { _, newValue in
                    if newValue.count > 100 { imageStyle = String(newValue.prefix(100)) }
                }

            Divider().padding(.vertical, 4)

            HStack {
                Text("生图风格参考")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("选填，最多 5 张")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink3)
                Spacer()
                Text("\(styleImagePaths.count) / \(Self.maxImages)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink3)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(styleImagePaths.enumerated()), id: \.offset) { idx, _ in
                        styleImageThumb(index: idx)
                    }
                    if styleImagePaths.count < Self.maxImages {
                        addImageButton
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .padding(Spacing.lg)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private func styleImageThumb(index: Int) -> some View {
        let path = index < styleImagePaths.count ? styleImagePaths[index] : ""
        return ZStack(alignment: .topTrailing) {
            Group {
                if let img = Self.loadThumbnail(relativePath: path) {
                    img
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.brandSoft)
                        .overlay(
                            Image(systemName: "photo.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.brand)
                        )
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            Button {
                guard index < styleImagePaths.count else { return }
                // 删除本地文件 + 数组中移除
                Self.deleteSandboxFile(relativePath: styleImagePaths[index])
                styleImagePaths.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ink)
                    .background(Circle().fill(Color.white))
            }
            .offset(x: 6, y: -6)
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
        .padding(.trailing, 6)
    }

    private var addImagePlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Color.brandSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(Color.brand.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
            if isLoadingPhotos {
                Text("加载中...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.brand)
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.brand)
            }
        }
        .frame(width: 80, height: 80)
        // 让点击落到整个 ZStack 区域（包含描边周围的留白），不只命中相机图标本身
        .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    /// Cross-platform image source button.
    /// - iOS / iPadOS: confirmation dialog (拍照 / 从图库选择)
    /// - macOS: confirmation dialog (从图库选择 / 从文件夹选择)
    /// - Mac Catalyst: PhotosPicker directly
    private var addImageButton: some View {
        let remaining = max(1, Self.maxImages - styleImagePaths.count)

        #if os(iOS) && !targetEnvironment(macCatalyst)
        return Button {
            showSourceDialog = true
        } label: {
            addImagePlaceholder
        }
        .buttonStyle(.plain)
        .confirmationDialog("添加图片", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("拍照") { showCamera = true }
            Button("从图库选择") { showPhotoLibrary = true }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotoLibrary,
            selection: $photoPickerItems,
            maxSelectionCount: remaining,
            matching: .images,
            photoLibrary: .shared()
        )
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onCapture: { data in
                    showCamera = false
                    if let path = Self.saveImageToSandbox(data: data) {
                        styleImagePaths.append(path)
                    }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: photoPickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            handlePickedPhotos(newItems)
        }
        #elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
        // macOS: 图库 / 文件夹
        let button = Button {
            showSourceDialog = true
        } label: {
            addImagePlaceholder
        }
        .buttonStyle(.plain)
        .confirmationDialog("添加图片", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("从图库选择") { showPhotoLibrary = true }
            Button("从文件夹选择") { showFileImporter = true }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotoLibrary,
            selection: $photoPickerItems,
            maxSelectionCount: remaining,
            matching: .images,
            photoLibrary: .shared()
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            handleImportedFiles(result)
        }
        .onChange(of: photoPickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            handlePickedPhotos(newItems)
        }
        return button
        #else
        // Mac Catalyst: PhotosPicker 直接打开图库
        return PhotosPicker(
            selection: $photoPickerItems,
            maxSelectionCount: remaining,
            matching: .images,
            photoLibrary: .shared()
        ) {
            addImagePlaceholder
        }
        .buttonStyle(.plain)
        .onChange(of: photoPickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            handlePickedPhotos(newItems)
        }
        #endif
    }

    // MARK: - Photo picker plumbing

    private func handlePickedPhotos(_ items: [PhotosPickerItem]) {
        isLoadingPhotos = true
        Task {
            var savedPaths: [String] = []
            for item in items {
                if styleImagePaths.count + savedPaths.count >= Self.maxImages { break }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let path = Self.saveImageToSandbox(data: data) {
                    savedPaths.append(path)
                }
            }
            await MainActor.run {
                styleImagePaths.append(contentsOf: savedPaths)
                photoPickerItems = []
                isLoadingPhotos = false
                if savedPaths.isEmpty && !items.isEmpty {
                    showToast("图片加载失败，请重试")
                }
            }
        }
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    private func handleImportedFiles(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            isLoadingPhotos = true
            var savedPaths: [String] = []
            for url in urls {
                guard styleImagePaths.count + savedPaths.count < Self.maxImages else { break }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url),
                   let path = Self.saveImageToSandbox(data: data) {
                    savedPaths.append(path)
                }
            }
            styleImagePaths.append(contentsOf: savedPaths)
            isLoadingPhotos = false
            if savedPaths.isEmpty {
                showToast("图片加载失败，请重试")
            }
        case .failure(let error):
            showToast("文件选择失败: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Sandbox image helpers (static, no self capture)

    private static func sandboxImageDir() -> URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("ProductImages", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func saveImageToSandbox(data: Data) -> String? {
        guard let dir = sandboxImageDir() else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return "ProductImages/\(filename)"
        } catch {
            return nil
        }
    }

    static func deleteSandboxFile(relativePath: String) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent(relativePath)
        try? fm.removeItem(at: url)
    }

    static func loadThumbnail(relativePath: String) -> Image? {
        guard !relativePath.isEmpty else { return nil }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = docs.appendingPathComponent(relativePath)
        guard fm.fileExists(atPath: url.path) else { return nil }
        #if canImport(UIKit)
        guard let ui = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: ui)
        #elseif canImport(AppKit)
        guard let ns = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: ns)
        #else
        return nil
        #endif
    }

    // MARK: - Bottom Actions

    @ViewBuilder
    private var bottomActions: some View {
        if isEditing {
            HStack(spacing: Spacing.md) {
                Button {
                    showDeleteAlert = true
                } label: {
                    Text("删除")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                }
                .buttonStyle(.plain)

                Button(action: save) {
                    Text("保存修改")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.brand, in: RoundedRectangle(cornerRadius: Radius.md))
                }
                .buttonStyle(.plain)
            }
        } else {
            Button(action: save) {
                Text("保存")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(Color.brand, in: RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Multiline editor

    private func multilineEditor(text: Binding<String>, placeholder: String, minHeight: CGFloat, limit: Int) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink3)
                    .padding(.horizontal, Spacing.md + 4)
                    .padding(.vertical, Spacing.md + 4)
            }
            TextEditor(text: text)
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
                .scrollContentBackground(.hidden)
                .padding(Spacing.sm)
                .frame(minHeight: minHeight)
                .onChange(of: text.wrappedValue) { _, newValue in
                    if newValue.count > limit { text.wrappedValue = String(newValue.prefix(limit)) }
                }
        }
        .background(Color.bg, in: RoundedRectangle(cornerRadius: Radius.sm))
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSP = sellingPoint.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            showToast("请填写产品名称")
            return
        }
        if trimmedSP.isEmpty {
            showToast("请填写核心卖点")
            return
        }

        let target = targetAudience.trimmingCharacters(in: .whitespacesAndNewlines)
        let scn = scenario.trimmingCharacters(in: .whitespacesAndNewlines)
        let style = imageStyle.trimmingCharacters(in: .whitespacesAndNewlines)

        // 产品首图：用"生图风格参考"的第一张作为产品库 / 生成页快速带入的缩略图。
        let coverPaths: [String] = styleImagePaths.isEmpty ? [] : [styleImagePaths[0]]

        if let existing = editingProduct {
            existing.name = trimmedName
            existing.sellingPoint = trimmedSP
            existing.targetAudience = target.isEmpty ? nil : target
            existing.scenario = scn.isEmpty ? nil : scn
            existing.imageStyle = style.isEmpty ? nil : style
            existing.styleImagePaths = styleImagePaths
            existing.imagePaths = coverPaths
            do {
                try modelContext.save()
            } catch {
                showToast("保存失败: \(error.localizedDescription)")
                return
            }
        } else {
            let newProduct = Product(
                id: UUID(),
                name: trimmedName,
                sellingPoint: trimmedSP,
                targetAudience: target.isEmpty ? nil : target,
                scenario: scn.isEmpty ? nil : scn,
                imageStyle: style.isEmpty ? nil : style,
                styleImagePaths: styleImagePaths,
                imagePaths: coverPaths,
                createdAt: Date()
            )
            modelContext.insert(newProduct)
            do {
                try modelContext.save()
            } catch {
                showToast("保存失败: \(error.localizedDescription)")
                return
            }
        }

        dismiss()
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                if toastMessage == message { toastMessage = nil }
            }
        }
    }

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: Radius.md))
            .transition(.opacity)
    }
}

// MARK: - Field Header

private struct FieldHeader: View {
    let title: String
    let required: Bool
    let count: Int
    let max: Int

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                if required {
                    Text("*")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.brand)
                }
            }
            Spacer()
            Text("\(count) / \(max)")
                .font(.system(size: 12))
                .foregroundStyle(count >= max ? Color.brand : Color.ink3)
        }
    }
}
