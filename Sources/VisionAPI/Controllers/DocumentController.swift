#if compiler(>=6.2)
import SwiftOpenAPI
import Vapor
import Vision

/// 文档结构识别与镜头污渍检测：macOS 26.0+
@available(macOS 26.0, *)
struct DocumentController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.grouped("text-detection").post("recognize-document", use: recognizeDocumentRequest)
            .openAPI(
                description: "文档结构识别（macOS 26+）：返回全文、段落、表格（按行列）以及检测到的邮箱和电话。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(DocumentResponse.self)
            )

        routes.grouped("vision").post("lens-smudge", use: lensSmudgeRequest)
            .openAPI(
                description: "镜头污渍检测（macOS 26+）：confidence 越接近 1 表示越可能是镜头脏污导致的模糊。",
                body: .type(VisionImageInput.self),
                contentType: .multipart(.formData),
                response: .type(LensSmudgeResponse.self)
            )
    }

    @Sendable func recognizeDocumentRequest(req: Request) async throws -> DocumentResponse {
        let imageData = try await InputResolver.image(from: req)

        let observations: [DocumentObservation]
        do {
            observations = try await RecognizeDocumentsRequest().perform(on: imageData)
        } catch {
            throw Abort(.unprocessableEntity, reason: "无法处理该图片：\(error.localizedDescription)")
        }

        guard let document = observations.first?.document else {
            throw Abort(.unprocessableEntity, reason: "未在图片中识别到文档")
        }

        let paragraphs = document.paragraphs.map { $0.transcript }
        let tables = document.tables.map { table in
            DocumentTable(rows: table.rows.map { row in row.map { $0.content.text.transcript } })
        }

        var emails: [String] = []
        var phoneNumbers: [String] = []
        for item in document.text.detectedData {
            switch item.match.details {
            case .emailAddress(let email):
                emails.append(email.emailAddress)
            case .phoneNumber(let phone):
                phoneNumbers.append(phone.phoneNumber)
            default:
                break
            }
        }

        return DocumentResponse(
            text: document.text.transcript,
            paragraphs: paragraphs,
            tables: tables,
            emails: emails,
            phoneNumbers: phoneNumbers
        )
    }

    @Sendable func lensSmudgeRequest(req: Request) async throws -> LensSmudgeResponse {
        let imageData = try await InputResolver.image(from: req)
        do {
            let observation = try await DetectLensSmudgeRequest().perform(on: imageData)
            return LensSmudgeResponse(confidence: Double(observation.confidence))
        } catch {
            throw Abort(.unprocessableEntity, reason: "无法处理该图片：\(error.localizedDescription)")
        }
    }
}

struct DocumentTable: Content {
    /// 按行排列的单元格文本
    var rows: [[String]]
}

struct DocumentResponse: Content {
    var text: String
    var paragraphs: [String]
    var tables: [DocumentTable]
    var emails: [String]
    var phoneNumbers: [String]
}

struct LensSmudgeResponse: Content {
    var confidence: Double
}
#endif
