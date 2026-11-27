import CoreImage
import Foundation
import Vision

/// 隐私打码：把人脸、文字、条码所在的区域做粗颗粒的马赛克处理
public enum Redactor {
    public static func redact(imageData: Data, targets: RedactionTargets = .all) throws -> RedactionResult {
        // 1. 找出需要打码的区域
        let faceRequest = VNDetectFaceRectanglesRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        let barcodeRequest = VNDetectBarcodesRequest()

        var requests: [VNRequest] = []
        if targets.contains(.faces) { requests.append(faceRequest) }
        if targets.contains(.text) { requests.append(textRequest) }
        if targets.contains(.barcodes) { requests.append(barcodeRequest) }
        if !requests.isEmpty {
            try VNImageRequestHandler(data: imageData).perform(requests)
        }

        var rects: [CGRect] = []
        if targets.contains(.faces) {
            rects += (faceRequest.results ?? []).map { $0.boundingBox }
        }
        if targets.contains(.text) {
            rects += (textRequest.results ?? []).map { $0.boundingBox }
        }
        if targets.contains(.barcodes) {
            rects += (barcodeRequest.results ?? []).map { $0.boundingBox }
        }
        // 稍微放大一点，避免边缘露出
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        rects = rects.map { $0.insetBy(dx: -0.008, dy: -0.008).intersection(unit) }.filter { !$0.isEmpty }

        // 2. 在按拍摄方向摆正后的图像上打码（Vision 的坐标也是相对摆正后的图像）
        guard let image = CIImage(data: imageData, options: [.applyOrientationProperty: true]) else {
            throw VisionCoreError.imageConversionFailed("无法解码图片")
        }
        let extent = image.extent
        var output = image

        // 每个区域单独做马赛克，色块大小取区域短边的四分之一：
        // 一行文字或一个条码最多只剩几个色块，无法再被辨认或解码
        let source = image.clampedToExtent()
        for rect in rects {
            let region = CGRect(
                x: extent.minX + rect.minX * extent.width,
                y: extent.minY + rect.minY * extent.height,
                width: rect.width * extent.width,
                height: rect.height * extent.height
            )
            let blockSize = max(min(region.width, region.height) / 4, 8)
            let pixellated = source
                .applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: blockSize,
                    kCIInputCenterKey: CIVector(x: region.minX, y: region.minY),
                ])
                .cropped(to: region)
            output = pixellated.composited(over: output)
        }

        guard let cgImage = CIContext(options: nil).createCGImage(output, from: extent) else {
            throw VisionCoreError.imageConversionFailed("图像转换失败。")
        }
        return RedactionResult(
            pngData: try ImageCoding.pngData(from: cgImage),
            regions: rects.map { BoundingBox($0) }
        )
    }
}
