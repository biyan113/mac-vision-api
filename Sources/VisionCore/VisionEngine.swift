import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// 对 Vision 框架的封装。所有函数同步执行并可能抛出错误，线程调度由调用方负责。
public enum VisionEngine {
    // MARK: - 文字识别

    /// 识别图像中的文字，按 Vision 返回的顺序逐行给出
    public static func recognizeText(
        imageData: Data,
        options: TextRecognitionOptions = TextRecognitionOptions()
    ) throws -> [RecognizedTextLine] {
        let request = VNRecognizeTextRequest()
        if options.languages.isEmpty {
            // 自动检测语言
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = options.languages
        }
        if options.fast {
            request.recognitionLevel = .fast
        }

        try VNImageRequestHandler(data: imageData).perform([request])

        var lines: [RecognizedTextLine] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            lines.append(RecognizedTextLine(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                boundingBox: BoundingBox(observation.boundingBox)
            ))
        }
        return lines
    }

    // MARK: - 背景移除

    /// 当前系统是否支持背景移除（需要 macOS 14.0+）
    public static var supportsBackgroundRemoval: Bool {
        if #available(macOS 14.0, *) {
            return true
        }
        return false
    }

    /// 移除图像背景，返回裁剪到前景范围、带透明通道的 PNG 数据
    public static func removeBackground(imageData: Data) throws -> Data {
        guard #available(macOS 14.0, *) else {
            throw VisionCoreError.unsupportedSystem("macOS 14.0 或更高版本")
        }

        let handler = VNImageRequestHandler(data: imageData)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw VisionCoreError.noForeground
        }

        let maskedBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )

        let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
        guard let cgImage = CIContext(options: nil).createCGImage(ciImage, from: ciImage.extent) else {
            throw VisionCoreError.imageConversionFailed("图像转换失败。")
        }
        return try ImageCoding.pngData(from: cgImage)
    }

    // MARK: - 图像分类

    public static func classify(
        imageData: Data,
        maxResults: Int = 10,
        minimumConfidence: Float = 0.01
    ) throws -> [ClassificationResult] {
        let request = VNClassifyImageRequest()
        try VNImageRequestHandler(data: imageData).perform([request])

        return (request.results ?? [])
            .filter { $0.confidence > minimumConfidence }
            .prefix(maxResults)
            .map { ClassificationResult(identifier: $0.identifier, confidence: Double($0.confidence)) }
    }

    // MARK: - 物体检测

    /// 检测动物、人脸和人体，结果按此顺序排列
    public static func detectObjects(imageData: Data) throws -> [DetectedObject] {
        let animalRequest = VNRecognizeAnimalsRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()

        try VNImageRequestHandler(data: imageData).perform([animalRequest, faceRequest, humanRequest])

        var objects: [DetectedObject] = []
        for observation in animalRequest.results ?? [] {
            objects.append(DetectedObject(
                label: observation.labels.first?.identifier ?? "animal",
                confidence: Double(observation.labels.first?.confidence ?? 0),
                boundingBox: BoundingBox(observation.boundingBox)
            ))
        }
        for observation in faceRequest.results ?? [] {
            objects.append(DetectedObject(
                label: "face",
                confidence: Double(observation.confidence),
                boundingBox: BoundingBox(observation.boundingBox)
            ))
        }
        for observation in humanRequest.results ?? [] {
            objects.append(DetectedObject(
                label: "human",
                confidence: Double(observation.confidence),
                boundingBox: BoundingBox(observation.boundingBox)
            ))
        }
        return objects
    }

    // MARK: - 条码识别

    public static func scanBarcodes(imageData: Data) throws -> [BarcodeResult] {
        let request = VNDetectBarcodesRequest()
        try VNImageRequestHandler(data: imageData).perform([request])

        return (request.results ?? []).map { observation in
            BarcodeResult(
                payload: observation.payloadStringValue ?? "",
                symbology: observation.symbology.rawValue,
                boundingBox: BoundingBox(observation.boundingBox)
            )
        }
    }
}

/// 图像编码工具
public enum ImageCoding {
    /// 把 CGImage 编码为 PNG 数据
    public static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw VisionCoreError.imageConversionFailed("创建图像目标失败。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VisionCoreError.imageConversionFailed("图像编码失败")
        }
        return data as Data
    }
}
