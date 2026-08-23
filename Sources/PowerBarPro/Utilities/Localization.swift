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

    // Settings rows & tooltips
    static var batteryAveraging: String { lang == .ukrainian ? "Усереднення батареї" : "Battery Averaging" }
    static var averagingPeriodHelp: String {
        lang == .ukrainian
            ? "Вікно усереднення для ватів у меню-барі та Total Power. Instant — сире останнє значення без згладжування."
            : "Averaging window for the menu bar wattage and Total Power. Instant shows the raw latest sample with no smoothing."
    }
    static var batteryAveragingHelp: String {
        lang == .ukrainian
            ? "Вікно усереднення споживання, з якого рахується прогноз «скільки протримається батарея». Довше вікно — стабільніший прогноз."
            : "Averaging window of power draw used for the battery time-remaining estimate. A longer window gives a steadier estimate."
    }
    static var processAveragingHelp: String {
        lang == .ukrainian
            ? "Згладжування ватів у списку процесів. Raw — миттєві значення, стрибають сильніше."
            : "Smoothing window for per-process wattage in the process list. Raw shows instant values, which jump around more."
    }
    static var refreshRateHelp: String {
        lang == .ukrainian
            ? "Як часто опитуються апаратні лічильники енергії. Частіше — точніше, але трохи більше власного споживання."
            : "How often the hardware energy counters are sampled. Faster is more responsive but costs slightly more power itself."
    }
    static var untilFull: String { lang == .ukrainian ? "до повного" : "until full" }
    static var powerAlerts: String { lang == .ukrainian ? "Алерти споживання" : "Power Alerts" }
    static var alertThreshold: String { lang == .ukrainian ? "Поріг алерту" : "Alert Threshold" }
    static var launchAtLogin: String { lang == .ukrainian ? "Запуск при вході" : "Launch at Login" }
    static var powerAlertsHelp: String {
        lang == .ukrainian
            ? "Сповіщення, коли один застосунок споживає більше порогу довше 5 хвилин поспіль."
            : "Notify when a single app draws more than the threshold continuously for 5 minutes."
    }
    static var alertThresholdHelp: String {
        lang == .ukrainian
            ? "Скільки ват має споживати застосунок, щоб спрацював алерт."
            : "How many watts an app must draw to trigger the alert."
    }
    static var launchAtLoginHelp: String {
        lang == .ukrainian
            ? "Автоматично запускати PowerBarPro після входу в систему."
            : "Start PowerBarPro automatically when you log in."
    }
    static func alertTitle(_ app: String) -> String {
        lang == .ukrainian ? "\(app) тягне багато енергії" : "\(app) is drawing a lot of power"
    }
    static func alertBody(watts: Double, minutes: Int) -> String {
        lang == .ukrainian
            ? String(format: "≈%.0f Вт уже %d хв поспіль. Можливо, варто його закрити.", watts, minutes)
            : String(format: "≈%.0fW for %d min straight. Consider closing it.", watts, minutes)
    }
    static var session: String { lang == .ukrainian ? "сесія" : "session" }
    static var sessionEnergyHelp: String {
        lang == .ukrainian
            ? "Скільки енергії система спожила за час роботи PowerBarPro, і середня потужність за сесію."
            : "Energy the system consumed while PowerBarPro has been running, and the session's average power."
    }
    static var cpuClusters: String { lang == .ukrainian ? "КЛАСТЕРИ CPU" : "CPU CLUSTERS" }
    static var sensors: String { lang == .ukrainian ? "СЕНСОРИ" : "SENSORS" }
    static var agentSessions: String { lang == .ukrainian ? "СЕСІЇ АГЕНТІВ" : "AGENT SESSIONS" }
    static var noAgentSessions: String {
        lang == .ukrainian ? "Немає сесій Claude Code / Codex CLI" : "No Claude Code / Codex CLI sessions"
    }
    static var refresh: String { lang == .ukrainian ? "Оновити" : "Refresh" }
    static var cancel: String { lang == .ukrainian ? "Скасувати" : "Cancel" }
    static var showInFinder: String { lang == .ukrainian ? "Показати у Finder" : "Show in Finder" }
    static var killSessionConfirm: String { lang == .ukrainian ? "Завершити сесію" : "Quit Session" }
    static func killSessionTitle(_ label: String, pid: Int32) -> String {
        lang == .ukrainian ? "Завершити сесію «\(label)» (PID \(pid))?" : "Quit session “\(label)” (PID \(pid))?"
    }
    static var killSessionBody: String {
        lang == .ukrainian
            ? "Розмова зберігається на диску — `claude --resume` / `codex resume` у тій самій теці поверне її."
            : "The conversation is preserved on disk — `claude --resume` / `codex resume` in the same folder brings it back."
    }
    static func helpers(_ mb: Int) -> String {
        lang == .ukrainian ? "MCP та хелпери \(mb) MB" : "MCP & helpers \(mb) MB"
    }
    static var timeRemainingHelp: String {
        lang == .ukrainian
            ? "Оцінка часу роботи від батареї на основі усередненого споживання (див. Усереднення батареї в налаштуваннях)."
            : "Battery time estimate based on averaged power draw (see Battery Averaging in settings)."
    }

    // Time periods
    static func seconds(_ n: Int) -> String { lang == .ukrainian ? "\(n) секунд" : "\(n) seconds" }
    static func minutes(_ n: Int) -> String { lang == .ukrainian ? "\(n) хвилин" : "\(n) minutes" }
    static var oneMinute: String { lang == .ukrainian ? "1 хвилина" : "1 minute" }
    static var oneHour: String { lang == .ukrainian ? "1 година" : "1 hour" }
}
