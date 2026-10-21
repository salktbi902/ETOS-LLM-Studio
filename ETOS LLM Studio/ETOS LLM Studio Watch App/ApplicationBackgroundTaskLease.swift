import Dispatch
import Foundation

/// watchOS 的短时后台任务；系统到期时只暂停传输，不清除重连目标。
@MainActor
final class ApplicationBackgroundTaskLease {
    private let completion = DispatchSemaphore(value: 0)
    private var expirationHandler: (@MainActor () -> Void)?
    private var hasEnded = false

    init(name: String, expirationHandler: (@MainActor () -> Void)? = nil) {
        self.expirationHandler = expirationHandler
        let completion = completion
        ProcessInfo.processInfo.performExpiringActivity(withReason: name) { [weak self] expired in
            if expired {
                // 系统在并发队列发出到期通知，主线程负责更新连接状态。
                Task { @MainActor [weak self] in
                    self?.expire()
                }
            } else {
                // 只等待这个后台队列；结束或到期会立即释放系统断言。
                completion.wait()
            }
        }
    }

    func end() {
        finish(expired: false)
    }

    func expire() {
        finish(expired: true)
    }

    private func finish(expired: Bool) {
        guard !hasEnded else { return }
        hasEnded = true
        let handler = expired ? expirationHandler : nil
        expirationHandler = nil
        // 先让主线程暂停连接，再释放后台断言。
        handler?()
        completion.signal()
    }

    deinit {
        completion.signal()
    }
}
