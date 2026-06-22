import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PPTinyCore

@main
struct PPTinyApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 520, height: 540)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

private enum Bauhaus {
    static let paper = Color(red: 0.957, green: 0.933, blue: 0.875)
    static let ink = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let red = Color(red: 0.843, green: 0.2, blue: 0.165)
    static let blue = Color(red: 0.122, green: 0.373, blue: 0.667)
    static let yellow = Color(red: 0.949, green: 0.788, blue: 0.298)
    static let muted = Color(red: 0.46, green: 0.43, blue: 0.37)
}

struct ContentView: View {
    @StateObject private var model = PPTinyViewModel()
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Bauhaus.paper.ignoresSafeArea()

            VStack(spacing: 14) {
                header

                dropZone
                filePanel

                Button(action: model.compress) {
                    Label(model.primaryButtonTitle, systemImage: model.primaryButtonIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledBauhausButtonStyle())
                .disabled(!model.canCompress)

                if model.isWorking || model.result != nil {
                    ProgressView(value: model.progress)
                        .tint(Bauhaus.red)
                        .frame(height: 8)
                }

                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 20)
        }
        .foregroundStyle(Bauhaus.ink)
        .background(WindowAccessor { window in
            window.styleMask.remove(.resizable)
            window.setContentSize(NSSize(width: 520, height: 540))
        })
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("PPTiny")
                .font(.system(size: 28, weight: .black, design: .default))
            Spacer()
            Rectangle().fill(Bauhaus.blue).frame(width: 52, height: 12)
            Circle().fill(Bauhaus.red).frame(width: 18, height: 18)
        }
    }

    private var dropZone: some View {
        Button(action: model.chooseFile) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 24, weight: .bold))

                Text(model.dropTitle)
                    .font(.system(size: 17, weight: .black))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(model.dropSubtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Bauhaus.muted)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(isTargeted ? Bauhaus.yellow.opacity(0.55) : Color.clear)
            .overlay(Rectangle().stroke(Bauhaus.ink, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .disabled(model.isWorking)
    }

    private var filePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.statusText)
                        .font(.system(size: 15, weight: .black))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(model.outputDescription)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Bauhaus.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: 300, alignment: .leading)
                Spacer()
                Text(model.inputSizeText)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Bauhaus.blue)
                    .frame(width: 82, alignment: .trailing)
            }

            queueList

            if let result = model.result {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("压缩后 \(result.compressedSizeText)")
                        Text("节省 \(result.savedPercentText)")
                    }
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Bauhaus.blue)
                    Spacer()
                    Button {
                        model.revealOutput()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(OutlineBauhausButtonStyle(compact: true))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .overlay(Rectangle().stroke(Bauhaus.ink, lineWidth: 3))
    }

    private var queueList: some View {
        Group {
            if model.inputURLs.isEmpty {
                Text(model.outputDescription)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Bauhaus.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(model.inputURLs.enumerated()), id: \.element.path) { index, url in
                            queueRow(index: index, url: url)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 148)
                .overlay(Rectangle().stroke(Bauhaus.ink.opacity(0.28), lineWidth: 1))
            }
        }
    }

    private func queueRow(index: Int, url: URL) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Bauhaus.paper)
                .frame(width: 22, height: 22)
                .background(model.currentIndex == index && model.isWorking ? Bauhaus.red : Bauhaus.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .black))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.backupDescription(for: url))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Bauhaus.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(model.sizeText(for: url))
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Bauhaus.blue)
                .frame(width: 56, alignment: .trailing)

            Button {
                model.removeInput(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .black))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isWorking ? Bauhaus.muted : Bauhaus.red)
            .disabled(model.isWorking)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(model.currentIndex == index && model.isWorking ? Bauhaus.yellow.opacity(0.45) : Color.clear)
    }

    private var footer: some View {
        HStack {
            Text("图片≤1080p · 视频4Mbps · 音频128k")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Bauhaus.muted)
            Spacer()
            Button(action: model.clear) {
                Text("清空")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(Bauhaus.red)
            .disabled(model.isWorking)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !model.isWorking else { return false }
        let fileProviders = providers.enumerated().filter { _, provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let accumulator = DropURLAccumulator()

        for (index, provider) in fileProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                if let url, url.pathExtension.lowercased() == "pptx" {
                    accumulator.append(url, at: index)
                }
            }
        }

        group.notify(queue: .main) {
            let urls = accumulator.urlsInOrder()
            model.setInputs(urls)
        }
        return true
    }
}

final class DropURLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var indexedURLs: [(Int, URL)] = []

    func append(_ url: URL, at index: Int) {
        lock.lock()
        indexedURLs.append((index, url))
        lock.unlock()
    }

    func urlsInOrder() -> [URL] {
        lock.lock()
        let urls = indexedURLs.sorted { $0.0 < $1.0 }.map(\.1)
        lock.unlock()
        return urls
    }
}

struct FilledBauhausButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(Bauhaus.paper)
            .padding(.vertical, 15)
            .background(configuration.isPressed ? Bauhaus.blue : Bauhaus.red)
            .overlay(Rectangle().stroke(Bauhaus.ink, lineWidth: 3))
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}

