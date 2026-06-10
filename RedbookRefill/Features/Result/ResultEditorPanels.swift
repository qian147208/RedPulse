//
//  ResultEditorPanels.swift
//  RedPulse
//
//  Editor panel sub-components for ResultView.
//  Extracted from the original 2550-line ResultView.
//

import SwiftUI
import SwiftData

// MARK: - Editor Panel

struct ResultEditorPanel: View {
    @Binding var record: GenerationRecord
    @Binding var selectedText: String
    @Binding var showRewriteDialog: Bool
    @Binding var showEmojiPicker: Bool
    @Binding var showAddTag: Bool
    @Binding var newTagText: String
    @Binding var debugMode: Bool
    @Binding var isGenerating: Bool
    @Binding var regeneratingField: RegenField?
    @State private var clipboardSnapshot: String? = nil
    let fromHistory: Bool
    let cloneCreated: Bool
    let onEnsureClone: () -> Void
    let onCopyAll: () -> Void
    let onRegenerateAll: () -> Void
    let onRegenerateField: (RegenField) -> Void
    let onSaveToInspiration: (InspirationType, String, String) -> Void
    let onPopToast: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                toolbarRow
                    .padding(.bottom, Spacing.xs)

                titleEditor

                Divider().background(Color.border)

                bodyEditor

                Divider().background(Color.border)

                tagsEditor
                    .padding(.top, Spacing.xs)

                if debugMode {
                    debugPromptSection
                        .padding(.top, Spacing.md)
                }

