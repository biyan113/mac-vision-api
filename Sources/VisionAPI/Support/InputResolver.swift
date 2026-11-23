import Foundation
import NIOCore
import NIOPosix
import Vapor

/// 解析后的输入数据
struct ResolvedInput: Sendable {
    var data: Data
    /// 原始文件名（如果能得到），用于推断扩展名
    var filename: String?
}

/// 统一处理四种输入方式：文件上传 / 本地路径 / 远程 URL / Base64。
///
/// 字段名由前缀决定，例如前缀 `image` 对应
/// `imageFile`、`imagePath`、`imageURL`、`imageBase64`。
enum InputResolver {
    static func image(from req: Request) async throws -> Data {
        try await resolve(from: req, prefix: "image", label: "图片").data
    }

    static func resolve(from req: Request, prefix: String, label: String) async throws -> ResolvedInput {
        let config = req.application.serviceConfig

        // 1. 文件上传（multipart）
        if let file = try? req.content.get(File.self, at: "\(prefix)File") {
            let data = Data(buffer: file.data)
            guard !data.isEmpty else {
                throw Abort(.badRequest, reason: "上传的\(label)文件为空")
            }
            return ResolvedInput(data: data, filename: file.filename)
        }
        if let data = try? req.content.get(Data.self, at: "\(prefix)File"), !data.isEmpty {
            return ResolvedInput(data: data, filename: nil)
        }

        // 2. 本地路径（默认关闭）
        if let path = try? req.content.get(String.self, at: "\(prefix)Path"), !path.isEmpty {
            guard config.allowLocalFiles else {
                throw Abort(.forbidden, reason: "服务未开启本地路径读取。设置环境变量 VISION_ALLOW_LOCAL_FILES=true 后可使用 \(prefix)Path")
            }
            guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else {
                throw Abort(.badRequest, reason: "无法读取指定路径的\(label)文件")
            }
            return ResolvedInput(data: data, filename: URL(fileURLWithPath: path).lastPathComponent)
        }

        // 3. 远程 URL
        if let urlString = try? req.content.get(String.self, at: "\(prefix)URL"), !urlString.isEmpty {
            let data = try await fetch(urlString, req: req, label: label)
            return ResolvedInput(data: data, filename: URL(string: urlString)?.lastPathComponent)
        }

        // 4. Base64（支持 data URL 前缀）
        if let base64 = try? req.content.get(String.self, at: "\(prefix)Base64"), !base64.isEmpty {
            var payload = Substring(base64)
            if base64.hasPrefix("data:"), let comma = base64.firstIndex(of: ",") {
                payload = base64[base64.index(after: comma)...]
            }
            guard let data = Data(base64Encoded: String(payload), options: .ignoreUnknownCharacters), !data.isEmpty else {
                throw Abort(.badRequest, reason: "无效的 Base64 \(label)数据")
            }
            return ResolvedInput(data: data, filename: nil)
        }

        throw Abort(.badRequest, reason: "请提供 \(prefix)File、\(prefix)Path、\(prefix)URL 或 \(prefix)Base64 之一")
    }

    // MARK: - 远程获取

    private static func fetch(_ urlString: String, req: Request, label: String) async throws -> Data {
        var current = urlString

        // 手动跟随重定向，每一跳都重新校验目标地址
        for _ in 0 ..< 5 {
            guard let url = URL(string: current),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = url.host, !host.isEmpty
            else {
                throw Abort(.badRequest, reason: "无效的 URL，仅支持 http/https")
            }

            if !req.application.serviceConfig.allowPrivateURLs, isPrivateHost(host) {
                throw Abort(.forbidden, reason: "不允许访问回环或内网地址。设置环境变量 VISION_ALLOW_PRIVATE_URLS=true 后可使用")
            }

            let response = try await req.client.get(URI(string: current))
            let code = Int(response.status.code)

            if (300 ..< 400).contains(code), let location = response.headers.first(name: .location),
               let next = URL(string: location, relativeTo: url) {
                current = next.absoluteString
                continue
            }
            guard (200 ..< 300).contains(code) else {
                throw Abort(.badRequest, reason: "获取远程\(label)失败，HTTP 状态码 \(code)")
            }
            guard let body = response.body, body.readableBytes > 0 else {
                throw Abort(.badRequest, reason: "无法从 URL 获取\(label)数据")
            }
            return Data(buffer: body)
        }
        throw Abort(.badRequest, reason: "远程\(label)重定向次数过多")
    }

    /// 基础的 SSRF 防护：拦截回环、链路本地、私有网段的字面量地址与常见内部域名。
    /// 注意：不解析 DNS，不能防御指向内网的公网域名。
    static func isPrivateHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        if host == "localhost" || host.hasSuffix(".localhost")
            || host.hasSuffix(".local") || host.hasSuffix(".internal") {
            return true
        }

        // IPv4 字面量
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4 {
            let octets = parts.compactMap { UInt8($0) }
            if octets.count == 4 {
                let (a, b) = (octets[0], octets[1])
                return a == 0 || a == 10 || a == 127
                    || (a == 169 && b == 254)
                    || (a == 172 && (16 ... 31).contains(b))
                    || (a == 192 && b == 168)
                    || (a == 100 && (64 ... 127).contains(b))
            }
        }

        // IPv6 字面量
        if host.contains(":") {
            return host == "::1" || host == "::"
                || host.hasPrefix("fc") || host.hasPrefix("fd")
                || host.hasPrefix("fe8") || host.hasPrefix("fe9")
                || host.hasPrefix("fea") || host.hasPrefix("feb")
                || host.hasPrefix("::ffff:")
        }

        return false
    }
}

/// 把同步的 Vision / CoreGraphics 计算放到 NIO 线程池执行，避免阻塞 Swift 并发线程。
enum Offload {
    static func run<T: Sendable>(_ req: Request, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await req.application.threadPool.runIfActive(work)
    }
}
