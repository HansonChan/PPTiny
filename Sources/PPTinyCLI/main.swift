import Foundation
import PPTinyCore

@main
struct PPTinyCLI {
    static func main() async {
        guard CommandLine.arguments.count >= 2 else {
            print("usage: PPTinyCLI <file.pptx>")
            Foundation.exit(2)
        }

        let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        do {
            let result = try await PPTCompressor().compress(inputURL: inputURL) { update in
                print("[\(Int(update.progress * 100))%] \(update.message)")
            }
            print("output=\(result.outputURL.path)")
            print("backup=\(result.backupURL.path)")
            print("original=\(ByteCountFormatter.string(fromByteCount: result.originalBytes, countStyle: .file))")
            print("compressed=\(ByteCountFormatter.string(fromByteCount: result.compressedBytes, countStyle: .file))")
            print("saved=\(result.savedPercentText)")
            for report in result.reports {
                print("\(report.kind)\t\(report.fileName)\t\(report.summary)")
            }
        } catch {
            print("error=\(error.localizedDescription)")
            Foundation.exit(1)
        }
    }
}
