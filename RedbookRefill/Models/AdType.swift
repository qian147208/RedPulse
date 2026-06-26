//
//  AdType.swift
//  灵芯
//
//  Four ad types defined by the V3.2 requirements. Raw values are the
//  Chinese strings persisted in `GenerationRecord.adType`.
//

import Foundation

enum AdType: String, CaseIterable, Codable, Identifiable {
    case feedAd = "信息流广告"
    case searchAd = "搜索广告"
    case brandAd = "品牌广告"
    case salesNote = "带货笔记"

    var id: String { rawValue }

    var displayName: String { rawValue }
}
