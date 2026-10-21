// ============================================================================
// ApplicationBackgroundTaskLease.swift
// ============================================================================

import UIKit

/// 为必须完成的短收尾工作持有可重复结束的后台任务，避免多个异步出口重复释放。
@MainActor
final class ApplicationBackgroundTaskLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var expirationHandler: (@MainActor () -> Void)?
    private var hasEnded = false

    init(name: String, expirationHandler: (@MainActor () -> Void)? = nil) {
        self.expirationHandler = expirationHandler
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.expire()
            }
        }
        if identifier == .invalid {
            Task { @MainActor [weak self] in
                self?.expire()
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
        // 先暂停传输，再归还系统额度，避免进程先挂起而保留过期连接状态。
        handler?()
        if identifier != .invalid {
            UIApplication.shared.endBackgroundTask(identifier)
        }
        identifier = .invalid
    }

    deinit {
        let identifier = identifier
        if identifier != .invalid {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(identifier)
            }
        }
    }
}
