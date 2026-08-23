import XCTest
import SwiftUI
@testable import PowerBarPro

/// Offscreen render of the full popover — catches layout crashes and lets a
/// human (or agent) eyeball the PNG written to the temporary directory.
@MainActor
final class PopoverSnapshotTests: XCTestCase {

    func testPopoverRendersToImage() throws {
        let powerMonitor = MockPowerMonitor()
        let aggregator = PowerAggregator()
        let settings = MockSettingsStore()

        // Seed 10 minutes of plausible history for the chart
        let now = Date()
        for i in 0..<600 {
            let t = now.addingTimeInterval(Double(i - 600))
            let w = 12.0 + 8.0 * sin(Double(i) / 40.0) + Double(i % 7)
            aggregator.record(PowerReading(allPower: w * 0.6, sysPower: w, timestamp: t))
        }

        let powerVM = PowerDisplayViewModel(
            powerMonitor: powerMonitor, aggregator: aggregator, settings: settings
        )

        let batteryMonitor = MockBatteryMonitor()
        batteryMonitor.stubbedBatteryState = TestData.batteryOnBattery()
        batteryMonitor.stubbedRemainingTime = 4 * 3600 + 12 * 60
        let batteryVM = BatteryViewModel(
            batteryMonitor: batteryMonitor, aggregator: aggregator, settings: settings
        )

        let processVM = ProcessListViewModel(
            processMonitor: ProcessEnergyService(),
            terminator: ProcessTerminator(),
            attributionEngine: PowerAttributionEngine(),
            coalitionGrouper: CoalitionGrouper()
        )

        powerMonitor.emit(TestData.sampleMetrics())
        batteryVM.refresh(currentMetrics: TestData.sampleMetrics())

        // Let async publishers deliver
        let exp = expectation(description: "settle")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        let view = PowerBarPopoverView(
            powerVM: powerVM,
            batteryVM: batteryVM,
            processVM: processVM,
            agentSessionsVM: AgentSessionsViewModel(
                service: AgentSessionsService(runTool: { _, _ in "" })
            ),
            settingsModel: PopoverSettingsModel(settings: settings),
            onQuit: nil
        )

        // Render the content directly: ImageRenderer can't lay out the
        // NSScrollView-backed ScrollView wrapper offscreen
        let renderable = view.mainPage
            .padding(16)
            .frame(width: 320)
            .background(Color(.sRGB, red: 0.11, green: 0.106, blue: 0.122, opacity: 1))
        let renderer = ImageRenderer(content: renderable)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "popover failed to render offscreen")
        XCTAssertGreaterThan(image.size.width, 0)

        // Write PNG for visual inspection
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("powerbarpro_popover_snapshot.png")
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: url)
            print("SNAPSHOT_PATH: \(url.path)")
        }
    }
}
