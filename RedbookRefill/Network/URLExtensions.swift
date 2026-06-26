//
//  URLExtensions.swift
//  RedPulse
//
//  URL 安全解析扩展，防止 iOS 17 / macOS 14+ 严格 URL 解析器因 query 中带有花括号、引号等特殊字符导致返回 nil。
//

import Foundation

extension URL {
    /// 安全地从字符串解析 URL。如果标准解析失败，会自动尝试进行百分号编码。
    nonisolated static func safeURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        
        // 1. 尝试标准解析
        if let url = URL(string: trimmed) {
            return url
        }
        
        // 2. 尝试对查询参数等不合规字符进行 percent 编码后解析
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) {
            return url
        }
        
        return nil
    }
}
