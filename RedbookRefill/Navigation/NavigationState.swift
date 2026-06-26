//
//  NavigationState.swift
//  灵芯
//
//  Shared navigation state for programmatic push navigation.
//  Works around SwiftUI bugs with .navigationDestination inside
//  NavigationSplitView detail panes on macOS / Catalyst.
//

import SwiftUI
import Observation
import Foundation

@Observable
final class NavigationState {
    var generatePath = NavigationPath()
    var historyPath = NavigationPath()
    var productPath = NavigationPath()

    /// 当前正在展示的结果 record id；非空时 RootTabView 直接在 detail 区域
    /// 渲染 ResultView，绕开 NavigationStack push（Mac Catalyst NavigationSplitView
    /// detail 内的 .navigationDestination 已知不稳）。
    var resultRecordId: UUID? = nil

    /// 刚生成完直接挂上来的 record。RootTabView 优先使用它渲染 ResultView，
    /// 避免 SwiftData @Query 异步同步窗口里出现「正在加载/找不到记录」中转态。
    /// 历史页等其他入口仍只设置 resultRecordId，让 @Query fallback 走起来。
    var pendingRecord: GenerationRecord? = nil

    // MARK: - 生成状态（原 @State in GenerateView，迁移至此避免视图销毁丢状态）

    var isGenerating = false
    var generateTask: Task<Void, Never>? = nil
    var generateErrorMessage: String? = nil
    var showGenerateError = false

    func cancelGeneration() {
        DebugLog.shared.warn(.llm, "user tapped cancel on thinking overlay")
        generateTask?.cancel()
        generateTask = nil
        isGenerating = false
    }
}
