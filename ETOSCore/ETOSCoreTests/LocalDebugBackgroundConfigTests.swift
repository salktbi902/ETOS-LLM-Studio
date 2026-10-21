import Foundation
import GRDB
import Testing
@testable import ETOSCore

@MainActor
@Suite("远程文件访问后台连接配置")
struct LocalDebugBackgroundConfigTests {
    @Test("后台连接默认关闭且不随设备同步")
    func defaultsToLocalOptIn() {
        let key = AppConfigKey.localDebugKeepAliveInBackground

        #expect(key.rawValue == "localDebug.keepAliveInBackground")
        #expect(key.defaultValue == .bool(false))
        #expect(key.typeHint == "bool")
        #expect(!key.participatesInSync)
        #expect(!AppConfigStore.shouldTouchWatchConfigDatabase(for: key))
    }

    @Test("已保存的后台连接选择保留布尔值且不会进入同步快照", arguments: [false, true])
    func persistedOptInStaysLocal(_ enabled: Bool) throws {
        let key = AppConfigKey.localDebugKeepAliveInBackground
        let db = try DatabaseQueue()
        try db.write { db in
            try db.execute(sql: "CREATE TABLE app_config (key TEXT PRIMARY KEY, value_text TEXT, value_real REAL, value_integer INTEGER, type_hint TEXT NOT NULL)")
            try db.execute(
                sql: "INSERT INTO app_config (key, value_integer, type_hint) VALUES (?, ?, 'bool')",
                arguments: [key.rawValue, enabled ? 1 : 0]
            )
        }
        let loaded = try db.read { try Persistence.loadAllAppConfigs(from: $0) }
        let stored = try #require(loaded.first { $0.key == key.rawValue })
        let value = try #require(AppConfigStore.appConfigValue(from: stored.value, for: key))
        #expect(value == .bool(enabled))

        let values: [AppConfigKey: AppConfigValue] = [key: value, .enableStreaming: .bool(true)]
        let localSnapshot = AppConfigStore.snapshot(from: values, includeLocalOnly: true)
        let syncedSnapshot = AppConfigStore.snapshot(from: values, includeLocalOnly: false)
        #expect(localSnapshot[key.rawValue] as? Bool == enabled)
        #expect(syncedSnapshot[key.rawValue] == nil)
        #expect(syncedSnapshot[AppConfigKey.enableStreaming.rawValue] as? Bool == true)
    }
}
