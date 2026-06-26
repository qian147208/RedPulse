//
//  InspirationBoardView.swift
//  RedPulse
//
//  灵感板：收藏笔记片段、关键词、风格提示，供生成时复用。
//

import SwiftUI
import SwiftData

struct InspirationBoardView: View {
    @Environment(Repository.self) private var repository
    @Query(sort: \InspirationItem.createdAt, order: .reverse) private var allItems: [InspirationItem]
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var filterType: InspirationType? = nil
    @State private var searchText: String = ""
    @State private var showAddSheet: Bool = false

    private var filteredItems: [InspirationItem] {
        allItems.filter { item in
            let typeMatch = filterType == nil || item.type == filterType?.rawValue
            let searchMatch = searchText.isEmpty
                || item.content.localizedCaseInsensitiveContains(searchText)
                || item.title.localizedCaseInsensitiveContains(searchText)
            return typeMatch && searchMatch
        }
    }

    var body: some View {
        // P1-7: InspirationBoardView 永远以 sheet 弹出（ProfileView 一处入口），
        // 顶部由 navigationTitle 渲染大/中标题，自己不再画 28pt 大标题，避免 iPad 上"双层标题"。
        VStack(spacing: 0) {
            typeFilterBar
                .padding(.horizontal, Adaptive.horizontalPageMargin)
                .padding(.top, sizeClass == .regular ? Spacing.md : Spacing.lg)
                .padding(.bottom, Spacing.sm)

            searchField
                .padding(.horizontal, Adaptive.horizontalPageMargin)
                .padding(.bottom, Spacing.md)

            if filteredItems.isEmpty {
                emptyState
            } else {
                itemsGrid
            }
        }
        .background(Color.bg)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("灵感板")
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddInspirationView(defaultType: filterType)
        }
    }

    // MARK: - Type filter bar

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                filterChip(label: "全部", isSelected: filterType == nil) {
                    withAnimation(.easeOut(duration: 0.15)) { filterType = nil }
                }
                ForEach(InspirationType.allCases) { type in
                    filterChip(
                        label: type.displayName,
                        isSelected: filterType == type
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) { filterType = type }
                    }
                }
            }
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color.ink2)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.brand : Color.surfaceMuted)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.border, lineWidth: BorderWidth.hairline)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search

    private var searchField: some View {
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
    }

    // MARK: - Grid

    private var itemsGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(filteredItems) { item in
                    InspirationCard(item: item) {
                        repository.deleteInspirationItem(item)
                    }
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
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.ink4)
            VStack(spacing: Spacing.sm) {
                Text(searchText.isEmpty ? "还没有灵感" : "没有匹配的灵感")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink2)
                Text(searchText.isEmpty
                    ? "在结果页收藏笔记片段，或手动添加关键词和风格提示"
                    : "换个关键词试试")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink3)
                    .multilineTextAlignment(.center)
            }
            if searchText.isEmpty {
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加灵感", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inspiration card

private struct InspirationCard: View {
    let item: InspirationItem
    let onDelete: () -> Void

    @State private var showDeleteAlert = false

    private var typeColor: Color {
        switch item.inspirationType {
        case .snippet: return .brand
        case .keyword: return .suggestionBlue
        case .style:   return .success
        case .none:    return .ink3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: item.inspirationType?.icon ?? "doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(typeColor)
                Text(item.inspirationType?.displayName ?? "未知")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(typeColor)
                Spacer()
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink4)
            }

            Text(item.content)
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
                .lineLimit(4)
                .lineSpacing(3)

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
        }
        .padding(Spacing.lg)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.border, lineWidth: BorderWidth.thin)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .contextMenu {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { onDelete() }
        } message: {
            Text("删除后无法恢复")
        }
    }
}
