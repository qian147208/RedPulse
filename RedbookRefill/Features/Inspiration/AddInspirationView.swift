//
//  AddInspirationView.swift
//  灵芯
//
//  手动添加灵感条目。
//

import SwiftUI

struct AddInspirationView: View {
    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    let defaultType: InspirationType?

    @State private var selectedType: InspirationType
    @State private var content: String = ""

    init(defaultType: InspirationType? = nil) {
        self.defaultType = defaultType
        _selectedType = State(initialValue: defaultType ?? .keyword)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                typePicker
                contentEditor
                Spacer()
            }
            .padding(.horizontal, Adaptive.horizontalPageMargin)
            .padding(.top, Spacing.md)
            .background(Color.bg)
            .navigationTitle("添加灵感")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Type picker

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("类型")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink2)

            HStack(spacing: Spacing.sm) {
                ForEach(InspirationType.allCases) { type in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selectedType = type }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: type.icon)
                                .font(.system(size: 12))
                            Text(type.displayName)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(selectedType == type ? .white : Color.ink2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selectedType == type ? Color.brand : Color.surfaceMuted)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedType == type ? Color.clear : Color.border, lineWidth: BorderWidth.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Content editor

    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("内容")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink2)

            TextEditor(text: $content)
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 160)
                .background(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(Color.border, lineWidth: BorderWidth.hairline)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = InspirationItem(type: selectedType, content: trimmed)
        repository.saveInspirationItem(item)
        dismiss()
    }
}
