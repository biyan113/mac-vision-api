import Foundation
import VisionCore

/// 图形界面提供的 Vision 功能
enum VisionFeature: Int, CaseIterable, Sendable {
    case ocr
    case backgroundRemoval
    case classify
    case detectObjects
    case barcode

    var title: String {
        switch self {
        case .ocr: return L("文字识别", "Text")
        case .backgroundRemoval: return L("背景移除", "Remove Background")
        case .classify: return L("图像分类", "Classify")
        case .detectObjects: return L("物体检测", "Detect Objects")
        case .barcode: return L("条码识别", "Barcodes")
        }
    }

    /// 批量处理时输出文件的扩展名
    var outputExtension: String {
        switch self {
        case .ocr: return "txt"
        case .backgroundRemoval: return "png"
        case .classify, .detectObjects, .barcode: return "json"
        }
    }
}

/// 叠加在原图上的检测框（Vision 归一化坐标，原点在左下角）
struct OverlayBox: Sendable {
    var rect: CGRect
    var label: String
}

/// 一次处理的结果，供界面显示和导出
struct AnalysisOutput: Sendable {
    /// 逐行的文本结果
    var lines: [String] = []
    /// 没有结果时显示的提示
    var emptyMessage = ""
    /// 图片形式的结果（PNG），目前仅背景移除使用
    var imageData: Data?
    /// 检测框；数量与 lines 相同时，第 n 行对应第 n 个框
    var boxes: [OverlayBox] = []
    /// 与 HTTP API 响应字段一致的 JSON
    var json: Data?

    var text: String {
        lines.joined(separator: "\n")
    }

    /// 文本行与检测框是否一一对应
    var linksLinesToBoxes: Bool {
        !boxes.isEmpty && boxes.count == lines.count
    }
}

/// 携带可显示文案的错误，可安全地跨线程传递
struct MessageError: Error, Sendable {
    let message: String
}

/// 在后台线程执行耗时操作
enum Background {
    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async -> Result<T, MessageError> {
        await Task.detached(priority: .userInitiated) { () -> Result<T, MessageError> in
            do {
                return .success(try work())
            } catch {
                return .failure(MessageError(message: error.localizedDescription))
            }
        }.value
    }
}

/// 调用 VisionCore 并把结果整理成界面需要的形式。同步执行，应在后台线程调用。
enum Analyzer {
    private struct TextExport: Encodable {
        let text: String
        let lines: [RecognizedTextLine]
    }

    static func run(
        _ feature: VisionFeature,
        imageData: Data,
        options: TextRecognitionOptions
    ) throws -> AnalysisOutput {
        switch feature {
        case .ocr:
            let lines = try VisionEngine.recognizeText(imageData: imageData, options: options)
            let text = lines.map { $0.text }.joined(separator: "\n")
            return AnalysisOutput(
                lines: lines.map { $0.text },
                emptyMessage: L("（没有识别到文字）", "(No text recognized)"),
                boxes: lines.map { OverlayBox(rect: $0.boundingBox.cgRect, label: "") },
                json: encode(TextExport(text: text, lines: lines))
            )

        case .backgroundRemoval:
            let png = try VisionEngine.removeBackground(imageData: imageData)
            return AnalysisOutput(imageData: png)

        case .classify:
            let results = try VisionEngine.classify(imageData: imageData)
            return AnalysisOutput(
                lines: results.map { "\(percent($0.confidence))  \($0.identifier)" },
                emptyMessage: L("（没有分类结果）", "(No classification results)"),
                json: encode(ClassificationResponse(classifications: results))
            )

        case .detectObjects:
            let objects = try VisionEngine.detectObjects(imageData: imageData)
            return AnalysisOutput(
                lines: objects.map { "\(percent($0.confidence))  \($0.label)" },
                emptyMessage: L("（未检测到动物、人脸或人体）", "(No animals, faces or people detected)"),
                boxes: objects.map { OverlayBox(rect: $0.boundingBox.cgRect, label: $0.label) },
                json: encode(ObjectDetectionResponse(objects: objects))
            )

        case .barcode:
            let barcodes = try VisionEngine.scanBarcodes(imageData: imageData)
            return AnalysisOutput(
                lines: barcodes.map { barcode in
                    let payload = barcode.payload.isEmpty
                        ? L("（无法解码内容）", "(payload not decodable)")
                        : barcode.payload.replacingOccurrences(of: "\n", with: " ")
                    return "[\(shortSymbology(barcode.symbology))] \(payload)"
                },
                emptyMessage: L("（未检测到条形码或二维码）", "(No barcodes or QR codes detected)"),
                boxes: barcodes.map {
                    OverlayBox(rect: $0.boundingBox.cgRect, label: shortSymbology($0.symbology))
                },
                json: encode(BarcodeResponse(barcodes: barcodes))
            )
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(value)
    }

    private static func percent(_ confidence: Double) -> String {
        String(format: "%5.1f%%", confidence * 100)
    }

    private static func shortSymbology(_ rawValue: String) -> String {
        rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
    }
}
