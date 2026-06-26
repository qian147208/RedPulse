//
//  Product.swift
//  灵芯
//
//  SwiftData model for a product entry in the user's local product library.
//  Fields match requirements V3.2 §4.1.
//

import Foundation
import SwiftData

@Model
final class Product {
    var id: UUID
    var name: String              // 产品名称(必填, ≤30)
    var sellingPoint: String      // 核心卖点(必填, ≤100)
    var targetAudience: String?   // 目标人群(≤50)
    var scenario: String?         // 使用场景(≤80)
    var imageStyle: String?       // 图片风格参考(≤100)
    var styleImagePaths: [String] // 生图风格参考图(存储上限 5 张)
    var imagePaths: [String]      // 产品图片本地相对路径
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sellingPoint: String,
        targetAudience: String? = nil,
        scenario: String? = nil,
        imageStyle: String? = nil,
        styleImagePaths: [String] = [],
        imagePaths: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sellingPoint = sellingPoint
        self.targetAudience = targetAudience
        self.scenario = scenario
        self.imageStyle = imageStyle
        self.styleImagePaths = styleImagePaths
        self.imagePaths = imagePaths
        self.createdAt = createdAt
    }
}

