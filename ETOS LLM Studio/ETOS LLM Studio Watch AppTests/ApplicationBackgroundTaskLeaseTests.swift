import Testing
@testable import ETOS_LLM_Studio_Watch_App

@MainActor
@Suite("调试后台任务到期与主动结束")
struct ApplicationBackgroundTaskLeaseTests {
    @Test("到期只通知一次")
    func expirationIsDeliveredOnce() {
        var expirationCount = 0
        let lease = ApplicationBackgroundTaskLease(name: "local-debug-test") {
            expirationCount += 1
        }
        lease.expire()
        lease.expire()
        lease.end()
        #expect(expirationCount == 1)
    }

    @Test("前台恢复后不再处理旧任务到期")
    func endingPreventsLateExpiration() {
        var expired = false
        let lease = ApplicationBackgroundTaskLease(name: "local-debug-test") {
            expired = true
        }
        lease.end()
        lease.expire()
        #expect(!expired)
    }
}
