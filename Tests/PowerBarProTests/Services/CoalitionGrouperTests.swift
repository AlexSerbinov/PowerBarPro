import XCTest
@testable import PowerBarPro

final class CoalitionGrouperTests: XCTestCase {

    // MARK: - Helpers

    /// Build a ProcessPowerInfo with sensible defaults.
    private func makeProcess(
        name: String,
        powerWatts: Double = 1.0,
        percentOfSystem: Double = 10.0,
        memoryBytes: UInt64 = 100_000_000,
        pids: [pid_t] = [1]
    ) -> ProcessPowerInfo {
        ProcessPowerInfo(
            id: name,
            name: name,
            powerWatts: powerWatts,
            percentOfSystem: percentOfSystem,
            memoryBytes: memoryBytes,
            pidCount: pids.count,
            pids: pids
        )
    }

    /// Create a CoalitionGrouper with a stubbed path resolver.
    private func makeGrouper(pathMap: [pid_t: String] = [:]) -> CoalitionGrouper {
        CoalitionGrouper(pathResolver: { pid in
            pathMap[pid]
        })
    }

    // MARK: - Empty Input

    func testEmptyInput_returnsEmptyOutput() {
        let grouper = makeGrouper()
        let result = grouper.group([], systemPowerW: 10.0)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - App Bundle Name Resolution

    func testResolveAppName_standardApplicationPath() {
        let grouper = makeGrouper(pathMap: [
            100: "/Applications/Telegram.app/Contents/MacOS/Telegram"
        ])

        let name = grouper.resolveAppName(pid: 100)
        XCTAssertEqual(name, "Telegram")
    }

    func testResolveAppName_chromeHelperPath() {
        let grouper = makeGrouper(pathMap: [
            200: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/123/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        ])

        let name = grouper.resolveAppName(pid: 200)
        // Should find the first .app in path which is "Google Chrome"
        XCTAssertEqual(name, "Google Chrome")
    }

    func testResolveAppName_systemUtilityPath() {
        let grouper = makeGrouper(pathMap: [
            300: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
        ])

        let name = grouper.resolveAppName(pid: 300)
        XCTAssertEqual(name, "Terminal")
    }

    func testResolveAppName_cliToolPath_returnsNil() {
        let grouper = makeGrouper(pathMap: [
            400: "/usr/bin/python3"
        ])

        let name = grouper.resolveAppName(pid: 400)
        XCTAssertNil(name)
    }

    func testResolveAppName_unknownPid_returnsNil() {
        let grouper = makeGrouper(pathMap: [:])
        let name = grouper.resolveAppName(pid: 999)
        XCTAssertNil(name)
    }

    func testResolveAppName_cachesResult() {
        var callCount = 0
        let grouper = CoalitionGrouper(pathResolver: { pid in
            callCount += 1
            return "/Applications/Safari.app/Contents/MacOS/Safari"
        })

        _ = grouper.resolveAppName(pid: 50)
        _ = grouper.resolveAppName(pid: 50)
        _ = grouper.resolveAppName(pid: 50)

        // Path resolver should only be called once due to caching
        XCTAssertEqual(callCount, 1)
    }

    // MARK: - extractAppBundleName

    func testExtractAppBundleName_standardPath() {
        let grouper = makeGrouper()
        let name = grouper.extractAppBundleName(
            from: "/Applications/Telegram.app/Contents/MacOS/Telegram"
        )
        XCTAssertEqual(name, "Telegram")
    }

    func testExtractAppBundleName_nestedAppPath() {
        let grouper = makeGrouper()
        let name = grouper.extractAppBundleName(
            from: "/Applications/Google Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"
        )
        // Should pick the first .app occurrence
        XCTAssertEqual(name, "Google Chrome")
    }

    func testExtractAppBundleName_noAppBundle_returnsNil() {
        let grouper = makeGrouper()
        let name = grouper.extractAppBundleName(from: "/usr/bin/python3")
        XCTAssertNil(name)
    }

    func testExtractAppBundleName_appAtEndOfPath() {
        let grouper = makeGrouper()
        let name = grouper.extractAppBundleName(from: "/Applications/Notes.app")
        XCTAssertEqual(name, "Notes")
    }

    func testExtractAppBundleName_spaceInName() {
        let grouper = makeGrouper()
        let name = grouper.extractAppBundleName(
            from: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"
        )
        XCTAssertEqual(name, "Visual Studio Code")
    }

    // MARK: - Helper Suffix Stripping

    func testStripHelperSuffixes_rendererSuffix() {
        let grouper = makeGrouper()
        let result = grouper.stripHelperSuffixes(from: "Google Chrome Helper (Renderer)")
        XCTAssertEqual(result, "Google Chrome")
    }

    func testStripHelperSuffixes_gpuSuffix() {
        let grouper = makeGrouper()
        let result = grouper.stripHelperSuffixes(from: "Google Chrome Helper (GPU)")
        XCTAssertEqual(result, "Google Chrome")
    }

    func testStripHelperSuffixes_pluginSuffix() {
        let grouper = makeGrouper()
        let result = grouper.stripHelperSuffixes(from: "Firefox Helper (Plugin)")
        XCTAssertEqual(result, "Firefox")
    }

    func testStripHelperSuffixes_helperOnly() {
        let grouper = makeGrouper()
        let result = grouper.stripHelperSuffixes(from: "Slack Helper")
        XCTAssertEqual(result, "Slack")
    }

    func testStripHelperSuffixes_workerSuffix() {
        let grouper = makeGrouper()
        let result = grouper.stripHelperSuffixes(from: "Safari Worker")
        XCTAssertEqual(result, "Safari")
    }

    func testStripHelperSuffixes_noSuffix_returnsOriginal() {
        let grouper = makeGrouper()
        let result = grouper.stripHelperSuffixes(from: "python3")
        XCTAssertEqual(result, "python3")
    }

    func testStripHelperSuffixes_utilitySuffix() {
        let grouper = makeGrouper()
        let result = grouper.stripHelperSuffixes(from: "Google Chrome Helper (Utility)")
        XCTAssertEqual(result, "Google Chrome")
    }

    // MARK: - Grouping: Multiple PIDs -> Single Coalition

    func testGroupMultiplePids_sameApp_singleCoalition() {
        let pathMap: [pid_t: String] = [
            101: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            102: "/Applications/Google Chrome.app/Contents/Helpers/Chrome Helper (Renderer).app/Contents/MacOS/Chrome Helper (Renderer)",
            103: "/Applications/Google Chrome.app/Contents/Helpers/Chrome Helper (GPU).app/Contents/MacOS/Chrome Helper (GPU)",
        ]
        let grouper = makeGrouper(pathMap: pathMap)

        let processes = [
            makeProcess(name: "Google Chrome", powerWatts: 2.0, memoryBytes: 500_000_000, pids: [101]),
            makeProcess(name: "Google Chrome Helper (Renderer)", powerWatts: 1.5, memoryBytes: 300_000_000, pids: [102]),
            makeProcess(name: "Google Chrome Helper (GPU)", powerWatts: 0.5, memoryBytes: 200_000_000, pids: [103]),
        ]

        let result = grouper.group(processes, systemPowerW: 20.0)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Google Chrome")
        XCTAssertEqual(result[0].totalPowerWatts, 4.0, accuracy: 0.001)
        XCTAssertEqual(result[0].totalMemoryBytes, 1_000_000_000)
        XCTAssertEqual(result[0].processCount, 3)
        XCTAssertEqual(Set(result[0].pids), Set([101, 102, 103]))
    }

    // MARK: - Grouping: Multiple Distinct Apps

    func testGroupMultipleApps_separateCoalitions() {
        let pathMap: [pid_t: String] = [
            10: "/Applications/Safari.app/Contents/MacOS/Safari",
            20: "/Applications/Telegram.app/Contents/MacOS/Telegram",
            30: "/usr/bin/python3",
        ]
        let grouper = makeGrouper(pathMap: pathMap)

        let processes = [
            makeProcess(name: "Safari", powerWatts: 3.0, pids: [10]),
            makeProcess(name: "Telegram", powerWatts: 1.0, pids: [20]),
            makeProcess(name: "python3", powerWatts: 0.5, pids: [30]),
        ]

        let result = grouper.group(processes, systemPowerW: 10.0)

        XCTAssertEqual(result.count, 3)
        // Sorted by power descending
        XCTAssertEqual(result[0].name, "Safari")
        XCTAssertEqual(result[1].name, "Telegram")
        XCTAssertEqual(result[2].name, "python3")
    }

    // MARK: - Percentage Calculation

    func testPercentageOfSystem_calculatedCorrectly() {
        let grouper = makeGrouper(pathMap: [
            1: "/Applications/Xcode.app/Contents/MacOS/Xcode"
        ])

        let processes = [
            makeProcess(name: "Xcode", powerWatts: 5.0, pids: [1]),
        ]

        let result = grouper.group(processes, systemPowerW: 20.0)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].percentOfSystem, 25.0, accuracy: 0.001) // 5/20 * 100
    }

    func testPercentageOfSystem_cappedAt100() {
        let grouper = makeGrouper(pathMap: [
            1: "/Applications/Xcode.app/Contents/MacOS/Xcode"
        ])

        let processes = [
            makeProcess(name: "Xcode", powerWatts: 25.0, pids: [1]),
        ]

        // System power less than process power — percentage should cap at 100
        let result = grouper.group(processes, systemPowerW: 10.0)
        XCTAssertEqual(result[0].percentOfSystem, 100.0)
    }

    func testPercentageOfSystem_zeroSystemPower_usesMinimum() {
        let grouper = makeGrouper(pathMap: [:])

        let processes = [
            makeProcess(name: "test", powerWatts: 1.0, pids: [1]),
        ]

        // Should not crash or produce infinity with 0 system power
        let result = grouper.group(processes, systemPowerW: 0.0)
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].percentOfSystem.isNaN)
        XCTAssertFalse(result[0].percentOfSystem.isInfinite)
    }

    // MARK: - Sorting

    func testSortedByPowerDescending() {
        let grouper = makeGrouper(pathMap: [
            1: "/Applications/Low.app/Contents/MacOS/Low",
            2: "/Applications/High.app/Contents/MacOS/High",
            3: "/Applications/Mid.app/Contents/MacOS/Mid",
        ])

        let processes = [
            makeProcess(name: "Low", powerWatts: 0.5, pids: [1]),
            makeProcess(name: "High", powerWatts: 5.0, pids: [2]),
            makeProcess(name: "Mid", powerWatts: 2.0, pids: [3]),
        ]

        let result = grouper.group(processes, systemPowerW: 20.0)

        XCTAssertEqual(result[0].name, "High")
        XCTAssertEqual(result[1].name, "Mid")
        XCTAssertEqual(result[2].name, "Low")
    }

    // MARK: - Fallback: Name-Based Grouping (no path available)

    func testFallbackGrouping_stripsSuffixes_whenNoPath() {
        // No paths available — grouper falls back to suffix stripping
        let grouper = makeGrouper(pathMap: [:])

        let processes = [
            makeProcess(name: "Google Chrome Helper (Renderer)", powerWatts: 1.0, pids: [101]),
            makeProcess(name: "Google Chrome Helper (GPU)", powerWatts: 0.5, pids: [102]),
            makeProcess(name: "Google Chrome", powerWatts: 2.0, pids: [100]),
        ]

        let result = grouper.group(processes, systemPowerW: 20.0)

        // All three should be grouped under "Google Chrome"
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Google Chrome")
        XCTAssertEqual(result[0].totalPowerWatts, 3.5, accuracy: 0.001)
        XCTAssertEqual(result[0].processCount, 3)
    }

    // MARK: - Mixed: Some With Paths, Some Without

    func testMixedResolution_pathAndFallback() {
        let pathMap: [pid_t: String] = [
            10: "/Applications/Safari.app/Contents/MacOS/Safari",
            // PID 20 has no path — will use name fallback
        ]
        let grouper = makeGrouper(pathMap: pathMap)

        let processes = [
            makeProcess(name: "Safari", powerWatts: 2.0, pids: [10]),
            makeProcess(name: "python3", powerWatts: 0.3, pids: [20]),
        ]

        let result = grouper.group(processes, systemPowerW: 10.0)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Safari")
        XCTAssertEqual(result[1].name, "python3")
    }

    // MARK: - Memory Aggregation

    func testMemoryAggregation_sumsAcrossProcesses() {
        let pathMap: [pid_t: String] = [
            1: "/Applications/Slack.app/Contents/MacOS/Slack",
            2: "/Applications/Slack.app/Contents/Helpers/Slack Helper.app/Contents/MacOS/Slack Helper",
        ]
        let grouper = makeGrouper(pathMap: pathMap)

        let processes = [
            makeProcess(name: "Slack", powerWatts: 1.0, memoryBytes: 200_000_000, pids: [1]),
            makeProcess(name: "Slack Helper", powerWatts: 0.5, memoryBytes: 150_000_000, pids: [2]),
        ]

        let result = grouper.group(processes, systemPowerW: 10.0)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].totalMemoryBytes, 350_000_000)
    }

    // MARK: - PID Aggregation

    func testPidAggregation_collectsAllPids() {
        let pathMap: [pid_t: String] = [
            10: "/Applications/Firefox.app/Contents/MacOS/firefox",
            11: "/Applications/Firefox.app/Contents/MacOS/firefox",
            12: "/Applications/Firefox.app/Contents/MacOS/firefox",
        ]
        let grouper = makeGrouper(pathMap: pathMap)

        let processes = [
            // ProcessPowerInfo already groups by name, but may have multiple PIDs
            makeProcess(name: "firefox", powerWatts: 2.0, pids: [10, 11]),
            makeProcess(name: "firefox web", powerWatts: 1.0, pids: [12]),
        ]

        let result = grouper.group(processes, systemPowerW: 10.0)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(Set(result[0].pids), Set([10, 11, 12]))
    }

    // MARK: - Cache Clearing

    func testClearCache_resolvesAgain() {
        var callCount = 0
        let grouper = CoalitionGrouper(pathResolver: { _ in
            callCount += 1
            return "/Applications/Safari.app/Contents/MacOS/Safari"
        })

        _ = grouper.resolveAppName(pid: 1)
        XCTAssertEqual(callCount, 1)

        _ = grouper.resolveAppName(pid: 1)
        XCTAssertEqual(callCount, 1) // cached

        grouper.clearCache()

        _ = grouper.resolveAppName(pid: 1)
        XCTAssertEqual(callCount, 2) // resolved again after cache clear
    }

    // MARK: - Single Process

    func testSingleProcess_returnsOneCoalition() {
        let grouper = makeGrouper(pathMap: [
            42: "/Applications/Notes.app/Contents/MacOS/Notes"
        ])

        let processes = [
            makeProcess(name: "Notes", powerWatts: 0.1, memoryBytes: 50_000_000, pids: [42]),
        ]

        let result = grouper.group(processes, systemPowerW: 10.0)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "Notes")
        XCTAssertEqual(result[0].name, "Notes")
        XCTAssertEqual(result[0].totalPowerWatts, 0.1, accuracy: 0.001)
        XCTAssertEqual(result[0].percentOfSystem, 1.0, accuracy: 0.001)
        XCTAssertEqual(result[0].totalMemoryBytes, 50_000_000)
        XCTAssertEqual(result[0].processCount, 1)
        XCTAssertEqual(result[0].pids, [42])
    }

    // MARK: - Equatable conformance

    func testCoalitionInfoEquatable() {
        let a = CoalitionInfo(
            id: "Safari", name: "Safari", pids: [1, 2],
            totalPowerWatts: 3.0, percentOfSystem: 15.0,
            totalMemoryBytes: 500_000_000, processCount: 2
        )
        let b = CoalitionInfo(
            id: "Safari", name: "Safari", pids: [1, 2],
            totalPowerWatts: 3.0, percentOfSystem: 15.0,
            totalMemoryBytes: 500_000_000, processCount: 2
        )
        XCTAssertEqual(a, b)
    }
}
