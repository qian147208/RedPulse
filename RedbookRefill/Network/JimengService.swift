//
//  JimengService.swift
//  RedPulse
//
//  即梦图片/视频生成服务。
//  优先使用 Ark API Key (Bearer 认证)，回退到 AK/SK HMAC-SHA256 签名。
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class JimengService {

    // MARK: - Configuration (from @AppStorage equivalents)

    private var imageAK: String {
        UserDefaults.standard.string(forKey: "llm_image_ak") ?? ""
    }
    private var imageSK: String {
        UserDefaults.standard.string(forKey: "llm_image_sk") ?? ""
    }
    private var imageReqKey: String {
        UserDefaults.standard.string(forKey: "llm_image_req_key") ?? ""
    }
    private var imageArkKey: String {
        UserDefaults.standard.string(forKey: "llm_image_ark_key") ?? ""
    }

    private var videoAK: String {
        UserDefaults.standard.string(forKey: "llm_video_ak") ?? ""
    }
    private var videoSK: String {
        UserDefaults.standard.string(forKey: "llm_video_sk") ?? ""
    }
    private var videoReqKey: String {
        UserDefaults.standard.string(forKey: "llm_video_req_key") ?? ""
    }
    private var videoArkKey: String {
        UserDefaults.standard.string(forKey: "llm_video_ark_key") ?? ""
    }

    // MARK: - State

    var isGeneratingImage = false
    var isGeneratingVideo = false
    var generatedImageURLs: [String] = []
    var generatedVideoURL: String?
    var imageError: String?
    var videoError: String?

    var isConfigValidForImage: Bool {
        (!imageAK.isEmpty && !imageSK.isEmpty && !imageReqKey.isEmpty)
        || !imageArkKey.isEmpty
    }

    var isConfigValidForVideo: Bool {
        (!videoAK.isEmpty && !videoSK.isEmpty && !videoReqKey.isEmpty)
        || !videoArkKey.isEmpty
    }

    /// Returns a human-readable list of missing config fields.
    /// Empty array means fully configured.
    func validateConfig() -> (imageIssues: [String], videoIssues: [String]) {
        var imageIssues: [String] = []
        if imageArkKey.isEmpty {
            if imageAK.isEmpty { imageIssues.append("图片生成缺少 Access Key") }
            if imageSK.isEmpty { imageIssues.append("图片生成缺少 Secret Key") }
            if imageReqKey.isEmpty { imageIssues.append("图片生成缺少模型标识 / req_key") }
        }
        if imageIssues.isEmpty {
            imageIssues.append("Ark API Key 未配置（可选，填了可走更简洁的认证路径）")
        }

        var videoIssues: [String] = []
        if videoArkKey.isEmpty {
            if videoAK.isEmpty { videoIssues.append("视频生成缺少 Access Key") }
            if videoSK.isEmpty { videoIssues.append("视频生成缺少 Secret Key") }
            if videoReqKey.isEmpty { videoIssues.append("视频生成缺少模型标识 / req_key") }
        }
        if videoIssues.isEmpty {
            videoIssues.append("Ark API Key 未配置（可选，填了可走更简洁的认证路径）")
        }

        return (imageIssues, videoIssues)
    }

    // MARK: - Image Generation

    func generateImage(prompt: String) async {
        isGeneratingImage = true
        imageError = nil
        generatedImageURLs = []

        guard isConfigValidForImage else {
            DebugLog.shared.error(.jimeng, "image config missing")
            imageError = "请先在「我的 → 大模型配置 → 图片生成」中填写 Ark Key 或 AK/SK + req_key"
            isGeneratingImage = false
            return
        }

        let usingArk = !imageArkKey.isEmpty
        DebugLog.shared.info(
            .jimeng,
            "image generate start",
            details: "path=\(usingArk ? "ark" : "aksk"), reqKey=\(imageReqKey), prompt_chars=\(prompt.count)"
        )
        let started = Date()
        do {
            if usingArk {
                generatedImageURLs = try await ArkJimengClient(apiKey: imageArkKey)
                    .generateImage(prompt: prompt, model: imageReqKey)
            } else {
                let client = JimengAPIClient(accessKey: imageAK, secretKey: imageSK)
                generatedImageURLs = try await client.generateImage(prompt: prompt, reqKey: imageReqKey)
            }
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            DebugLog.shared.info(
                .jimeng,
                "image generate ok",
                details: "elapsed=\(elapsedMs)ms, urls=\(generatedImageURLs.count)"
            )
        } catch {
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            DebugLog.shared.error(
                .jimeng,
                "image generate failed",
                details: "elapsed=\(elapsedMs)ms, error=\(error.localizedDescription)"
            )
            imageError = error.localizedDescription
        }
        isGeneratingImage = false
    }

    /// 并行用 N 个 prompt 各生成一张图，结果累积到 generatedImageURLs。
    /// 失败的单条不影响其它，但会被记到 imageError 摘要里。
    /// - Parameter referenceImagesData: 若非空，且走 Ark 路径，每个 prompt 会按 round-robin
    ///   方式分配一张参考图做 image-to-image（产品库里有几张图就轮几张参考）。
    func generateImages(prompts: [String], referenceImagesData: [Data] = []) async {
        let cleanPrompts = prompts.filter { !$0.isEmpty }
        guard !cleanPrompts.isEmpty else {
            imageError = "没有可用的提示词"
            return
        }
        isGeneratingImage = true
        imageError = nil
        generatedImageURLs = []

        guard isConfigValidForImage else {
            DebugLog.shared.error(.jimeng, "image config missing")
            imageError = "请先在「我的 → 大模型配置 → 图片生成」中填写 Ark Key 或 AK/SK + req_key"
            isGeneratingImage = false
            return
        }

        let usingArk = !imageArkKey.isEmpty
        DebugLog.shared.info(
            .jimeng,
            "image batch generate start",
            details: "path=\(usingArk ? "ark" : "aksk"), count=\(cleanPrompts.count), reqKey=\(imageReqKey)"
        )
        let started = Date()
        let arkKey = imageArkKey
        let ak = imageAK
        let sk = imageSK
        let reqKey = imageReqKey

        var collected: [String] = []
        var failures: [String] = []
        await withTaskGroup(of: Result<[String], Error>.self) { group in
            for (idx, prompt) in cleanPrompts.enumerated() {
                // round-robin 分配参考图：N 张参考图，N 个 prompt 时一一对应；
                // 数量不等时按余数循环。无参考图则走纯文生图。
                let refData: Data? = referenceImagesData.isEmpty
                    ? nil
                    : referenceImagesData[idx % referenceImagesData.count]
                group.addTask {
                    do {
                        if usingArk {
                            let urls = try await ArkJimengClient(apiKey: arkKey)
                                .generateImage(prompt: prompt, model: reqKey, referenceImageData: refData)
                            return .success(urls)
                        } else {
                            // Volc 旧 API 路径暂未实现 image-to-image；refData 被忽略。
                            let urls = try await JimengAPIClient(accessKey: ak, secretKey: sk)
                                .generateImage(prompt: prompt, reqKey: reqKey)
                            return .success(urls)
                        }
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let urls): collected.append(contentsOf: urls)
                case .failure(let err): failures.append(err.localizedDescription)
                }
            }
        }
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        generatedImageURLs = collected
        if collected.isEmpty {
            imageError = failures.first ?? "生成失败"
            DebugLog.shared.error(
                .jimeng,
                "image batch generate failed",
                details: "elapsed=\(elapsedMs)ms, all \(cleanPrompts.count) tasks failed"
            )
        } else {
            if !failures.isEmpty {
                imageError = "成功 \(collected.count)/\(cleanPrompts.count)，失败：\(failures.first ?? "")"
            }
            DebugLog.shared.info(
                .jimeng,
                "image batch generate ok",
                details: "elapsed=\(elapsedMs)ms, ok=\(collected.count), failed=\(failures.count)"
            )
        }
        isGeneratingImage = false
    }

    // MARK: - Video Generation

    /// 生成视频。
    /// - Parameter referenceImageURLs: 参考帧 URL 列表（来自当前结果页的所有生成图）。
    ///   空数组退化为文生视频；1 张当首帧；≥2 张由 Ark Seedance 综合参考。
    func generateVideo(prompt: String, referenceImageURLs: [String] = []) async {
        isGeneratingVideo = true
        videoError = nil
        generatedVideoURL = nil

        guard isConfigValidForVideo else {
            DebugLog.shared.error(.jimeng, "video config missing")
            videoError = "请先在「我的 → 大模型配置 → 视频生成」中填写 Ark Key 或 AK/SK + req_key"
            isGeneratingVideo = false
            return
        }

        let usingArk = !videoArkKey.isEmpty
        let mode = referenceImageURLs.isEmpty ? "t2v" : "i2v(\(referenceImageURLs.count) frames)"
        DebugLog.shared.info(
            .jimeng,
            "video generate start",
            details: "path=\(usingArk ? "ark" : "aksk"), reqKey=\(videoReqKey), mode=\(mode), prompt_chars=\(prompt.count)"
        )
        let started = Date()
        do {
            if usingArk {
                generatedVideoURL = try await ArkJimengClient(apiKey: videoArkKey)
                    .generateVideo(prompt: prompt, model: videoReqKey, referenceImageURLs: referenceImageURLs)
            } else {
                // Volc 旧 API 路径只支持单首帧。
                let client = JimengAPIClient(accessKey: videoAK, secretKey: videoSK)
                generatedVideoURL = try await client.generateVideo(
                    prompt: prompt,
                    reqKey: videoReqKey,
                    firstFrameURL: referenceImageURLs.first
                )
            }
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            DebugLog.shared.info(
                .jimeng,
                "video generate ok",
                details: "elapsed=\(elapsedMs)ms, url=\(generatedVideoURL ?? "(none)")"
            )
        } catch {
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            DebugLog.shared.error(
                .jimeng,
                "video generate failed",
                details: "elapsed=\(elapsedMs)ms, error=\(error.localizedDescription)"
            )
            videoError = error.localizedDescription
        }
        isGeneratingVideo = false
    }

    func reset() {
        isGeneratingImage = false
        isGeneratingVideo = false
        generatedImageURLs = []
        generatedVideoURL = nil
        imageError = nil
        videoError = nil
    }
}
