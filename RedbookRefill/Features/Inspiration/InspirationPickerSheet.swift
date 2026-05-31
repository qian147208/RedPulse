//
//  InspirationPickerSheet.swift
//  RedPulse
//
//  从灵感板选择条目导入到生成页。
//

import SwiftUI
import SwiftData

struct InspirationPickerSheet: View {
    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    let filterType: InspirationType
    let onSelect: (String) -> Void

    @Query(sort: \InspirationItem.createdAt, order: .reverse) private var allItems: [InspirationItem]
    @State private var searchText: String = ""

    private var filteredItems: [InspirationItem] {
        allItems.filter { item in
            let typeMatch = item.type == filterType.rawValue
            let searchMatch = searchText.isEmpty
                || item.content.localizedCaseInsensitiveContains(searchText)
                || item.title.localizedCaseInsensitiveContains(searchText)
            return typeMatch && searchMatch
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if filteredItems.isEmpty {
                    emptyState
                } else {
                    itemsList
                }
            }
            .background(Color.bg)
            .navigationTitle("从灵感板导入")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.ink3)
            TextField("搜索灵感内容", text: $searchText)
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Color.border, lineWidth: BorderWidth.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .padding(.horizontal, Adaptive.horizontalPageMargin)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Items list

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(filteredItems) { item in
                    Button {
                        onSelect(item.content)
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(item.content)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.ink)
                                .lineLimit(3)
                                .lineSpacing(3)

                            HStack(spacing: 6) {
                                if let source = item.source, !source.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.left.circle")
                                            .font(.system(size: 11))
                                        Text(source)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(Color.ink4)
                                }
                                Spacer()
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.ink4)
                            }
                        }
                        .padding(Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .stroke(Color.border, lineWidth: BorderWidth.hairline)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Adaptive.horizontalPageMargin)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "lightbulb")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.ink4)
            VStack(spacing: Spacing.sm) {
                Text(searchText.isEmpty ? "还没有\(filterType.displayName)类型的灵感" : "没有匹配的灵感")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink2)
                Text(searchText.isEmpty
                    ? "在结果页收藏笔记片段，或在灵感板手动添加"
                    : "换个关键词试试")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink3)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
