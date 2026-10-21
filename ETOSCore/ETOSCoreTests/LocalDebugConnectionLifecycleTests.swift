import Foundation
import Network
import Testing
@testable import ETOSCore

@MainActor
@Suite("本地调试后台挂起与前台恢复")
struct LocalDebugConnectionLifecycleTests {
    @Test("后台挂起关闭传输与重连任务，但保留用户连接意图")
    func suspensionPreservesReconnectIntentAndCancelsTransport() {
        let server = LocalDebugServer()
        server.beginAutoReconnect(host: "127.0.0.1", port: "7654", useHTTPMode: true)
        server.reconnectAttempt = 4
        server.isRunning = true
        server.isTransferring = true
        let token = server.connectionToken
        let timer = Timer(timeInterval: 60, repeats: true) { _ in }
        server.httpPollingTimer = timer
        server.httpSession = URLSession(configuration: .ephemeral)
        server.wsConnection = NWConnection(host: "127.0.0.1", port: 7654, using: .tcp)
        let connectionTask = Task<Void, Never> { try? await Task.sleep(nanoseconds: 60_000_000_000) }
        let pollTask = Task<Void, Never> { try? await Task.sleep(nanoseconds: 60_000_000_000) }
        server.httpConnectionTask = connectionTask
        server.httpPollTask = pollTask
        server.scheduleReconnectIfNeeded()
        let reconnectTask = server.reconnectTask
        let reconnectAttempt = server.reconnectAttempt

        server.suspendForBackground()

        #expect(server.isAutoReconnectEnabled)
        #expect(server.reconnectTarget?.host == "127.0.0.1")
        #expect(server.reconnectTarget?.port == "7654")
        #expect(server.reconnectTarget?.useHTTP == true)
        #expect(server.connectionToken != token && !server.isCurrentConnection(token))
        #expect(!server.isRunning && !server.isTransferring)
        #expect(server.wsConnection == nil && server.httpSession == nil)
        #expect(server.httpPollingTimer == nil && !timer.isValid)
        #expect(connectionTask.isCancelled && pollTask.isCancelled)
        #expect(reconnectTask?.isCancelled == true && server.reconnectTask == nil)
        #expect(server.reconnectAttempt == reconnectAttempt)
        #expect(!server.isCurrentConnection(server.connectionToken))
        server.disconnect()
    }

    @Test("挂起期间迟到的失败回调不会重新调度连接")
    func suspendedConnectionDoesNotReconnectAfterLateFailure() {
        let server = LocalDebugServer()
        server.beginAutoReconnect(host: "127.0.0.1", port: "7654", useHTTPMode: true)
        server.suspendForBackground()
        let token = server.connectionToken
        let status = server.connectionStatus

        server.handleConnectionLost(errorMessage: "late failure")
        server.scheduleReconnectIfNeeded()

        #expect(server.reconnectTask == nil)
        #expect(server.connectionToken == token && server.connectionStatus == status)
        #expect(server.isAutoReconnectEnabled && server.reconnectTarget != nil)
        server.disconnect()
    }

    @Test("前台恢复立即使用保留地址重连，并清除退避次数")
    func resumeStartsRetainedConnectionImmediately() async {
        let server = LocalDebugServer()
        server.beginAutoReconnect(host: "127.0.0.1", port: "7654", useHTTPMode: true)
        server.reconnectAttempt = 4
        server.suspendForBackground()
        server.useHTTP = false
        let suspendedToken = server.connectionToken

        server.resumeIfNeeded()

        #expect(server.connectionToken != suspendedToken)
        #expect(server.serverURL == "127.0.0.1:7654" && server.useHTTP)
        #expect(server.httpSession != nil && server.httpConnectionTask != nil)
        #expect(server.reconnectAttempt == 0 && server.reconnectTask == nil)
        // Cancel before yielding so this state test never sends a network request.
        server.disconnect()
        await server.waitForPendingOperations()
    }

    @Test("已连接时重复恢复不会替换当前连接")
    func resumeLeavesRunningConnectionAlone() {
        let server = LocalDebugServer()
        server.beginAutoReconnect(host: "127.0.0.1", port: "7654", useHTTPMode: true)
        server.isRunning = true
        let token = server.connectionToken

        server.resumeIfNeeded()

        #expect(server.isRunning && server.connectionToken == token)
        #expect(server.httpSession == nil && server.reconnectTask == nil)
        server.disconnect()
    }

    @Test("未挂起的连接尝试不会因短暂失活后恢复而被替换", arguments: [true, false])
    func resumeLeavesInFlightConnectionAlone(useHTTP: Bool) {
        let server = LocalDebugServer()
        server.beginAutoReconnect(host: "127.0.0.1", port: "7654", useHTTPMode: useHTTP)
        let session = URLSession(configuration: .ephemeral)
        let connection = NWConnection(host: "127.0.0.1", port: 7654, using: .tcp)
        if useHTTP {
            server.httpSession = session
        } else {
            server.wsConnection = connection
        }
        let token = server.connectionToken

        server.resumeIfNeeded()

        #expect(server.connectionToken == token && server.isAutoReconnectEnabled)
        if useHTTP {
            #expect(server.httpSession === session)
        } else {
            #expect(server.wsConnection === connection)
        }
        server.disconnect()
        session.invalidateAndCancel()
        connection.cancel()
    }

    @Test("用户主动断开后前台恢复不能重新连接")
    func explicitDisconnectCancelsAutomaticResume() {
        let server = LocalDebugServer()
        server.beginAutoReconnect(host: "127.0.0.1", port: "7654", useHTTPMode: true)
        server.suspendForBackground()
        server.disconnect()
        let token = server.connectionToken

        server.resumeIfNeeded()

        #expect(!server.isAutoReconnectEnabled && server.reconnectTarget == nil)
        #expect(server.connectionToken == token)
        #expect(server.httpSession == nil && server.reconnectTask == nil)
    }

    @Test("从未连接的客户端不会因前后台切换自动连接")
    func lifecycleDoesNotEnableAutomaticReconnect() {
        let server = LocalDebugServer()
        server.suspendForBackground()
        let token = server.connectionToken

        server.resumeIfNeeded()

        #expect(!server.isAutoReconnectEnabled && server.reconnectTarget == nil)
        #expect(server.connectionToken == token)
        #expect(server.httpSession == nil && server.reconnectTask == nil)
    }
}
