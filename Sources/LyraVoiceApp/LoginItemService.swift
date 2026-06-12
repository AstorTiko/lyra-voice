import Foundation
import ServiceManagement
import LyraVoiceCore

/// Управление автозапуском приложения при входе в систему через `SMAppService`
/// (современный API ServiceManagement, macOS 13+). Источник правды — статус
/// самой службы; настройка `launchAtLogin` хранит лишь намерение пользователя и
/// сверяется с фактическим статусом на старте.
@MainActor
enum LoginItemService {
    /// Включён ли автозапуск прямо сейчас (по данным системы).
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Включает/выключает автозапуск. Возвращает фактический статус после операции
    /// (может отличаться от запрошенного, если система отклонила регистрацию).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            DiagnosticsLog.write("login item set failed enabled=\(enabled) status=\(service.status.rawValue) error=\(error.localizedDescription)")
        }
        return service.status == .enabled
    }
}
