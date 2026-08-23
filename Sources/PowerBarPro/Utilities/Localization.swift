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
