import Foundation
import SwiftUI
import Translation

/// 把界面里的翻译请求转交给系统翻译会话，并缓存结果。
///
/// 系统的 `TranslationSession` 只能在 `.translationTask` 修饰符的闭包里拿到，
/// 所以这里用一个异步流把请求送进那个闭包。
@MainActor
final class TranslationBridge: ObservableObject {
    @Published private(set) var translations: [String: String] = [:]
    @Published var lastError: String?

    private var continuation: AsyncStream<[String]>.Continuation?
    private var pending: Set<String> = []
    private var waiting: [String] = []

    func translation(for text: String) -> String? {
        translations[text]
    }

    /// 请求翻译；已有结果或正在翻译的文本会被忽略
    func request(_ texts: [String]) {
        let fresh = texts.filter { translations[$0] == nil && !pending.contains($0) && !waiting.contains($0) }
        guard !fresh.isEmpty else { return }
        if let continuation {
            pending.formUnion(fresh)
            continuation.yield(fresh)
        } else {
            waiting.append(contentsOf: fresh)
        }
    }

    /// 语言改变时清空缓存
    func reset() {
        translations = [:]
        pending = []
        waiting = []
        lastError = nil
    }

    /// 在 `.translationTask` 的闭包里调用；会一直运行到该任务被取消
    func serve(_ session: TranslationSession) async {
        let (stream, continuation) = AsyncStream<[String]>.makeStream()
        self.continuation = continuation

        // 会话就绪前积压的请求，以及上一个会话没处理完的请求
        let backlog = waiting + pending
        waiting = []
        pending = []
        if !backlog.isEmpty {
            pending.formUnion(backlog)
            continuation.yield(backlog)
        }

        for await batch in stream {
            do {
                let requests = batch.map { TranslationSession.Request(sourceText: $0, clientIdentifier: $0) }
                let responses = try await session.translations(from: requests)
                for response in responses {
                    translations[response.sourceText] = response.targetText
                }
                lastError = nil
            } catch is CancellationError {
                break
            } catch {
                lastError = error.localizedDescription
            }
            pending.subtract(batch)
        }
    }
}