                Spacer().frame(height: 80)
            }
            .padding(Adaptive.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.surface)
    }

    private func ensureCloneIfNeeded() {
        guard fromHistory, !cloneCreated else { return }
        let newRecord = GenerationRecord(
            id: UUID(),
            adType: record.adType,
            inputKeyword: record.inputKeyword,
            keywordHint: record.keywordHint,
            productId: record.productId,
            noteTitle: record.noteTitle,
            content: record.content,
            tags: record.tags,
            imageSuggestion: record.imageSuggestion,
            imagePrompt: record.imagePrompt,
            videoPrompt: record.videoPrompt,
            imageUrls: record.imageUrls,
            videoUrl: record.videoUrl,
            easterEggText: record.easterEggText,
            hotScore: record.hotScore,
            suggestion: record.suggestion,
            isEdited: false,
            createdAt: Date()
        )
        onEnsureClone()
    }

    // MARK: - Title Editor

    private var titleEditor: some View {
        TextField("输入笔记标题", text: Binding(
            get: { record.noteTitle },
            set: {
                ensureCloneIfNeeded()
                record.noteTitle = String($0.prefix(40))
                record.isEdited = true
            }
        ))
        .font(.system(size: 22, weight: .bold, design: .serif))
        .foregroundStyle(Color.ink)
        .textFieldStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Body Editor

    private static let quickEmojis = ["✨", "🔥", "💄", "💰", "🎯", "📸", "🌟", "💡", "🎁", "❤️", "😍", "👀"]

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Group {
                #if os(macOS)
                SelectableTextEditor(
                    text: Binding(
                        get: { record.content },
                        set: {
                            ensureCloneIfNeeded()
                            record.content = $0
                            record.isEdited = true
                        }
                    ),
                    selectedText: $selectedText,
                    showRewriteDialog: $showRewriteDialog,
                    selectionScreenOrigin: .constant(.zero),
                    font: .systemFont(ofSize: 16),
                    lineSpacing: 7
                )
                #else
                SelectableTextEditor(
                    text: Binding(
                        get: { record.content },
                        set: {
                            ensureCloneIfNeeded()
                            record.content = $0
                            record.isEdited = true
                        }
                    ),
                    selectedText: $selectedText,
                    showRewriteDialog: $showRewriteDialog,
                    font: .systemFont(ofSize: 16),
                    lineSpacing: 7
                )
                #endif
            }
            .frame(minHeight: 380)
            .padding(.bottom, 4)

            HStack(spacing: Spacing.md) {
                Button {
                    HapticManager.lightImpact()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showEmojiPicker.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 13, weight: .medium))
                        Text("表情")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(showEmojiPicker ? Color.brand : Color.ink3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(showEmojiPicker ? Color.brandSoft : Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                if showEmojiPicker {
                    emojiGrid
                        .transition(.opacity)
                }

                Spacer()

                Text("\(record.content.count) 字")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var emojiGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(Self.quickEmojis.prefix(6), id: \.self) { emoji in
                    Button {
                        HapticManager.lightImpact()
                        ensureCloneIfNeeded()
                        record.content += emoji
                        record.isEdited = true
                        withAnimation { showEmojiPicker = false }
                    } label: {
                        Text(emoji)
                            .font(.system(size: 20))
                            .frame(width: 40, height: 34)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tags Editor

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FlowLayout(spacing: Spacing.sm) {
                ForEach(Array(record.tags.enumerated()), id: \.offset) { index, tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                            .font(Typography.caption)
                        Button {
                            guard index < record.tags.count else { return }
                            ensureCloneIfNeeded()
                            record.tags.remove(at: index)
                            record.isEdited = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(Typography.micro.weight(.bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .pillStyle()
                }

                Button {
                    showAddTag = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(Typography.micro.weight(.bold))
                        Text("添加标签")
                            .font(Typography.caption)
                    }
                }
                .buttonStyle(.plain)
                .pillStyle(foreground: .ink3, background: .surface, borderColor: .borderStrong)
            }

            if showAddTag {
                HStack(spacing: Spacing.sm) {
                    TextField("标签内容", text: $newTagText)
                        .textFieldStyle(.plain)
                        .font(Typography.bodySmall)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 6)
                        .background(Color.surfaceMuted)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .stroke(Color.border, lineWidth: BorderWidth.hairline)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        .onSubmit(addTag)

                    Button("添加", action: addTag)
                        .buttonStyle(GhostButtonStyle(tint: .brand))

                    Button {
                        showAddTag = false
                        newTagText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.ink3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func addTag() {
        ensureCloneIfNeeded()
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showAddTag = false
            newTagText = ""
            return
        }
        guard record.tags.count < 10 else {
            onPopToast("最多 10 个标签")
            return
        }
        record.tags.append(trimmed)
        record.isEdited = true
        newTagText = ""
        showAddTag = false
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()
            Button { onCopyAll() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc").font(.system(size: 12, weight: .medium))
                    Text("复制全部").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.ink3)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            Menu {
                Button { onRegenerateAll() } label: { Label("换一批", systemImage: "arrow.triangle.2.circlepath") }
                Button { onRegenerateField(.title) } label: { Label("重写标题", systemImage: "textformat") }
                Button { onRegenerateField(.body) } label: { Label("重写正文", systemImage: "doc.text") }
                Button { onRegenerateField(.tags) } label: { Label("重写标签", systemImage: "number") }
                Divider()
                if !record.noteTitle.isEmpty {
                    Button { onSaveToInspiration(.snippet, record.noteTitle, "标题") } label: { Label("收藏标题到灵感板", systemImage: "heart") }
                }
                if !record.content.isEmpty {
                    Button { onSaveToInspiration(.snippet, record.content, "正文") } label: { Label("收藏正文到灵感板", systemImage: "heart") }
                }
                if !record.tags.isEmpty {
                    Button { onSaveToInspiration(.keyword, record.tags.map { "#\($0)" }.joined(separator: " "), "标签") } label: { Label("收藏标签到灵感板", systemImage: "heart") }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .medium))
                    Text("重写").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.ink3)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 7))
            }
            .disabled(isGenerating)
        }
    }

    // MARK: - Debug Section

    @State private var expandedDebugSection: String? = nil

    private var debugPromptSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "ladybug")
                    .font(Typography.body)
                    .foregroundStyle(Color.brand)
                Text("调试信息")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Color.ink)
            }
            .padding(Spacing.lg)

            Divider().padding(.horizontal, Spacing.lg)

            debugPromptRow(title: "文生文提示词", icon: "text.bubble", content: debugTextPrompt)
            Divider().padding(.horizontal, Spacing.lg)
            debugPromptRow(title: "文生图提示词", icon: "photo", content: record.imagePrompt.isEmpty ? "暂无" : record.imagePrompt)
            Divider().padding(.horizontal, Spacing.lg)
            debugPromptRow(title: "图生视频提示词", icon: "video", content: record.videoPrompt.isEmpty ? "暂无" : record.videoPrompt)
        }
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Color.border, lineWidth: BorderWidth.thin))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func debugPromptRow(title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                    expandedDebugSection = expandedDebugSection == title ? nil : title
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(Typography.caption).foregroundStyle(Color.ink3).frame(width: 16)
                    Text(title).font(Typography.bodySmall.weight(.medium)).foregroundStyle(Color.ink2)
                    Spacer()
                    Image(systemName: expandedDebugSection == title ? "chevron.up" : "chevron.down")
                        .font(Typography.caption.weight(.semibold)).foregroundStyle(Color.ink3)
                }
            }
            .buttonStyle(.plain)

            if expandedDebugSection == title {
                Text(content)
                    .font(Typography.mono)
                    .foregroundStyle(Color.ink2)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
    }

    private var debugTextPrompt: String {
        let keyword = record.inputKeyword
        let hint = record.keywordHint.map { "\n风格提示：\($0)" } ?? ""
        return """
        [文生文提示词]
        你是一个小红书文案专家。产品：\(keyword)
        广告类型：\(record.adType)
        关键词：\(keyword)\(hint)

        请根据以上信息生成一篇小红书笔记，包含标题、正文、标签。
        """
    }
}
