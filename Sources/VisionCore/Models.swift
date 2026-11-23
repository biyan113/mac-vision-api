import CoreGraphics
import Foundation

// 这些模型同时用作 HTTP API 的响应体和图形界面的 JSON 导出格式，
// 修改字段名会改变 API 的响应格式。

/// 归一化的矩形区域（Vision 坐标系，原点在左下角，取值 0...1）
public struct BoundingBox: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - 文字识别

/// 文字识别选项
public struct TextRecognitionOptions: Sendable {
    /// 识别语言代码，空数组表示自动检测语言
    public var languages: [String]
    /// 是否使用快速模式（默认使用精确模式）
    public var fast: Bool

    public init(languages: [String] = [], fast: Bool = false) {
        self.languages = languages
        self.fast = fast
    }
}

/// 识别到的一行文字
public struct RecognizedTextLine: Codable, Sendable {
    public var text: String
    public var confidence: Double
    public var boundingBox: BoundingBox

    public init(text: String, confidence: Double, boundingBox: BoundingBox) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

// MARK: - 图像分类

public struct ClassificationResult: Codable, Sendable {
    public var identifier: String
    public var confidence: Double

    public init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

public struct ClassificationResponse: Codable, Sendable {
    public var classifications: [ClassificationResult]

    public init(classifications: [ClassificationResult]) {
        self.classifications = classifications
    }
}

// MARK: - 物体检测

public struct DetectedObject: Codable, Sendable {
    public var label: String
    public var confidence: Double
    public var boundingBox: BoundingBox

    public init(label: String, confidence: Double, boundingBox: BoundingBox) {
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

public struct ObjectDetectionResponse: Codable, Sendable {
    public var objects: [DetectedObject]

    public init(objects: [DetectedObject]) {
        self.objects = objects
    }
}

// MARK: - 条码识别

public struct BarcodeResult: Codable, Sendable {
    public var payload: String
    public var symbology: String
    public var boundingBox: BoundingBox

    public init(payload: String, symbology: String, boundingBox: BoundingBox) {
        self.payload = payload
        self.symbology = symbology
        self.boundingBox = boundingBox
    }
}

public struct BarcodeResponse: Codable, Sendable {
    public var barcodes: [BarcodeResult]

    public init(barcodes: [BarcodeResult]) {
        self.barcodes = barcodes
    }
}

// MARK: - PDF

/// PDF 单页文本
public struct PDFPageText: Codable, Sendable {
    /// 页码，从 1 开始
    public let pageNumber: Int
    public let text: String

    public init(pageNumber: Int, text: String) {
        self.pageNumber = pageNumber
        self.text = text
    }
}

/// PDF 文本抽取结果
public struct PDFTextResponse: Codable, Sendable {
    public let totalPages: Int
    public let extractedPages: [PDFPageText]
    public let allText: String?

    public init(totalPages: Int, extractedPages: [PDFPageText], allText: String?) {
        self.totalPages = totalPages
        self.extractedPages = extractedPages
        self.allText = allText
    }
}

// MARK: - 错误

public enum VisionCoreError: LocalizedError, Sendable {
    case unsupportedSystem(String)
    case noForeground
    case imageConversionFailed(String)
    case invalidPDF
    case pageOutOfRange(pageCount: Int)
    case pageUnavailable(pageNumber: Int)
    case invalidPageRange(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSystem(let requirement): return "此功能需要 \(requirement)"
        case .noForeground: return "未找到前景实例。"
        case .imageConversionFailed(let reason): return reason
        case .invalidPDF: return "无效的PDF文件格式"
        case .pageOutOfRange(let pageCount): return "页面索引超出范围，PDF共有\(pageCount)页"
        case .pageUnavailable(let pageNumber): return "无法获取第\(pageNumber)页"
        case .invalidPageRange(let reason): return reason
        }
    }

    /// 是否由调用方的输入引起（HTTP 服务据此返回 400 而不是 500）
    public var isInputError: Bool {
        switch self {
        case .invalidPDF, .pageOutOfRange, .pageUnavailable, .invalidPageRange: return true
        case .unsupportedSystem, .noForeground, .imageConversionFailed: return false
        }
    }
}
