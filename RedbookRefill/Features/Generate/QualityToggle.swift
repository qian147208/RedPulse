//
//  QualityToggle.swift
//  RedPulse
//
//  "⚡ 快速 / ✨ 高质量" 切换胶囊。
//  在 GenerateView 中 inline 使用，不做 toolbar 按钮。
//

import SwiftUI

/// 快速 / 高质量模式切换按钮。
/// - 通过 `llm_high_quality_mode` 读写 UserDefaults。
/// - 配置页里没填高质量模型时按钮变灰，提示先去填。
struct QualityToggle: View {
    @AppStorage("llm_high_quality_mode") private var highQualityMode: Bool = false

    /// GenerateView 生成中禁用的外部信号。
    var isDisabled: Bool = false

    var body: some View {
        let hasQualityModel = !(UserDefaults.standard.string(forKey: "llm_content_model_quality") ?? "").isEmpty

        Button {
            guard hasQualityModel else { return }
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.75)) {
                highQualityMode.toggle()
            }
            DebugLog.shared.info(
                .llm,
                "quality mode toggled",
                details: "highQuality=\(highQualityMode)"
            )
        } label: {
            HStack(spacing: 5) {
                Image(systemName: highQualityMode ? "sparkles" : "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolEffect(.bounce.up.byLayer, value: highQualityMode)
                Text(highQualityMode ? "高质量" : "快速")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(highQualityMode ? .white : Color.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if highQualityMode {
                    Capsule()
                        .fill(Color.brand)
                        .shadow(color: Color.brand.opacity(0.25), radius: 4, y: 2)
                } else {
                    Capsule()
                        .fill(Color.surfaceMuted)
                }
            }
            .overlay(
                Capsule()
                    .stroke(highQualityMode ? Color.clear : Color.border, lineWidth: 1)
            )
            .opacity(hasQualityModel ? 1.0 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
