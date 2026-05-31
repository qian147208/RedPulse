//
//  SelectionToolbarViewModel.swift
//  RedPulse
//
//  UI-state-only ViewModel for the floating selection toolbar.
//  Does NOT touch any core business logic — all AI calls go through the
//  provided `onGenerate` closure which the parent view wires to the existing
//  LLMTextGenerator pipeline.
//

import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

@Observable
@MainActor
final class SelectionToolbarViewModel {

    // MARK: - State

    /// The currently selected text (from the text editor).
    var selectedText: String = ""

    /// Whether the toolbar is visible.
    var isVisible: Bool = false

    /// The recommended (highlighted) action based on intent guessing.
    var recommendedAction: QuickAction = .rewrite

    /// Currently executing action (nil when idle).
    var activeAction: QuickAction? = nil

    /// Whether an AI request is in flight.
    var isLoading: Bool = false

    /// The result text from the last action.
    var resultText: String? = nil

    /// Error message if the last action failed.
    var errorMessage: String? = nil

    /// Whether the result card is expanded (showing full text).
    var isResultExpanded: Bool = false

    /// Whether the micro-adjustment panel is visible.
    var showMicroAdjustments: Bool = false

    /// Custom instruction text (for .custom action).
    var customInstruction: String = ""

    /// Screen position of the text selection (macOS). Used by FloatingToolbarPanel
    /// to position the toolbar below the selected text rather than at the cursor.
    /// macOS: selection's screen-space origin. nil on iOS.
    #if os(macOS)
    var selectionScreenOrigin: CGPoint? = nil
    #endif

    /// History store.
    let history = QuickActionsHistory()

    // MARK: - Callbacks

    /// Called when the user taps a quick action. The parent provides an
    /// async function that takes (action, selectedText, optional customInstruction)
    /// and returns the AI-generated result string.
    var onGenerate: ((QuickAction, String, String?) async throws -> String)?

    /// Called when the user wants to replace the selected text with the result.
    var onReplace: ((String) -> Void)?

    // MARK: - Actions

    func show(for text: String) {
        selectedText = text
        recommendedAction = IntentGuesser.guess(for: text)
        resultText = nil
        errorMessage = nil
        showMicroAdjustments = false
        customInstruction = ""
        isVisible = true
    }

    func hide() {
        isVisible = false
        resultText = nil
        errorMessage = nil
        showMicroAdjustments = false
        isLoading = false
        activeAction = nil
    }

    func performAction(_ action: QuickAction) {
        guard !isLoading else { return }

        if action == .custom {
            // Show micro-adjustment panel with custom instruction field
            showMicroAdjustments = true
            return
        }

        executeAction(action, customInstruction: nil)
    }

    func executeCustomInstruction() {
        let trimmed = customInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        executeAction(.custom, customInstruction: trimmed)
    }

    func retry() {
        guard let lastAction = activeAction else { return }
        executeAction(lastAction, customInstruction: lastAction == .custom ? customInstruction : nil)
    }

    func replaceText() {
        guard let result = resultText else { return }
        onReplace?(result)
        hide()
    }

    func copyResult() {
        guard let result = resultText else { return }
        #if os(iOS)
        UIPasteboard.general.string = result
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        #endif
    }

    /// Micro-adjustment: re-run with shorter instruction.
    func makeShorter() {
        showMicroAdjustments = false
        executeAction(.shorter, customInstruction: nil)
    }

    /// Micro-adjustment: re-run with longer instruction.
    func makeLonger() {
        showMicroAdjustments = false
        executeAction(.longer, customInstruction: nil)
    }

    /// Micro-adjustment: re-run with "more casual" hint.
    func makeMoreCasual() {
        showMicroAdjustments = false
        let hint = "请改写以下文本，让语气更口语化、更随意自然："
        executeAction(.rewrite, customInstruction: hint)
    }

    /// Micro-adjustment: re-run with "more formal" hint.
    func makeMoreFormal() {
        showMicroAdjustments = false
        let hint = "请改写以下文本，让语气更正式、更专业："
        executeAction(.rewrite, customInstruction: hint)
    }

    // MARK: - Private

    private func executeAction(_ action: QuickAction, customInstruction: String?) {
        guard let generate = onGenerate else {
            errorMessage = "AI 生成服务未配置"
            return
        }

        isLoading = true
        activeAction = action
        resultText = nil
        errorMessage = nil

        Task {
            defer { self.isLoading = false }
            do {
                let result = try await generate(action, selectedText, customInstruction)
                self.resultText = result
                self.isResultExpanded = false

                // Save to history
                let record = QuickActionRecord(
                    action: action,
                    originalText: selectedText,
                    resultText: result
                )
                history.addRecord(record)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
