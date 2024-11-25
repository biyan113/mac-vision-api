// 导入必要的框架
import Vapor
import Logging
import NIOCore
import NIOPosix

/// 应用程序入口点
/// 负责初始化和启动整个应用程序
@main
enum Entrypoint {
    /// 主函数 - 应用程序的启动入口点
    /// - Throws: 启动过程中可能发生的错误
    static func main() async throws {
        // 检测并配置环境变量
        var env = try Environment.detect()
        // 初始化日志系统
        try LoggingSystem.bootstrap(from: &env)
        
        // 创建应用程序实例
        let app = try await Application.make(env)

        // NIO作为Swift并发执行器的配置说明
        // 启用此配置可以减少NIO和Swift Concurrency之间的上下文切换
        // 注意：这可能会导致使用.wait()的库出现问题，以及在清理关闭时出现问题
        // 如果启用，在此点之前调用异步函数时应该小心，因为可能会导致断言失败
        // let executorTakeoverSuccess = NIOSingletons.unsafeTryInstallSingletonPosixEventLoopGroupAsConcurrencyGlobalExecutor()
        // app.logger.debug("尝试将SwiftNIO的EventLoopGroup安装为Swift的全局并发执行器", metadata: ["success": .stringConvertible(executorTakeoverSuccess)])
        
        do {
            // 配置应用程序
            try await configure(app)
        } catch {
            // 错误处理：记录错误并尝试关闭应用
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        
        // 启动应用程序
        try await app.execute()
        // 应用程序结束时进行清理
        try await app.asyncShutdown()
    }
}
