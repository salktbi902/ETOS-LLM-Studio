import Testing
@testable import ETOS_LLM_Studio_App

@MainActor
@Suite("后台任务到期与主动结束")
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

    @Test("回到前台结束任务后忽略排队的到期通知")
    func endingPreventsLateExpiration() {
        var expired = false
        let lease = ApplicationBackgroundTaskLease(name: "local-debug-test") {
            expired = true
        }
        lease.end()
        lease.end()
        lease.expire()
        #expect(!expired)
    }
}
