import SwiftUI
import SwiftData

struct ProductListView: View {
    @Environment(Repository.self) private var repository
    @Environment(AuthStore.self) private var authStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Product.createdAt, order: .reverse) private var products: [Product]

    @State private var productToDelete: Product?
    @State private var showDeleteAlert = false

    @State private var showGuestAlert: Bool = false

    // MARK: - Filter
    @State private var filterText: String = ""

    /// 应用搜索过滤后的产品
    private var filteredProducts: [Product] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return products }
        let lower = q.lowercased()
        return products.filter { p in
            p.name.lowercased().contains(lower) ||
            p.sellingPoint.lowercased().contains(lower) ||
            (p.targetAudience?.lowercased().contains(lower) ?? false) ||
            (p.scenario?.lowercased().contains(lower) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sizeClass == .regular {
                Text("产品库")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xs)
            }

            if !products.isEmpty {
                filterBar
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.sm)
            }

            if products.isEmpty {
                emptyState
            } else if filteredProducts.isEmpty {
                filterEmptyState
            } else {
                productList
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("产品库")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                toolbarButtons
            }
            #else
            ToolbarItem(placement: .automatic) {
                toolbarButtons
            }
            #endif
        }
        .alert("删除产品", isPresented: $showDeleteAlert, presenting: productToDelete) { product in
            Button("取消", role: .cancel) { productToDelete = nil }
            Button("删除", role: .destructive) {
                HapticManager.warning()
                repository.deleteProduct(product)
                productToDelete = nil
            }
        } message: { _ in
            Text("确定要删除该产品吗？关联的本地图片也会一并清除。")
        }
        .alert("访客次数已用完", isPresented: $showGuestAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("登录后可解锁无限生成次数")
        }

    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarButtons: some View {
        NavigationLink {
            ProductFormView(product: nil)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.brand)
        }
    }

    // MARK: - Filter

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ink3)
            TextField("搜产品名称 / 卖点 / 人群 / 场景", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(Color.border, lineWidth: BorderWidth.hairline)
        )
    }

    private var filterEmptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.ink4)
            Text("没有匹配「\(filterText)」的产品")
                .font(.system(size: 14))
                .foregroundStyle(Color.ink3)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.brandSoft)
                    .frame(width: 100, height: 100)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.brand)
            }
            Text("还没有产品")
                .font(Typography.sectionTitle)
                .foregroundStyle(Color.ink)
            Text("提前录入产品信息，AI 将根据产品卖点\n精准生成小红书笔记")
                .font(.system(size: 14))
                .foregroundStyle(Color.ink3)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            NavigationLink {
                ProductFormView(product: nil)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("添加你的第一个产品")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(Color.brand, in: RoundedRectangle(cornerRadius: Radius.md))
            }
            .padding(.top, Spacing.sm)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xl)
    }

    // MARK: - Grid List

    private var productList: some View {
        let displayProducts = filteredProducts
        let columns = [
            GridItem(.adaptive(minimum: 280), spacing: Spacing.md)
        ]
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header info
                HStack {
                    Text(filterText.isEmpty ? "共 \(products.count) 个产品" : "\(filteredProducts.count) / \(products.count) 个产品")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink3)
                    Spacer()
                }
                .padding(.horizontal, Adaptive.horizontalPageMargin)
                .padding(.top, Spacing.xs)

                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(displayProducts) { product in
                        productRowContainer(product)
                    }
                }
                .padding(.horizontal, Adaptive.horizontalPageMargin)
            }
            .padding(.bottom, 80)
        }
        .background(Color.bg)
    }

    @ViewBuilder
    private func productRowContainer(_ product: Product) -> some View {
        NavigationLink {
            ProductFormView(product: product)
        } label: {
            ProductCard(product: product)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                productToDelete = product
                showDeleteAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                productToDelete = product
                showDeleteAlert = true
            } label: {
                Label("删除产品", systemImage: "trash")
            }
        }
    }

}

// MARK: - Premium Product Card

private struct ProductCard: View {
    let product: Product

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .abbreviated
        return f
    }()

    private var timeLabel: String {
        Self.timeFormatter.localizedString(for: product.createdAt, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.md) {
                thumbnail
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(product.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Spacer()
                        

                    }
                    
                    Text(product.sellingPoint)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 32, alignment: .topLeading)
                }
            }
            .padding(Spacing.md)
            
            Divider()
                .background(Color.border)
            
            // Bottom Row: Time & Tags
            HStack(spacing: Spacing.xs) {
                if let audience = product.targetAudience, !audience.isEmpty {
                    Text(audience)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.brandSoft)
                        .foregroundStyle(Color.brand)
                        .clipShape(Capsule())
                }
                if let scenario = product.scenario, !scenario.isEmpty {
                    Text(scenario)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.surfaceMuted)
                        .foregroundStyle(Color.ink2)
                        .clipShape(Capsule())
                }
                Spacer()
                
                Text(timeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink4)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 8)
            .background(Color.bg.opacity(0.3))
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.border, lineWidth: BorderWidth.hairline)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let path = product.imagePaths.first,
           let img = ProductFormView.loadThumbnail(relativePath: path) {
            img
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.brandSoft)
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.brand)
                )
        }
    }
}