struct OutlineBauhausButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 17, weight: .black))
            .foregroundStyle(Bauhaus.ink)
            .padding(.vertical, compact ? 7 : 15)
            .padding(.horizontal, compact ? 12 : 0)
            .background(configuration.isPressed ? Bauhaus.yellow.opacity(0.8) : Color.clear)
            .overlay(Rectangle().stroke(Bauhaus.ink, lineWidth: compact ? 2 : 3))
    }
}

@MainActor
final class PPTinyViewModel: ObservableObject {
    @Published private(set) var inputURLs: [URL] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var progress: Double = 0
    @Published private(set) var isWorking = false
    @Published private(set) var statusText = "等待 PPTX 文件"
    @Published private(set) var reports: [MediaReport] = []
    @Published private(set) var result: CompressionResult?

    private let compressor = PPTCompressor()

    var canCompress: Bool {
        !inputURLs.isEmpty && !isWorking
    }

    var primaryButtonTitle: String {
        isWorking ? "压缩中 \(Int(progress * 100))%" : "一键压缩"
    }

    var primaryButtonIcon: String {
        isWorking ? "hourglass" : "bolt.fill"
    }

    var inputFileName: String {
        currentInputURL?.lastPathComponent ?? "未选择文件"
    }

    var dropTitle: String {
        if inputURLs.isEmpty { return "拖入 PPTX" }
        if inputURLs.count == 1 { return inputURLs[0].lastPathComponent }
        return "已选择 \(inputURLs.count) 个 PPTX"
    }

    var dropSubtitle: String {
        inputURLs.isEmpty ? "或点击选择文件" : "点击可重新选择文件"
    }

    var inputSizeText: String {
        if let result {
            return ByteCountFormatter.string(fromByteCount: result.originalBytes, countStyle: .file)
        }
        guard !inputURLs.isEmpty else { return "0 MB" }
        let total = inputURLs.reduce(Int64(0)) { $0 + fileSize($1) }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var outputDescription: String {
        guard let inputURL = currentInputURL else { return "压缩后保留原文件名，旧文件改为 .old.pptx" }
        return "旧文件：\(PPTCompressor.backupURL(for: inputURL).lastPathComponent)"
    }

    func backupDescription(for url: URL) -> String {
        "旧文件：\(PPTCompressor.backupURL(for: url).lastPathComponent)"
    }

    func sizeText(for url: URL) -> String {
        ByteCountFormatter.string(fromByteCount: fileSize(url), countStyle: .file)
    }

    private var currentInputURL: URL? {
        guard !inputURLs.isEmpty else { return nil }
        let index = min(currentIndex, inputURLs.count - 1)
        return inputURLs[index]
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pptx") ?? .data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            setInputs(panel.urls)
        }
    }

    func setInputs(_ urls: [URL]) {
        inputURLs = urls.filter { $0.pathExtension.lowercased() == "pptx" }
        currentIndex = 0
        result = nil
        reports = []
        progress = 0
        if inputURLs.count == 1 {
            statusText = "已选择 \(inputURLs[0].lastPathComponent)"
        } else if inputURLs.count > 1 {
            statusText = "已选择 \(inputURLs.count) 个文件"
        } else {
            statusText = "等待 PPTX 文件"
        }
    }

    func removeInput(at index: Int) {
        guard !isWorking, inputURLs.indices.contains(index) else { return }
        inputURLs.remove(at: index)
        currentIndex = min(currentIndex, max(inputURLs.count - 1, 0))
        result = nil
        reports = []
        progress = 0

        if inputURLs.count == 1 {
            statusText = "已选择 \(inputURLs[0].lastPathComponent)"
        } else if inputURLs.count > 1 {
            statusText = "已选择 \(inputURLs.count) 个文件"
        } else {
            statusText = "等待 PPTX 文件"
        }
    }

    func clear() {
        inputURLs = []
        currentIndex = 0
        result = nil
        reports = []
        progress = 0
        statusText = "等待 PPTX 文件"
    }

    func compress() {
        guard !inputURLs.isEmpty else { return }
        isWorking = true
        result = nil
        reports = []
        currentIndex = 0
        progress = 0
        statusText = "准备压缩..."

        Task {
            var completed = 0
            var failures = 0

            for (index, url) in inputURLs.enumerated() {
                currentIndex = index
                reports = []
                let base = Double(index) / Double(inputURLs.count)
                let span = 1.0 / Double(inputURLs.count)
                progress = base
                statusText = "正在压缩 \(index + 1)/\(inputURLs.count)：\(url.lastPathComponent)"

                do {
                    let output = try await compressor.compress(inputURL: url) { update in
                        Task { @MainActor in
                            self.progress = base + update.progress * span
                            self.statusText = "正在压缩 \(index + 1)/\(self.inputURLs.count)：\(url.lastPathComponent)"
                            self.reports = update.reports
                        }
                    }
                    result = output
                    reports = output.reports
                    completed += 1
                } catch {
                    failures += 1
                    statusText = "压缩失败 \(index + 1)/\(inputURLs.count)：\(error.localizedDescription)"
                }
            }

            progress = 1
            statusText = failures == 0 ? "压缩完成：\(completed) 个文件" : "完成 \(completed) 个，失败 \(failures) 个"
            isWorking = false
        }
    }

    func revealOutput() {
        guard let outputURL = result?.outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
