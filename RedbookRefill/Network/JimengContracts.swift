//
//  JimengContracts.swift
//  RedPulse
//
//  火山引擎即梦(Jimeng) API 请求/响应模型。
//  Endpoint: https://visual.volcengineapi.com
//  Action: CVProcess / CVGetResult
//  Version: 2022-08-31
//

import Foundation

// MARK: - 图片生成

struct JimengImageRequest: Encodable {
    let req_key: String
    let prompt: String
    let width: Int = 1024
    let height: Int = 1024
    let return_url: Bool = true
    let logo_info: LogoInfo = LogoInfo()

    struct LogoInfo: Encodable {
        let add_logo: Bool = false
    }
}

struct JimengImageResponse: Decodable {
    let code: Int
    let message: String
    let data: JimengImageData?

    struct JimengImageData: Decodable {
        let image_urls: [String]?
    }

    var isSuccess: Bool { code == 10000 }
}

// MARK: - 视频生成（异步：提交 → 轮询）

struct JimengVideoRequest: Encodable {
    let req_key: String
    let prompt: String
    let return_url: Bool
    /// 图生视频用：首帧图片 URL 列表。文生视频时为 nil，JSONEncoder 自动跳过该字段。
    let image_urls: [String]?

    init(req_key: String, prompt: String, image_urls: [String]? = nil, return_url: Bool = true) {
        self.req_key = req_key
        self.prompt = prompt
        self.image_urls = image_urls
        self.return_url = return_url
    }
}

struct JimengVideoSubmitResponse: Decodable {
    let code: Int
    let message: String
    let data: JimengVideoSubmitData?

    struct JimengVideoSubmitData: Decodable {
        let task_id: String
    }

    var taskId: String? { data?.task_id }
    var isSuccess: Bool { code == 10000 }
}

struct JimengTaskResultResponse: Decodable {
    let code: Int
    let message: String
    let data: JimengTaskResultData?

    struct JimengTaskResultData: Decodable {
        let status: String         // "pending" | "running" | "done" | "failed"
        let video_url: String?
        let image_urls: [String]?
    }

    var isDone: Bool { data?.status == "done" }
    var isFailed: Bool { data?.status == "failed" }
    var videoURL: String? { data?.video_url }
    var imageURLs: [String]? { data?.image_urls }
}
