import Vapor
import VisionCore

/// 从请求中解析图片数据，供所有图像类接口共用
enum ImageInput {
    /// 依次尝试：上传文件（imageFile）、本地路径（imagePath）、远程 URL（imageURL）、Base64（imageBase64）
    static func decode(from req: Request) async throws -> Data {
        if let imageFile = try? req.content.get(Data.self, at: "imageFile") {
            return imageFile
        } else if let imagePath = try? req.content.get(String.self, at: "imagePath") {
            guard let fileData = FileManager.default.contents(atPath: imagePath) else {
                throw Abort(.badRequest, reason: "无法读取指定路径的图片文件")
            }
            return fileData
        } else if let imageURL = try? req.content.get(String.self, at: "imageURL") {
            let response = try await req.client.get(URI(string: imageURL))
            guard let remoteData = response.body else {
                throw Abort(.badRequest, reason: "无法从URL获取图片数据")
            }
            return Data(buffer: remoteData)
        } else if let base64String = try? req.content.get(String.self, at: "imageBase64") {
            // 移除可能存在的 base64 头部信息（如 "data:image/jpeg;base64,"）
            let base64Data = base64String.components(separatedBy: ",").last ?? base64String
            guard let decodedData = Data(base64Encoded: base64Data) else {
                throw Abort(.badRequest, reason: "无效的Base64图片数据")
            }
            return decodedData
        }
        throw Abort(.badRequest, reason: "请提供图片文件、本地路径、远程URL或Base64编码数据其中之一")
    }
}

/// 把 VisionCore 的错误转换为带合适状态码的 HTTP 错误，其他错误原样返回
func httpError(from error: Error) -> Error {
    guard let coreError = error as? VisionCoreError else { return error }
    return Abort(
        coreError.isInputError ? .badRequest : .internalServerError,
        reason: coreError.localizedDescription
    )
}

// VisionCore 的结果模型直接作为响应体
extension ClassificationResult: Content {}
extension ClassificationResponse: Content {}
extension BoundingBox: Content {}
extension DetectedObject: Content {}
extension ObjectDetectionResponse: Content {}
extension BarcodeResult: Content {}
extension BarcodeResponse: Content {}
extension PDFPageText: Content {}
extension PDFTextResponse: Content {}
