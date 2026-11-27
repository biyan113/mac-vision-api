import Foundation
import VisionCore

// Vision 的 MCP 服务：通过标准输入输出（每行一条 JSON-RPC 消息）把本机的
// 识别能力提供给 Claude 等 AI 助手。所有工具都只读写调用方给出的本地路径，不联网。
//
// 接入示例：claude mcp add vision -- /path/to/VisionMCP

// MARK: - 工具定义

struct Tool {
    let name: String
    let description: String
    /// 参数名 → 说明
    let properties: [(name: String, description: String)]
    let required: [String]
    let run: ([String: Any]) throws -> String

    var schema: [String: Any] {
        var props: [String: Any] = [:]
        for property in properties {
            props[property.name] = ["type": "string", "description": property.description]
        }
        return [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": props, "required": required],
        ]
    }
}

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func stringArgument(_ arguments: [String: Any], _ name: String) throws -> String {
    guard let value = arguments[name] as? String, !value.isEmpty else {
        throw ToolError(message: "缺少参数 \(name)")
    }
    return value
}

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

func readFile(_ arguments: [String: Any], _ name: String = "path") throws -> Data {
    let url = fileURL(try stringArgument(arguments, name))
    do {
        return try Data(contentsOf: url)
    } catch {
        throw ToolError(message: "无法读取文件 \(url.path)：\(error.localizedDescription)")
    }
}

func writeFile(_ data: Data, _ arguments: [String: Any], _ name: String = "output_path") throws -> String {
    let url = fileURL(try stringArgument(arguments, name))
    do {
        try data.write(to: url, options: .atomic)
    } catch {
        throw ToolError(message: "无法写入文件 \(url.path)：\(error.localizedDescription)")
    }
    return url.path
}

func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
}

/// 图片或 PDF 都接受：PDF 逐页渲染后再处理
func pageImages(_ data: Data) throws -> [Data] {
    guard PDFEngine.looksLikePDF(data) else { return [data] }
    let count = try PDFEngine.pageCount(pdfData: data)
    return try (0..<count).map { try PDFEngine.renderPage(pdfData: data, pageIndex: $0, dpi: 150) }
}

let pathProperty = (name: "path", description: "本机上的图片文件的绝对路径")
let outputProperty = (name: "output_path", description: "结果文件要保存到的绝对路径")

