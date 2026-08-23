import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case english = "en"
    case ukrainian = "ua"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .ukrainian: return "Українська"
        }
    }

    /// Detect from system locale
    static var system: AppLanguage {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang.hasPrefix("uk") ? .ukrainian : .english
    }
}

/// All localized strings for the app.
enum L {
    static var lang: AppLanguage = .system

    // Menu items
    static var powerDetails: String { lang == .ukrainian ? "Деталі потужності" : "Power Details" }
    static var averagingPeriod: String { lang == .ukrainian ? "Період усереднення" : "Averaging Period" }
    static var processAveraging: String { lang == .ukrainian ? "Усереднення процесів" : "Process Averaging" }
    static var refreshRate: String { lang == .ukrainian ? "Частота оновлення" : "Refresh Rate" }
    static var battery: String { lang == .ukrainian ? "Батарея" : "Battery" }
    static var display: String { lang == .ukrainian ? "Дисплей" : "Display" }
    static var activeProcesses: String { lang == .ukrainian ? "Активні процеси" : "Active Processes" }
    static var noActiveProcesses: String { lang == .ukrainian ? "Немає активних процесів" : "No active processes" }
    static var quit: String { lang == .ukrainian ? "Вийти з PowerBar" : "Quit PowerBar" }
    static var instant: String { lang == .ukrainian ? "Миттєво" : "Instant" }
    static var allTimeAverage: String { lang == .ukrainian ? "За весь час" : "All Time Average" }
    static var language: String { lang == .ukrainian ? "Мова" : "Language" }
    static var terminate: String { lang == .ukrainian ? "Завершити" : "Terminate" }
    static func close(_ name: String) -> String { lang == .ukrainian ? "✕ Закрити \(name)" : "✕ Close \(name)" }
    static var instantRaw: String { lang == .ukrainian ? "Миттєво (без усереднення)" : "Instant (raw)" }
    static var loading: String { lang == .ukrainian ? "Завантаження..." : "Loading..." }
    static var stopped: String { lang == .ukrainian ? "Зупинено" : "Stopped" }
    static var error: String { lang == .ukrainian ? "Помилка" : "Error" }
    static var calculating: String { lang == .ukrainian ? "Розрахунок..." : "Calculating..." }
    static var unavailable: String { lang == .ukrainian ? "Недоступно" : "Unavailable" }
    static var remaining: String { lang == .ukrainian ? "залишилось" : "remaining" }
    static var charging: String { lang == .ukrainian ? "заряджається" : "charging" }
    static var brightness: String { lang == .ukrainian ? "яскравість" : "brightness" }

    // Time periods
    static func seconds(_ n: Int) -> String { lang == .ukrainian ? "\(n) секунд" : "\(n) seconds" }
    static func minutes(_ n: Int) -> String { lang == .ukrainian ? "\(n) хвилин" : "\(n) minutes" }
    static var oneMinute: String { lang == .ukrainian ? "1 хвилина" : "1 minute" }
    static var oneHour: String { lang == .ukrainian ? "1 година" : "1 hour" }
}
