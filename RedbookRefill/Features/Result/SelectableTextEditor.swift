//
//  SelectableTextEditor.swift
//  RedPulse
//
//  平台自适应文本编辑器 — 检测选中文字以触发 AI 改写对话框。
//  iOS: UIViewRepresentable + UITextView
//  Mac: NSViewRepresentable + NSTextView
//

import SwiftUI

#if canImport(UIKit)
import UIKit

// MARK: - UITextView line spacing helper

private extension UITextView {
    func setLineSpacing(_ spacing: CGFloat) {
        guard let text = self.text else { return }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing
        let attr = NSMutableAttributedString(string: text)
        let full = NSRange(location: 0, length: attr.length)
        attr.addAttribute(.paragraphStyle, value: style, range: full)
        // Preserve existing font/color
        if let font = self.font {
            attr.addAttribute(.font, value: font, range: full)
        }
        attr.addAttribute(.foregroundColor, value: self.textColor ?? .label, range: full)
        self.attributedText = attr
    }
}

// MARK: - iOS implementation

struct SelectableTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String
    @Binding var showRewriteDialog: Bool
    var font: UIFont = .systemFont(ofSize: 16)
    var lineSpacing: CGFloat = 6

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        tv.isEditable = true
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        tv.textContainer.lineFragmentPadding = 0
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        tv.typingAttributes[.paragraphStyle] = style
        
        tv.setLineSpacing(lineSpacing)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            uiView.setLineSpacing(lineSpacing)
        }
        uiView.font = font
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: SelectableTextEditor
        private var debounceWorkItem: DispatchWorkItem?

        init(_ parent: SelectableTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            debounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let range = textView.selectedRange
                if range.length > 0 {
                    let selected = (textView.text as NSString).substring(with: range)
                    let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        self.parent.selectedText = trimmed
                        self.parent.showRewriteDialog = true
                        return
                    }
                }
                self.parent.selectedText = ""
                self.parent.showRewriteDialog = false
            }
            debounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
}

#elseif canImport(AppKit)
import AppKit

// MARK: - NSTextView line spacing helper

private extension NSTextView {
    /// Returns the screen-space bounding rect of the current selection.
    /// If no selection or invalid range, returns nil.
    func selectedScreenRect() -> NSRect? {
        let r = selectedRange()
        guard r.length > 0,
              let layout = layoutManager,
              let container = textContainer else { return nil }
        let glyphRange = layout.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
        let bounding = layout.boundingRect(forGlyphRange: glyphRange, in: container)
        guard let window = self.window else { return nil }
        var windowRect = bounding
        // Convert from text view local coords to window coords, then to screen
        windowRect = convert(bounding, to: nil)
        windowRect = window.convertToScreen(windowRect)
        return windowRect
    }

    func setLineSpacing(_ spacing: CGFloat) {
        let text = self.string
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing
        let attr = NSMutableAttributedString(string: text)
        let full = NSRange(location: 0, length: attr.length)
        attr.addAttribute(.paragraphStyle, value: style, range: full)
        if let font = self.font {
            attr.addAttribute(.font, value: font, range: full)
        }
        attr.addAttribute(.foregroundColor, value: self.textColor ?? .labelColor, range: full)
        self.textStorage?.setAttributedString(attr)
    }
}

// MARK: - macOS implementation

struct SelectableTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String
    @Binding var showRewriteDialog: Bool
    /// On macOS, receives the screen-space origin of the text selection
    var selectionScreenOrigin: Binding<NSPoint>? = nil
    var font: NSFont = .systemFont(ofSize: 16)
    var lineSpacing: CGFloat = 6

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.textColor = .labelColor
        tv.backgroundColor = .clear
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.textContainer?.lineFragmentPadding = 0
        tv.minSize = .zero
        tv.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        tv.defaultParagraphStyle = style
        tv.typingAttributes[.paragraphStyle] = style
        
        tv.setLineSpacing(lineSpacing)

        scrollView.documentView = tv
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
            tv.setLineSpacing(lineSpacing)
        }
        tv.font = font
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: SelectableTextEditor
        private var debounceWorkItem: DispatchWorkItem?

        init(_ parent: SelectableTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            debounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let range = tv.selectedRange()
                if range.length > 0 {
                    let selected = (tv.string as NSString).substring(with: range)
                    let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        self.parent.selectedText = trimmed
                        self.parent.showRewriteDialog = true
                        // Capture the selection's screen position for FloatingToolbarPanel
                        if let screenRect = tv.selectedScreenRect() {
                            self.parent.selectionScreenOrigin?.wrappedValue = screenRect.origin
                        }
                        return
                    }
                }
                self.parent.selectedText = ""
                self.parent.showRewriteDialog = false
            }
            debounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
}

#endif
