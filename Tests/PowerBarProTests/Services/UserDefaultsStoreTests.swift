import XCTest
import Combine
@testable import PowerBarPro

final class UserDefaultsStoreTests: XCTestCase {

    var defaults: UserDefaults!
    var store: UserDefaultsStore!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        // Use a unique suite name to avoid polluting real UserDefaults
        defaults = UserDefaults(suiteName: "com.powerbar.tests.\(UUID().uuidString)")!
        store = UserDefaultsStore(defaults: defaults)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        let suiteName = defaults.volatileDomainNames.first
        cancellables = nil
        store = nil
        defaults.removePersistentDomain(forName: "com.powerbar.tests")
        defaults = nil
        super.tearDown()
    }

    // MARK: - Default Values

    func testDefaultDisplayMode() {
        XCTAssertEqual(store.displayMode, Constants.Defaults.displayMode)
    }

    func testDefaultBatteryDisplayMode() {
        XCTAssertEqual(store.batteryDisplayMode, Constants.Defaults.batteryDisplayMode)
    }

    func testDefaultUpdateInterval() {
        XCTAssertEqual(store.updateIntervalMs, Constants.Defaults.updateIntervalMs)
    }

    // MARK: - DisplayMode Persistence

    func testDisplayMode_persistsInstant() {
        store.displayMode = .instant

        // Create a new store from same defaults to verify persistence
        let store2 = UserDefaultsStore(defaults: defaults)
        XCTAssertEqual(store2.displayMode, .instant)
    }

    func testDisplayMode_persistsAverage() {
        store.displayMode = .average(seconds: 300)

        let store2 = UserDefaultsStore(defaults: defaults)
        XCTAssertEqual(store2.displayMode, .average(seconds: 300))
    }

    func testDisplayMode_persistsAllTime() {
        store.displayMode = .average(seconds: 0)

        let store2 = UserDefaultsStore(defaults: defaults)
        XCTAssertEqual(store2.displayMode, .average(seconds: 0))
    }

    // MARK: - Battery DisplayMode Persistence

    func testBatteryDisplayMode_persists() {
        store.batteryDisplayMode = .instant

        let store2 = UserDefaultsStore(defaults: defaults)
        XCTAssertEqual(store2.batteryDisplayMode, .instant)
    }

    func testBatteryDisplayMode_persistsAverage() {
        store.batteryDisplayMode = .average(seconds: 60)

        let store2 = UserDefaultsStore(defaults: defaults)
        XCTAssertEqual(store2.batteryDisplayMode, .average(seconds: 60))
    }

    // MARK: - UpdateInterval Persistence

    func testUpdateInterval_persists() {
        store.updateIntervalMs = 500

        let store2 = UserDefaultsStore(defaults: defaults)
        XCTAssertEqual(store2.updateIntervalMs, 500)
    }

    func testUpdateInterval_persistsAllValues() {
        for interval in Constants.Defaults.availableIntervals {
            store.updateIntervalMs = interval
            let store2 = UserDefaultsStore(defaults: defaults)
            XCTAssertEqual(store2.updateIntervalMs, interval,
                           "Failed to persist interval \(interval)")
        }
    }

    // MARK: - Publisher Reactivity

    func testDisplayModePublisher_emitsOnChange() {
        let exp = expectation(description: "mode changed")

        store.displayModePublisher
            .dropFirst() // skip current value
            .first()
            .sink { mode in
                XCTAssertEqual(mode, .average(seconds: 600))
                exp.fulfill()
            }
            .store(in: &cancellables)

        store.displayMode = .average(seconds: 600)

        wait(for: [exp], timeout: 1.0)
    }

    func testBatteryDisplayModePublisher_emitsOnChange() {
        let exp = expectation(description: "battery mode changed")

        store.batteryDisplayModePublisher
            .dropFirst()
            .first()
            .sink { mode in
                XCTAssertEqual(mode, .instant)
                exp.fulfill()
            }
            .store(in: &cancellables)

        store.batteryDisplayMode = .instant

        wait(for: [exp], timeout: 1.0)
    }

    func testUpdateIntervalPublisher_emitsOnChange() {
        let exp = expectation(description: "interval changed")

        store.updateIntervalMsPublisher
            .dropFirst()
            .first()
            .sink { interval in
                XCTAssertEqual(interval, 250)
                exp.fulfill()
            }
            .store(in: &cancellables)

        store.updateIntervalMs = 250

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Edge Cases

    func testMultipleRapidChanges_lastValueWins() {
        store.displayMode = .instant
        store.displayMode = .average(seconds: 10)
        store.displayMode = .average(seconds: 60)
        store.displayMode = .average(seconds: 3600)

        let store2 = UserDefaultsStore(defaults: defaults)
        XCTAssertEqual(store2.displayMode, .average(seconds: 3600))
    }

    func testCorruptedData_fallsBackToDefault() {
        // Write garbage data to the display mode key
        defaults.set(Data([0xFF, 0xFE]), forKey: "powerbar.displayMode")

        let store2 = UserDefaultsStore(defaults: defaults)
        XCTAssertEqual(store2.displayMode, Constants.Defaults.displayMode)
    }

    func testZeroInterval_fallsBackToDefault() {
        defaults.set(0, forKey: "powerbar.updateIntervalMs")

        let store2 = UserDefaultsStore(defaults: defaults)
        XCTAssertEqual(store2.updateIntervalMs, Constants.Defaults.updateIntervalMs)
    }
}
