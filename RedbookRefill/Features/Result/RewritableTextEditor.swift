//
//  RewritableTextEditor.swift
//  RedPulse
//
//  Encapsulates: SelectableTextEditor + SelectionToolbarView.
//  When the user selects text, a floating glass toolbar appears with
//  quick AI actions (translate, explain, summarize, rewrite, etc.)
//  instead of the old modal dialog.
//
//  All existing business logic (onTransform callback) is preserved.
//

import SwiftUI

struct RewritableTextEditor: View {
    @Binding var text: String
    /// 编辑区最小高度
    var minHeight: CGFloat = 100
    /// 上下文片段（传给 LLM 当 context）—— 调用方提供。默认空。
    var contextSnippet: String = ""
    /// 来源标签，用于 dialog 顶部标题（如 "正文" / "配图建议"）
    var sourceLabel: String = "文本"
    /// 触发 LLM 改写的回调：(command, selectedText, context) async throws -> 重写后文本
    var onTransform: (String, String, String) async throws -> String
    /// 成功改写后调用方做 toast / 其它通知
    var onSuccess: (() -> Void)? = nil
    /// 失败后调用方提示
    var onFailure: ((Error) -> Void)? = nil

    @State private var selectedText: String = ""
    @State private var showRewriteDialog: Bool = false
    @State private var isProcessing: Bool = false
    @State private var viewModel = SelectionToolbarViewModel()
    #if os(macOS)
    @State private var selectionScreenOrigin: CGPoint = .zero
    #endif
    /// Tracks which field triggered selection so the old dialog path still works
    /// for callers that haven't migrated to the toolbar pattern.
    @State private var useNewToolbar: Bool = true

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Group {
                #if os(macOS)
                SelectableTextEditor(
                    text: $text,
                    selectedText: $selectedText,
                    showRewriteDialog: $showRewriteDialog,
                    selectionScreenOrigin: $selectionScreenOrigin
                )
                #else
                SelectableTextEditor(
                    text: $text,
                    selectedText: $selectedText,
                    showRewriteDialog: $showRewriteDialog
                )
                #endif
            }
            .frame(minHeight: minHeight)
            .padding(Spacing.sm)
            .background(Color.surfaceMuted)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(Color.border, lineWidth: BorderWidth.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        // New: floating glass toolbar
        // - iOS/iPad: inline overlay at the bottom of the editor
        // - macOS: system-wide floating panel that follows the mouse
        .overlay(alignment: .bottom) {
            #if os(macOS)
            if useNewToolbar {
                MacSelectionToolbarBridge(viewModel: viewModel)
            }
            #else
            if useNewToolbar {
                SelectionToolbarView(viewModel: viewModel)
                    .padding(.bottom, 8)
            }
            #endif
        }
        // Legacy: modal sheet dialog — only shown when useNewToolbar is false
        .sheet(isPresented: Binding(
            get: { showRewriteDialog && !useNewToolbar },
            set: { showRewriteDialog = $0 }
        )) {
            RewritePromptDialog(
                selectedText: selectedText,
                sourceLabel: sourceLabel,
                onConfirm: { instruction in
                    await performRewriteDirect(instruction)
                    await MainActor.run { showRewriteDialog = false }
                },
                onCancel: { showRewriteDialog = false }
            )
            .presentationDetents([.fraction(0.5), .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedText) { _, newValue in
            guard useNewToolbar else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                viewModel.show(for: trimmed)
                #if os(macOS)
                viewModel.selectionScreenOrigin = selectionScreenOrigin
                #endif
                // Prevent legacy dialog from appearing
                showRewriteDialog = false
            } else {
                viewModel.hide()
            }
        }
        .onAppear {
            setupViewModel()
        }
    }

    // MARK: - ViewModel wiring

    private func setupViewModel() {
        viewModel.onGenerate = { [self] action, text, customInstruction in
            let instruction: String
            if let custom = customInstruction, action == .custom {
                instruction = custom
            } else {
                instruction = action.llmInstruction
            }
            return try await onTransform(instruction, text, contextSnippet)
        }

        viewModel.onReplace = { [self] result in
            guard !selectedText.isEmpty else { return }
            text = text.replacingOccurrences(of: selectedText, with: result)
            selectedText = ""
            onSuccess?()
        }
    }

    // MARK: - Legacy LLM transform (for RewritePromptDialog backward compat)

    private func performRewriteDirect(_ instruction: String) async {
        let original = selectedText
        guard !original.isEmpty else { return }
        do {
            let result = try await onTransform(instruction, original, contextSnippet)
            await MainActor.run {
                text = text.replacingOccurrences(of: original, with: result)
                selectedText = ""
                showRewriteDialog = false
                onSuccess?()
            }
        } catch {
            await MainActor.run {
                showRewriteDialog = false
                onFailure?(error)
            }
        }
    }
}
