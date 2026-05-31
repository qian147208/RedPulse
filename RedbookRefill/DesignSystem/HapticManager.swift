import SwiftUI

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

/// 统一的触觉反馈入口。iOS/iPad 使用 CoreHaptics 的轻量 API，Mac 无触觉硬件故为空操作。
enum HapticManager {
    /// 轻触反馈：chip 选中/取消、开关切换
    static func lightImpact() {
        #if canImport(UIKit) && !os(macOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// 中等反馈：按钮点击、tab 切换
    static func mediumImpact() {
        #if canImport(UIKit) && !os(macOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    /// 重度反馈：生成完成
    static func heavyImpact() {
        #if canImport(UIKit) && !os(macOS)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
    }

    /// 刚性反馈：选中操作
    static func rigidImpact() {
        #if canImport(UIKit) && !os(macOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }

    /// 成功通知：生成成功、保存成功
    static func success() {
        #if canImport(UIKit) && !os(macOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// 警告通知：删除确认
    static func warning() {
        #if canImport(UIKit) && !os(macOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// 错误通知：生成失败
    static func error() {
        #if canImport(UIKit) && !os(macOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}
