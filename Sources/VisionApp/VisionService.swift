import CoreImage
import Foundation
import Vision

/// 图形界面支持的 Vision 功能
enum VisionFeature: Int, CaseIterable, Sendable {
    case ocr
    case backgroundRemoval
    case classify
    case detectObjects
    case barcode

    var title: String {
        switch self {
        case .ocr: return "文字识别"
        case .backgroundRemoval: return "背景移除"
        case .classify: return "图像分类"
        case .detectObjects: return "物体检测"
        case .barcode: return "条码识别"
        }
    }
}

/// OCR 选项
struct OCROptions: Sendable {
    /// 识别语言，空数组表示自动检测
    var languages: [String] = []
    /// 是否使用快速模式
    var fast = false
}

/// 检测框（Vision 归一化坐标，原点在左下角）
struct VisionBox: Sendable {
    var rect: CGRect
    var label: String
}

/// 一次 Vision 处理的输出
struct VisionOutput: Sendable {
    /// 文本形式的结果
    var text = ""
    /// 图片形式的结果（PNG 数据），目前仅背景移除使用
    var imageData: Data?
    /// 需要叠加在原图上的检测框
    var boxes: [VisionBox] = []
}

enum VisionServiceError: LocalizedError {
    case unsupportedSystem(String)
    case noForeground
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem(let requirement): return "此功能需要 \(requirement)"
        case .noForeground: return "未找到前景主体"
        case .imageConversionFailed: return "图像转换失败"
        }
    }
}

/// 直接调用 Vision 框架的同步处理函数，应在后台线程调用
enum VisionService {
    static func run(_ feature: VisionFeature, imageData: Data, options: OCROptions) throws -> VisionOutput {
        switch feature {
        case .ocr: return try recognizeText(imageData, options: options)
        case .backgroundRemoval: return try removeBackground(imageData)
        case .classify: return try classify(imageData)
        case .detectObjects: return try detectObjects(imageData)
        case .barcode: return try scanBarcodes(imageData)
        }
    }

    // MARK: - 文字识别

    private static func recognizeText(_ data: Data, options: OCROptions) throws -> VisionOutput {
        let request = VNRecognizeTextRequest()
        if options.languages.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = options.languages
        }
        request.recognitionLevel = options.fast ? .fast : .accurate

        try VNImageRequestHandler(data: data).perform([request])

        var lines: [String] = []
        var boxes: [VisionBox] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            lines.append(candidate.string)
            boxes.append(VisionBox(rect: observation.boundingBox, label: ""))
        }
        return VisionOutput(text: lines.joined(separator: "\n"), boxes: boxes)
    }

    // MARK: - 背景移除

    private static func removeBackground(_ data: Data) throws -> VisionOutput {
        guard #available(macOS 14.0, *) else {
            throw VisionServiceError.unsupportedSystem("macOS 14.0 或更高版本")
        }
        let handler = VNImageRequestHandler(data: data)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw VisionServiceError.noForeground
        }

        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )

        let ciImage = CIImage(cvPixelBuffer: buffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let png = CIContext().pngRepresentation(of: ciImage, format: .RGBA8, colorSpace: colorSpace) else {
            throw VisionServiceError.imageConversionFailed
        }
        return VisionOutput(text: "已移除背景，共 \(observation.allInstances.count) 个前景主体", imageData: png)
    }

    // MARK: - 图像分类

    private static func classify(_ data: Data) throws -> VisionOutput {
        let request = VNClassifyImageRequest()
        try VNImageRequestHandler(data: data).perform([request])

        let lines = (request.results ?? [])
            .filter { $0.confidence > 0.01 }
            .prefix(10)
            .map { "\(percent($0.confidence))  \($0.identifier)" }
        return VisionOutput(text: lines.isEmpty ? "未得到分类结果" : lines.joined(separator: "\n"))
    }

    // MARK: - 物体检测

    private static func detectObjects(_ data: Data) throws -> VisionOutput {
        let animalRequest = VNRecognizeAnimalsRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()
        try VNImageRequestHandler(data: data).perform([animalRequest, faceRequest, humanRequest])

        var boxes: [VisionBox] = []
        var lines: [String] = []

        for observation in animalRequest.results ?? [] {
            let label = observation.labels.first?.identifier ?? "animal"
            let confidence = observation.labels.first?.confidence ?? observation.confidence
            boxes.append(VisionBox(rect: observation.boundingBox, label: label))
            lines.append("\(percent(confidence))  \(label)")
        }
        for observation in faceRequest.results ?? [] {
            boxes.append(VisionBox(rect: observation.boundingBox, label: "face"))
            lines.append("\(percent(observation.confidence))  face")
        }
        for observation in humanRequest.results ?? [] {
            boxes.append(VisionBox(rect: observation.boundingBox, label: "human"))
            lines.append("\(percent(observation.confidence))  human")
        }

        return VisionOutput(
            text: lines.isEmpty ? "未检测到动物、人脸或人体" : lines.joined(separator: "\n"),
            boxes: boxes
        )
    }

    // MARK: - 条码识别

    private static func scanBarcodes(_ data: Data) throws -> VisionOutput {
        let request = VNDetectBarcodesRequest()
        try VNImageRequestHandler(data: data).perform([request])

        var boxes: [VisionBox] = []
        var lines: [String] = []
        for observation in request.results ?? [] {
            let symbology = observation.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
            boxes.append(VisionBox(rect: observation.boundingBox, label: symbology))
            lines.append("[\(symbology)] \(observation.payloadStringValue ?? "（无法解码内容）")")
        }
        return VisionOutput(
            text: lines.isEmpty ? "未检测到条形码或二维码" : lines.joined(separator: "\n"),
            boxes: boxes
        )
    }

    private static func percent(_ confidence: Float) -> String {
        String(format: "%5.1f%%", Double(confidence) * 100)
    }
}
