//
//  DebugLogView.swift
//  灵芯
//
//  调试日志查看页（开发者模式入口）。
//  - 搜索过滤
//  - 级别 / 分类筛选
//  - 自动滚动到最新（除非用户手动滚动了）
//  - 复制全部 / 清空
//

import SwiftUI

struct DebugLogView: View {
    @State private var query: String = ""
    @State private var selectedLevel: DebugLogLevel? = nil
    @State private var selectedCategory: DebugLogCategory? = nil
    @State private var showCopiedToast = false

    private var log: DebugLog { DebugLog.shared }

    private var filtered: [DebugLogEntry] {
        log.entries.filter { entry in
            if let lv = selectedLevel, entry.level != lv { return false }
            if let cat = selectedCategory, entry.category != cat { return false }
            if !query.isEmpty {
                let q = query.lowercased()
                let hit = entry.message.lowercased().contains(q)
                    || (entry.details?.lowercased().contains(q) ?? false)
                if !hit { return false }
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            listView
        }
        .navigationTitle("调试日志")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyAll()
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        log.clear()
                    } label: {
                        Label("清空日志", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                Text("已复制到剪贴板")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // 搜索框
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink3)
                TextField("搜索 message / details", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ink3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 8))

            // 级别 chips + 分类 chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: "全部级别", selected: selectedLevel == nil, color: Color.ink2) {
                        selectedLevel = nil
                    }
                    ForEach(DebugLogLevel.allCases, id: \.self) { lv in
                        chip(label: lv.label, selected: selectedLevel == lv, color: color(for: lv)) {
                            selectedLevel = (selectedLevel == lv) ? nil : lv
                        }
                    }
                    Divider().frame(height: 16).padding(.horizontal, 2)
                    chip(label: "全部分类", selected: selectedCategory == nil, color: Color.ink2) {
                        selectedCategory = nil
                    }
                    ForEach(DebugLogCategory.allCases, id: \.self) { cat in
                        chip(label: cat.label, selected: selectedCategory == cat, color: Color.brand) {
                            selectedCategory = (selectedCategory == cat) ? nil : cat
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.surface)
    }

    private func chip(label: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? .white : color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selected ? color : color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    @ViewBuilder
    private var listView: some View {
        if filtered.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.ink3)
                Text(log.entries.isEmpty ? "暂无日志" : "无匹配的日志")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink3)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bg)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { entry in
                        entryRow(entry)
                        Divider()
                    }
                }
            }
            .background(Color.bg)
        }
    }

    private func entryRow(_ entry: DebugLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.formattedTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.ink3)
                Text(entry.level.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(color(for: entry.level), in: Capsule())
                Text(entry.category.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.brandSoft, in: Capsule())
                Spacer()
            }
            Text(entry.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let details = entry.details, !details.isEmpty {
                Text(details)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.surface)
    }

    private func color(for level: DebugLogLevel) -> Color {
        switch level {
        case .debug: return Color.ink3
        case .info:  return Color.ink2
        case .warn:  return .orange
        case .error: return Color.brand
        }
    }

    // MARK: - Actions

    private func copyAll() {
        let text = log.exportText()
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation { showCopiedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showCopiedToast = false }
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