let tools: [Tool] = [
    Tool(
        name: "recognize_text",
        description: "识别图片或 PDF 中的文字（OCR），支持中文、英文、日文、韩文等。PDF 会逐页识别。",
        properties: [
            (name: "path", description: "本机上的图片或 PDF 文件的绝对路径"),
            (name: "languages", description: "可选，逗号分隔的语言代码，例如 zh-Hans,en-US；不填则自动检测"),
        ],
        required: ["path"],
        run: { arguments in
            let data = try readFile(arguments)
            let languages = ((arguments["languages"] as? String) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let options = TextRecognitionOptions(languages: languages)
            let pages = try pageImages(data).map { page in
                try VisionEngine.recognizeText(imageData: page, options: options).map { $0.text }.joined(separator: "\n")
            }
            let text = pages.joined(separator: "\n\n")
            return text.isEmpty ? "（没有识别到文字）" : text
        }
    ),
    Tool(
        name: "extract_text_insights",
        description: "识别图片中的文字，并找出其中的链接、电话号码、日期和地址，返回 JSON。",
        properties: [pathProperty],
        required: ["path"],
        run: { arguments in
            let data = try readFile(arguments)
            let text = try pageImages(data).map { page in
                try VisionEngine.recognizeText(imageData: page).map { $0.text }.joined(separator: "\n")
            }.joined(separator: "\n")
            return try json(TextInsights.detect(in: text))
        }
    ),
    Tool(
        name: "scan_barcodes",
        description: "识别图片中的条形码和二维码，返回内容、码制和位置的 JSON。",
        properties: [pathProperty],
        required: ["path"],
        run: { arguments in
            try json(BarcodeResponse(barcodes: try VisionEngine.scanBarcodes(imageData: try readFile(arguments))))
        }
    ),
    Tool(
        name: "classify_image",
        description: "对图片内容分类，返回置信度最高的若干类别的 JSON。",
        properties: [pathProperty],
        required: ["path"],
        run: { arguments in
            try json(ClassificationResponse(classifications: try VisionEngine.classify(imageData: try readFile(arguments))))
        }
    ),
    Tool(
        name: "detect_objects",
        description: "检测图片中的动物、人脸和人体，返回标签、置信度和位置的 JSON。",
        properties: [pathProperty],
        required: ["path"],
        run: { arguments in
            try json(ObjectDetectionResponse(objects: try VisionEngine.detectObjects(imageData: try readFile(arguments))))
        }
    ),
    Tool(
        name: "remove_background",
        description: "移除图片背景，把主体保存为透明背景的 PNG。需要 macOS 14 或更高版本。",
        properties: [pathProperty, outputProperty],
        required: ["path", "output_path"],
        run: { arguments in
            let png = try VisionEngine.removeBackground(imageData: try readFile(arguments))
            let saved = try writeFile(png, arguments)
            return "已保存到 \(saved)"
        }
    ),
    Tool(
        name: "redact_image",
        description: "给图片里的人脸、文字和条码打马赛克，保存为 PNG。用于分享截图前去除隐私信息。",
        properties: [
            pathProperty,
            outputProperty,
            (name: "targets", description: "可选，逗号分隔：faces、text、barcodes；不填则全部打码"),
        ],
        required: ["path", "output_path"],
        run: { arguments in
            var targets: RedactionTargets = []
            for name in ((arguments["targets"] as? String) ?? "").split(separator: ",") {
                switch name.trimmingCharacters(in: .whitespaces).lowercased() {
                case "faces": targets.insert(.faces)
                case "text": targets.insert(.text)
                case "barcodes": targets.insert(.barcodes)
                default: break
                }
            }
            if targets.isEmpty { targets = .all }
            let result = try Redactor.redact(imageData: try readFile(arguments), targets: targets)
            let saved = try writeFile(result.pngData, arguments)
            return "已对 \(result.regions.count) 处内容打码，保存到 \(saved)"
        }
    ),
    Tool(
        name: "pdf_extract_text",
        description: "提取 PDF 内嵌的文本（不做 OCR）。扫描件没有内嵌文本，请改用 recognize_text。",
        properties: [(name: "path", description: "本机上的 PDF 文件的绝对路径")],
        required: ["path"],
        run: { arguments in
            let text = try PDFEngine.extractText(pdfData: try readFile(arguments), mergePages: true).allText ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "（这个 PDF 没有内嵌文本）" : text
        }
    ),
    Tool(
        name: "make_searchable_pdf",
        description: "把图片或扫描版 PDF 转成可搜索、可复制文字的 PDF（在原图上叠加不可见的识别文字）。",
        properties: [(name: "path", description: "本机上的图片或 PDF 文件的绝对路径"), outputProperty],
        required: ["path", "output_path"],
        run: { arguments in
            let data = try readFile(arguments)
            let pdf = PDFEngine.looksLikePDF(data)
                ? try SearchablePDF.make(pdfData: data)
                : try SearchablePDF.make(imageData: data)
            let saved = try writeFile(pdf, arguments)
            return "已保存到 \(saved)"
        }
    ),
]

// MARK: - JSON-RPC

func send(_ message: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else {
        return
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func reply(_ id: Any, result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func fail(_ id: Any, code: Int, message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

func handle(_ line: String) {
    guard let data = line.data(using: .utf8),
          let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let method = message["method"] as? String
    else {
        return
    }
    // 没有 id 的是通知，不需要回复
    guard let id = message["id"] else { return }
    let params = message["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        reply(id, result: [
            "protocolVersion": (params["protocolVersion"] as? String) ?? "2024-11-05",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "vision", "version": "1.0.0"],
        ])
    case "ping":
        reply(id, result: [:])
    case "tools/list":
        reply(id, result: ["tools": tools.map { $0.schema }])
    case "tools/call":
        guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
            fail(id, code: -32602, message: "未知的工具")
            return
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        do {
            let text = try tool.run(arguments)
            reply(id, result: ["content": [["type": "text", "text": text]], "isError": false])
        } catch {
            reply(id, result: ["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
        }
    default:
        fail(id, code: -32601, message: "不支持的方法：\(method)")
    }
}

while let line = readLine(strippingNewline: true) {
    if !line.trimmingCharacters(in: .whitespaces).isEmpty {
        handle(line)
    }
}
