import CoreGraphics

/// 把识别结果的归一化坐标换算成屏幕坐标。
public enum PreviewGeometry {
    /// - Parameters:
    ///   - rect: Vision 返回的归一化矩形（0~1，原点在图像左下角）
    ///   - imageSize: 被识别图像的像素尺寸
    ///   - viewSize: 以“等比填满”（aspect fill）方式显示该图像的视图尺寸
    /// - Returns: 视图坐标系（原点在左上角）中的矩形
    public static func viewRect(forNormalized rect: CGRect, imageSize: CGSize, viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return .zero
        }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (imageSize.width * scale - viewSize.width) / 2
        let offsetY = (imageSize.height * scale - viewSize.height) / 2

        let width = rect.width * imageSize.width * scale
        let height = rect.height * imageSize.height * scale
        let x = rect.minX * imageSize.width * scale - offsetX
        // 翻转纵轴：归一化坐标的原点在下方
        let y = (1 - rect.minY - rect.height) * imageSize.height * scale - offsetY
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 矩形中心到视图中心的距离，用于挑选“正对着”的那一项
    public static func distanceFromCenter(_ rect: CGRect, in viewSize: CGSize) -> CGFloat {
        let dx = rect.midX - viewSize.width / 2
        let dy = rect.midY - viewSize.height / 2
        return (dx * dx + dy * dy).squareRoot()
    }
}
