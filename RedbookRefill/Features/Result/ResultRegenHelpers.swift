import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Copy / Clipboard

struct ResultCopyHelper {
    static func copyAll(
        record: GenerationRecord,
        onPopToast: @escaping (String) -> Void
    ) {
        HapticManager.lightImpact()
        var parts: [String] = []
        if !record.noteTitle.isEmpty { parts.append("【笔记标题】\(record.noteTitle)") }
        if !record.content.isEmpty { parts.append("【正文】\(record.content)") }
        if !record.tags.isEmpty { parts.append("【标签】\(record.tags.map { "#\($0)" }.joined(separator: " "))") }
        if !record.imageSuggestion.isEmpty { parts.append("【配图建议】\(record.imageSuggestion)") }
        copyToClipboard(parts.joined(separator: "\n"))
        onPopToast("全部内容已复制")
    }

    static func copyToClipboard(_ text: String) {
        #if canImport(UIKit) && !os(macOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    static func copyStringToClipboard(_ text: String) {
        copyToClipboard(text)
    }
}

// MARK: - Save to Inspiration

struct ResultInspirationHelper {
    static func saveToInspiration(
        type: InspirationType,
        content: String,
        source: String,
        repository: Repository,
        onPopToast: @escaping (String) -> Void
    ) {
        let item = InspirationItem(type: type, content: content, source: source)
        repository.saveInspirationItem(item)
        onPopToast("已收藏到灵感板")
    }
}

// MARK: - Save Image/Video

struct ResultSaveHelper {
    static func saveImage(url: String, onPopToast: @escaping (String) -> Void) async {
        guard let imageURL = URL(string: url) else {
            onPopToast("图片链接无效")
            return
        }
        do {
            let data = try Data(contentsOf: imageURL)
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let fileName = URL(string: url)?.lastPathComponent ?? "\(UUID().uuidString).jpg"
            let destURL = cacheDir.appendingPathComponent(fileName)
            try data.write(to: destURL)
            #if canImport(UIKit) && !os(macOS)
            UIImageWriteToSavedPhotosAlbum(UIImage(data: data) ?? UIImage(), nil, nil, nil)
            #endif
            onPopToast("图片已保存")
        } catch {
            onPopToast("保存失败：\(error.localizedDescription)")
        }
    }

    static func saveVideo(url: String, onPopToast: @escaping (String) -> Void) async {
        guard let videoURL = URL(string: url) else {
            onPopToast("视频链接无效")
            return
        }
        do {
            let data = try Data(contentsOf: videoURL)
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let fileName = URL(string: url)?.lastPathComponent ?? "\(UUID().uuidString).mp4"
            let destURL = cacheDir.appendingPathComponent(fileName)
            try data.write(to: destURL)
            #if canImport(UIKit) && !os(macOS)
            if destURL.isFileURL {
                UISaveVideoAtPathToSavedPhotosAlbum(destURL.path, nil, nil, nil)
            }
            #endif
            onPopToast("视频已保存")
        } catch {
            onPopToast("保存失败：\(error.localizedDescription)")
        }
    }

    static func saveAllImages(urls: [String], onPopToast: @escaping (String) -> Void) async {
        var saved = 0
        for url in urls {
            await saveImage(url: url, onPopToast: { _ in })
            saved += 1
        }
        onPopToast("已保存 \(saved) 张")
    }
}

