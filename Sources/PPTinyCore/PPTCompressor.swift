import AppKit
import AVFoundation
import Foundation

public struct CompressionResult: Sendable {
    public let outputURL: URL
    public let backupURL: URL
    public let originalBytes: Int64
    public let compressedBytes: Int64
    public let reports: [MediaReport]

    public var compressedSizeText: String {
        ByteCountFormatter.string(fromByteCount: compressedBytes, countStyle: .file)
    }

    public var savedPercentText: String {
        guard originalBytes > 0 else { return "0%" }
        let ratio = 1 - (Double(compressedBytes) / Double(originalBytes))
        return "\(max(0, Int(ratio * 100)))%"
    }
}

public struct CompressionUpdate: Sendable {
    public let progress: Double
    public let message: String
    public let reports: [MediaReport]
}

public struct MediaReport: Identifiable, Hashable, Sendable {
    public enum Status: Sendable {
        case compressed
        case skipped
        case failed
    }

    public let id = UUID()
    public let kind: String
    public let fileName: String
    public let status: Status
    public let summary: String
}

public final class PPTCompressor: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (CompressionUpdate) -> Void

    private let fileManager = FileManager.default
    private let imageExtensions = Set(["jpg", "jpeg", "png", "bmp", "tif", "tiff"])
    private let videoExtensions = Set(["mp4", "mov", "m4v", "avi", "wmv", "mkv"])
    private let audioExtensions = Set(["mp3", "m4a", "wav", "aac", "aiff", "aif", "wma"])

    public init() {}

    public static func outputURL(for inputURL: URL) -> URL {
        inputURL
    }

    public static func backupURL(for inputURL: URL) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let base = inputURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent("\(base).old.pptx")
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base).old-\(index).pptx")
            index += 1
        }
        return candidate
    }

    public func compress(inputURL: URL, onProgress: @escaping ProgressHandler) async throws -> CompressionResult {
        try await Task.detached(priority: .userInitiated) {
            try self.compressSync(inputURL: inputURL, onProgress: onProgress)
        }.value
    }

    private func compressSync(inputURL: URL, onProgress: ProgressHandler) throws -> CompressionResult {
        let originalBytes = fileSize(inputURL)
        let outputURL = Self.outputURL(for: inputURL)
        let backupURL = Self.backupURL(for: inputURL)
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("PPTiny-\(UUID().uuidString)", isDirectory: true)
        let localInputURL = tempRoot.appendingPathComponent("input.pptx")
        let unpackURL = tempRoot.appendingPathComponent("unpacked", isDirectory: true)
        let compressedTempURL = tempRoot.appendingPathComponent("compressed.pptx")
        try fileManager.createDirectory(at: unpackURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        var reports: [MediaReport] = []
        onProgress(.init(progress: 0.03, message: "读取文件...", reports: reports))
        try copyInputToLocalWorkFile(inputURL, destinationURL: localInputURL)

        onProgress(.init(progress: 0.06, message: "解包 PPTX...", reports: reports))
        _ = try run("/usr/bin/unzip", ["-q", localInputURL.path, "-d", unpackURL.path])

        let mediaURL = unpackURL.appendingPathComponent("ppt/media", isDirectory: true)
        let mediaFiles = listFiles(in: mediaURL)
        let total = max(mediaFiles.count, 1)

        for (index, file) in mediaFiles.enumerated() {
            let ext = file.pathExtension.lowercased()
            let baseProgress = 0.1 + (Double(index) / Double(total)) * 0.76
            onProgress(.init(progress: baseProgress, message: "处理 \(file.lastPathComponent)...", reports: reports))

            do {
                if imageExtensions.contains(ext) {
                    reports.append(try compressImage(file, root: unpackURL))
                } else if videoExtensions.contains(ext) {
                    reports.append(try compressVideo(file, root: unpackURL))
                } else if audioExtensions.contains(ext) {
                    reports.append(try compressAudio(file, root: unpackURL))
                }
            } catch {
                reports.append(.init(kind: mediaKind(ext), fileName: file.lastPathComponent, status: .failed, summary: error.localizedDescription))
            }
        }

        if let fontReport = try removeEmbeddedFonts(root: unpackURL) {
            reports.append(fontReport)
            onProgress(.init(progress: 0.88, message: "移除嵌入字体...", reports: reports))
        }

        onProgress(.init(progress: 0.9, message: "重新打包 PPTX...", reports: reports))
        _ = try run("/usr/bin/zip", ["-qry", compressedTempURL.path, "."], in: unpackURL)

        let compressedBytes = fileSize(compressedTempURL)
        onProgress(.init(progress: 0.96, message: "替换原文件...", reports: reports))
        try replaceOriginal(inputURL: inputURL, compressedURL: compressedTempURL, backupURL: backupURL)

        onProgress(.init(progress: 1, message: "压缩完成", reports: reports))
        return CompressionResult(
            outputURL: outputURL,
            backupURL: backupURL,
            originalBytes: originalBytes,
            compressedBytes: compressedBytes,
            reports: reports
        )
    }

    private func replaceOriginal(inputURL: URL, compressedURL: URL, backupURL: URL) throws {
        try fileManager.moveItem(at: inputURL, to: backupURL)
        do {
            try fileManager.moveItem(at: compressedURL, to: inputURL)
        } catch {
            if fileManager.fileExists(atPath: backupURL.path), !fileManager.fileExists(atPath: inputURL.path) {
                try? fileManager.moveItem(at: backupURL, to: inputURL)
            }
            throw error
        }
    }

    private func copyInputToLocalWorkFile(_ inputURL: URL, destinationURL: URL) throws {
        try validateReadableLocalFile(inputURL)

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(readingItemAt: inputURL, options: [], error: &coordinationError) { readableURL in
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: readableURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            throw cloudFileError(underlying: coordinationError)
        }
        if let copyError {
            throw cloudFileError(underlying: copyError)
        }
        guard fileSize(destinationURL) > 0 else {
            throw NSError(
                domain: "PPTiny.CloudFile",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "文件尚未下载到本机，请先在 Finder 或 OneDrive 中打开/下载后再压缩"]
            )
        }
    }

    private func validateReadableLocalFile(_ url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isReadableKey])
        let logicalSize = values?.fileSize ?? 0
        let allocatedSize = values?.totalFileAllocatedSize ?? 0
        let isReadable = values?.isReadable ?? false

        if logicalSize > 0, allocatedSize == 0 {
            throw NSError(
                domain: "PPTiny.CloudFile",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "这个 PPTX 还是云端占位文件，尚未下载到本机。请先在 Finder 中右键该文件，选择“始终保留在此设备上”，或双击打开等待 OneDrive/iCloud 下载完成后再压缩。"
                ]
            )
        }

        if !isReadable {
            throw NSError(
                domain: "PPTiny.CloudFile",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "当前没有权限读取这个 PPTX。请检查文件权限，或先复制到本机普通文件夹后再压缩。"
                ]
            )
        }
    }

    private func cloudFileError(underlying: Error) -> NSError {
        let message = (underlying as NSError).localizedDescription
        let timedOut = message.localizedCaseInsensitiveContains("timed out")
            || message.localizedCaseInsensitiveContains("timeout")
            || message.localizedCaseInsensitiveContains("Operation timed out")
        let cannotOpen = message.localizedCaseInsensitiveContains("未能打开")
            || message.localizedCaseInsensitiveContains("couldn’t be opened")
            || message.localizedCaseInsensitiveContains("could not be opened")

        if cannotOpen {
            return NSError(
                domain: "PPTiny.CloudFile",
                code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "无法打开这个 PPTX。它可能还在 OneDrive/iCloud 云端或正在同步。请先在 Finder 中右键选择“始终保留在此设备上”，或双击文件等待下载完成后再压缩。"
                ]
            )
        }

        return NSError(
            domain: "PPTiny.CloudFile",
            code: timedOut ? 1 : 0,
            userInfo: [
                NSLocalizedDescriptionKey: timedOut
                    ? "读取云端文件超时。请先在 Finder 中右键选择“始终保留在此设备上”，或等待 OneDrive/iCloud 同步完成后再压缩。"
                    : "无法读取输入文件：\(message)"
            ]
        )
    }

    private func compressImage(_ url: URL, root: URL) throws -> MediaReport {
        let originalBytes = fileSize(url)

        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .init(kind: "图片", fileName: url.lastPathComponent, status: .skipped, summary: "无法读取")
        }

        let width = cgImage.width
        let height = cgImage.height
        let hasAlpha = hasAlpha(cgImage)
        let sourceExt = url.pathExtension.lowercased()
        let outputExt = shouldConvertToJPEG(sourceExtension: sourceExt, hasAlpha: hasAlpha) ? "jpg" : sourceExt
        let finalURL = outputExt == sourceExt ? url : url.deletingPathExtension().appendingPathExtension(outputExt)
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".pptiny-\(UUID().uuidString).\(outputExt)")
        defer { try? fileManager.removeItem(at: temp) }

        let bounds = imageBounds(width: width, height: height)
        let scale = min(Double(bounds.width) / Double(width), Double(bounds.height) / Double(height), 1)

        guard scale < 1 || outputExt != sourceExt else {
            return .init(kind: "图片", fileName: url.lastPathComponent, status: .skipped, summary: "\(width)x\(height)")
        }

        let targetWidth = scale < 1 ? max(1, Int(Double(width) * scale)) : width
        let targetHeight = scale < 1 ? max(1, Int(Double(height) * scale)) : height
        try resizeImage(cgImage, sourceExtension: outputExt, width: targetWidth, height: targetHeight, outputURL: temp)

        let newBytes = fileSize(temp)
        guard newBytes > 0 else {
            return .init(kind: "图片", fileName: url.lastPathComponent, status: .failed, summary: "输出为空")
        }

        try replaceMedia(
            originalURL: url,
            replacementURL: temp,
            finalURL: finalURL,
            root: root,
            contentType: outputExt == "jpg" || outputExt == "jpeg" ? "image/jpeg" : "image/png"
        )

        return .init(
            kind: "图片",
            fileName: finalURL.lastPathComponent,
            status: .compressed,
            summary: "\(width)x\(height) → \(targetWidth)x\(targetHeight), \(formatBytes(originalBytes)) → \(formatBytes(newBytes))"
        )
    }

    private func shouldConvertToJPEG(sourceExtension: String, hasAlpha: Bool) -> Bool {
        ["png", "bmp", "tif", "tiff"].contains(sourceExtension) && !hasAlpha
    }

    private func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }

    private func imageBounds(width: Int, height: Int) -> (width: Int, height: Int) {
        width >= height ? (1920, 1080) : (1080, 1920)
    }

    private func resizeImage(_ image: CGImage, sourceExtension: String, width: Int, height: Int, outputURL: URL) throws {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "PPTiny.Image", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建图片上下文"])
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let resized = context.makeImage() else {
            throw NSError(domain: "PPTiny.Image", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法生成缩放图片"])
        }

        let bitmap = NSBitmapImageRep(cgImage: resized)
        let ext = sourceExtension.lowercased()
        let fileType: NSBitmapImageRep.FileType = ["jpg", "jpeg"].contains(ext) ? .jpeg : .png
        let properties: [NSBitmapImageRep.PropertyKey: Any] = fileType == .jpeg
            ? [.compressionFactor: 0.8]
            : [:]

        guard let data = bitmap.representation(using: fileType, properties: properties) else {
            throw NSError(domain: "PPTiny.Image", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法编码图片"])
        }
        try data.write(to: outputURL, options: .atomic)
    }

    private func compressVideo(_ url: URL, root: URL) throws -> MediaReport {
        let originalBytes = fileSize(url)
        let newURL = url.deletingPathExtension().appendingPathExtension("mp4")
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".pptiny-\(UUID().uuidString).mp4")
        defer { try? fileManager.removeItem(at: temp) }

        let asset = AVURLAsset(url: url)
        let duration = max(CMTimeGetSeconds(asset.duration), 1)
        let maxBytes = Int64(duration * (4_000_000 + 128_000) / 8)
        try exportAsset(asset, to: temp, fileType: .mp4, preferredPresets: [
            AVAssetExportPreset1920x1080,
            AVAssetExportPresetHighestQuality,
            AVAssetExportPresetMediumQuality
        ], fileLengthLimit: maxBytes)

        let newBytes = fileSize(temp)
        guard newBytes > 0, isMeaningfullySmaller(newBytes, than: originalBytes) else {
            return .init(kind: "视频", fileName: url.lastPathComponent, status: .skipped, summary: "已低于上限")
        }

        try replaceMedia(originalURL: url, replacementURL: temp, finalURL: newURL, root: root, contentType: "video/mp4")
        return .init(kind: "视频", fileName: newURL.lastPathComponent, status: .compressed, summary: "\(formatBytes(originalBytes)) → \(formatBytes(newBytes))")
    }

    private func compressAudio(_ url: URL, root: URL) throws -> MediaReport {
        let originalBytes = fileSize(url)
        let newURL = url.deletingPathExtension().appendingPathExtension("m4a")
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".pptiny-\(UUID().uuidString).m4a")
        defer { try? fileManager.removeItem(at: temp) }

        let asset = AVURLAsset(url: url)
        let duration = max(CMTimeGetSeconds(asset.duration), 1)
        let maxBytes = Int64(duration * 128_000 / 8)
        try exportAsset(asset, to: temp, fileType: .m4a, preferredPresets: [
            AVAssetExportPresetAppleM4A
        ], fileLengthLimit: maxBytes)

        let newBytes = fileSize(temp)
        guard newBytes > 0, isMeaningfullySmaller(newBytes, than: originalBytes) else {
            return .init(kind: "音频", fileName: url.lastPathComponent, status: .skipped, summary: "已低于上限")
        }

        try replaceMedia(originalURL: url, replacementURL: temp, finalURL: newURL, root: root, contentType: "audio/mp4")
        return .init(kind: "音频", fileName: newURL.lastPathComponent, status: .compressed, summary: "\(formatBytes(originalBytes)) → \(formatBytes(newBytes))")
    }

    private func exportAsset(
        _ asset: AVAsset,
        to outputURL: URL,
        fileType: AVFileType,
        preferredPresets: [String],
        fileLengthLimit: Int64
    ) throws {
        let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        guard let preset = preferredPresets.first(where: { compatiblePresets.contains($0) }),
              let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw NSError(domain: "PPTiny.AVFoundation", code: 1, userInfo: [NSLocalizedDescriptionKey: "系统不支持该音视频格式"])
        }

        session.outputURL = outputURL
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true
        if fileLengthLimit > 0 {
            session.fileLengthLimit = fileLengthLimit
        }

        let semaphore = DispatchSemaphore(value: 0)
        session.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        switch session.status {
        case .completed:
            return
        case .failed, .cancelled:
            throw NSError(
                domain: "PPTiny.AVFoundation",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: session.error?.localizedDescription ?? "音视频导出失败"]
            )
        default:
            throw NSError(domain: "PPTiny.AVFoundation", code: 3, userInfo: [NSLocalizedDescriptionKey: "音视频导出未完成"])
        }
    }

    private func replaceMedia(originalURL: URL, replacementURL: URL, finalURL: URL, root: URL, contentType: String) throws {
        let oldName = originalURL.lastPathComponent
        let newName = finalURL.lastPathComponent

        if fileManager.fileExists(atPath: finalURL.path), finalURL != originalURL {
            try fileManager.removeItem(at: finalURL)
        }
        try? fileManager.removeItem(at: originalURL)
        try fileManager.moveItem(at: replacementURL, to: finalURL)

        if oldName != newName {
            try replaceTextOccurrences(in: root, oldName: oldName, newName: newName)
            try ensureContentType(root: root, ext: finalURL.pathExtension.lowercased(), contentType: contentType)
        }
    }

    private func removeEmbeddedFonts(root: URL) throws -> MediaReport? {
        let fontsURL = root.appendingPathComponent("ppt/fonts", isDirectory: true)
        guard fileManager.fileExists(atPath: fontsURL.path) else { return nil }

        let originalBytes = directorySize(fontsURL)
        let presentationURL = root.appendingPathComponent("ppt/presentation.xml")
        let relsURL = root.appendingPathComponent("ppt/_rels/presentation.xml.rels")

        if var presentation = try? String(contentsOf: presentationURL, encoding: .utf8) {
            presentation = replaceRegex("<p:embeddedFontLst>.*?</p:embeddedFontLst>", in: presentation, with: "")
            presentation = presentation
                .replacingOccurrences(of: " embedTrueTypeFonts=\"1\"", with: "")
                .replacingOccurrences(of: " saveSubsetFonts=\"1\"", with: "")
            try presentation.write(to: presentationURL, atomically: true, encoding: .utf8)
        }

        if var rels = try? String(contentsOf: relsURL, encoding: .utf8) {
            rels = replaceRegex("<Relationship[^>]+Type=\"http://schemas\\.openxmlformats\\.org/officeDocument/2006/relationships/font\"[^>]*/>", in: rels, with: "")
            try rels.write(to: relsURL, atomically: true, encoding: .utf8)
        }

        let contentTypesURL = root.appendingPathComponent("[Content_Types].xml")
        if var contentTypes = try? String(contentsOf: contentTypesURL, encoding: .utf8) {
            contentTypes = replaceRegex("<Default Extension=\"fntdata\" ContentType=\"application/x-fontdata\"/>", in: contentTypes, with: "")
            try contentTypes.write(to: contentTypesURL, atomically: true, encoding: .utf8)
        }

        try fileManager.removeItem(at: fontsURL)
        return .init(kind: "字体", fileName: "embedded fonts", status: .compressed, summary: "\(formatBytes(originalBytes)) → 0 bytes")
    }

    private func replaceRegex(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private func replaceTextOccurrences(in root: URL, oldName: String, newName: String) throws {
        for file in listFiles(in: root) where ["xml", "rels"].contains(file.pathExtension.lowercased()) {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  text.contains(oldName) else { continue }
            let updated = text.replacingOccurrences(of: oldName, with: newName)
            try updated.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func ensureContentType(root: URL, ext: String, contentType: String) throws {
        let url = root.appendingPathComponent("[Content_Types].xml")
        guard var text = try? String(contentsOf: url, encoding: .utf8),
              !text.contains("Extension=\"\(ext)\"") else { return }
        let defaultNode = "<Default Extension=\"\(ext)\" ContentType=\"\(contentType)\"/>"
        text = text.replacingOccurrences(of: "</Types>", with: "\(defaultNode)</Types>")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func listFiles(in directory: URL) -> [URL] {
        guard fileManager.fileExists(atPath: directory.path),
              let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true ? url : nil
        }
        .sorted { $0.path < $1.path }
    }

    private func isMeaningfullySmaller(_ newBytes: Int64, than originalBytes: Int64) -> Bool {
        newBytes < Int64(Double(originalBytes) * 0.95)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func directorySize(_ url: URL) -> Int64 {
        listFiles(in: url).reduce(Int64(0)) { $0 + fileSize($1) }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func mediaKind(_ ext: String) -> String {
        if imageExtensions.contains(ext) { return "图片" }
        if videoExtensions.contains(ext) { return "视频" }
        if audioExtensions.contains(ext) { return "音频" }
        return "媒体"
    }

    private func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]) { current, _ in current }

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "PPTiny.Process",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorText.isEmpty ? outputText : errorText]
            )
        }
        return outputText
    }
}
