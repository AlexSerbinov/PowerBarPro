import SwiftUI

/// Reports the popover content's natural height up to the manager,
/// which resizes the NSPopover to fit (capped to the screen).
struct PopoverContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Main popover view — a compact, glanceable menu bar tool.
///
/// Layout follows menu-bar-utility canons (HIG / iStat-class apps):
/// everything important in one screen without scrolling, details behind
/// progressive disclosure, settings on a separate page behind the gear.
struct PowerBarPopoverView: View {
    @ObservedObject var powerVM: PowerDisplayViewModel
    @ObservedObject var batteryVM: BatteryViewModel
    @ObservedObject var processVM: ProcessListViewModel
    var agentSessionsVM: AgentSessionsViewModel?
    var fanControlVM: FanControlViewModel?
    var settingsModel: PopoverSettingsModel?
    var onQuit: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    private enum Page { case main, settings }
    @State private var page: Page = .main

    var body: some View {
        // ScrollView is a safety net for expanded sections on small screens;
        // the default state fits without scrolling.
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                if page == .settings, let model = settingsModel {
                    SettingsPageView(model: model, onQuit: onQuit) {
                        withAnimation(.easeInOut(duration: 0.15)) { page = .main }
                    }
                } else {
                    mainPage
                }
            }
            .padding(Spacing.md)
            .frame(width: 320)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: PopoverContentHeightKey.self, value: geo.size.height)
                }
            )
        }
        .onPreferenceChange(PopoverContentHeightKey.self) { onHeightChange?($0) }
        .background(
            ZStack {
                Color.PB.bg
                Color.white.opacity(0.015)
            }
        )
    }

    var mainPage: some View {
        VStack(spacing: 0) {
            // 1. Glanceable header: total watts + battery chip
            HeaderRowView(metrics: powerVM.currentMetrics, batteryVM: batteryVM)
                .padding(.bottom, Spacing.sm)

            // 2. Component strip: CPU / GPU / PKG / RAM / DSP in one row
            MetricStripView(metrics: powerVM.currentMetrics)
                .padding(.bottom, Spacing.sm)

            SectionSeparator()

            // 4. History chart with period picker
            SparklineChartView(powerVM: powerVM)
                .padding(.vertical, Spacing.sm)

            SectionSeparator()

            // 5. Progressive disclosure: fan control, details, processes, sessions
            VStack(spacing: Spacing.sm) {
                if let fanVM = fanControlVM, fanVM.isAvailable {
                    FanControlSectionView(vm: fanVM)
                }
                DetailsSectionView(metrics: powerVM.currentMetrics)
                ProcessListSectionView(processVM: processVM)
                if let sessionsVM = agentSessionsVM {
                    AgentSessionsSectionView(vm: sessionsVM)
                }
            }
            .padding(.vertical, Spacing.sm)

            SectionSeparator()

            // 6. Footer: session energy + gear + quit
            FooterRowView(
                sessionSummary: powerVM.sessionSummary,
                onSettings: { withAnimation(.easeInOut(duration: 0.15)) { page = .settings } },
                onQuit: onQuit
            )
            .padding(.top, Spacing.sm)
        }
    }
}

// MARK: - Header (total power + battery chip)

struct HeaderRowView: View {
    let metrics: SystemMetrics?
    @ObservedObject var batteryVM: BatteryViewModel

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(heroValue)
                        .font(.system(size: 26, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(Color.PB.accent)
                    Text("W")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color.PB.textMuted)
                }
                Text("TOTAL POWER")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(Color.PB.textMuted)
            }

            Spacer()

            if batteryVM.isVisible {
                BatteryChipView(batteryVM: batteryVM)
            }
        }
    }

    private var heroValue: String {
        guard let m = metrics else { return "--.-" }
        return String(format: "%.1f", m.sysPower)
    }
}

struct BatteryChipView: View {
    @ObservedObject var batteryVM: BatteryViewModel

    var body: some View {
        HStack(spacing: Spacing.sm) {
            BatteryIconView(percent: batteryVM.percent / 100, isCharging: batteryVM.isCharging)

            // Bolt marks AC power; the estimate stays visible either way
            // ("how long would it last at this draw")
            if !batteryVM.isOnBattery {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.PB.accent)
            }

            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "%.0f%%", batteryVM.percent))
                    .font(.system(size: 12, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(percentColor)

                if !batteryVM.timeRemainingText.isEmpty {
                    Text(batteryVM.timeRemainingText)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color.PB.textMuted)
                } else {
                    Text(statusText)
                        .font(.system(size: 9))
                        .foregroundColor(Color.PB.textMuted)
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: CornerRadius.md).fill(Color.PB.surface))
        .help(batteryHelp)
    }

    private var statusText: String {
        if batteryVM.isCharging { return "Charging" }
        if batteryVM.isOnBattery { return "On Battery" }
        return "Plugged In"
    }

    private var percentColor: Color {
        if batteryVM.percent < 20 { return Color.PB.error }
        if batteryVM.isCharging { return Color.PB.success }
        return Color.PB.textPrimary
    }

    private var batteryHelp: String {
        var parts = [statusText]
        if !batteryVM.timeRemainingText.isEmpty {
            parts.append("\(batteryVM.timeRemainingText) \(L.remaining)")
        }
        parts.append(L.timeRemainingHelp)
        return parts.joined(separator: "\n")
    }
}

// MARK: - Metric Strip (CPU / GPU / PKG / RAM)

struct MetricStripView: View {
    let metrics: SystemMetrics?

    var body: some View {
        HStack(spacing: 1) {
            cell("CPU", value: metrics?.cpuPower, help: cpuHelp, accent: true)
            divider
            cell("GPU", value: metrics?.gpuPower, help: gpuHelp, accent: true)
            divider
            cell("PKG", value: metrics?.allPower, help: pkgHelp)
            divider
            cell("RAM", value: metrics?.ramPower, help: ramHelp)
            divider
            cell("DSP", value: displayW, help: dspHelp)
        }
        .padding(.vertical, Spacing.sm)
        .background(RoundedRectangle(cornerRadius: CornerRadius.md).fill(Color.PB.surface))
        .overlay(RoundedRectangle(cornerRadius: CornerRadius.md).stroke(Color.PB.separator, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.PB.separator)
            .frame(width: 1, height: 22)
    }

    private func cell(_ name: String, value: Double?, help: String, accent: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(name)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(Color.PB.textMuted)
            Text(value.map { String(format: "%.1fW", $0) } ?? "--.-")
                .font(.system(size: 13, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(accent ? Color.PB.accent : Color.PB.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .help(help)
    }

    private var cpuHelp: String {
        guard let m = metrics else { return "CPU" }
        return String(format: "CPU %.2fW · Fabric %.2fW", m.cpuPower, m.soc.fabricW)
    }
    private var gpuHelp: String {
        guard let m = metrics else { return "GPU" }
        let cores = m.gpuCores.map { " · \($0) cores" } ?? ""
        return String(format: "GPU %.2fW%@", m.gpuPower, cores)
    }
    private var pkgHelp: String {
        guard let m = metrics else { return "Package" }
        return String(format: "Package %.2fW · ANE %.3fW", m.allPower, m.anePower)
    }
    private var ramHelp: String {
        guard let m = metrics else { return "DRAM" }
        let size = m.dramGb.map { " · \($0) GB unified" } ?? ""
        return String(format: "DRAM %.2fW%@", m.ramPower, size)
    }

    /// Display draw: the higher of the backlight sensor and the model estimate.
    private var displayW: Double? {
        guard let m = metrics else { return nil }
        let value = max(m.backlightPowerW, m.display?.estimatedPowerW ?? 0)
        return value > 0 ? value : nil
    }

    private var dspHelp: String {
        guard let m = metrics, let w = displayW else { return "Display" }
        let brightness = m.display.map { String(format: " · %.0f%% %@", $0.brightnessPct, L.brightness) } ?? ""
        return String(format: "%@ %.2fW%@", L.display, w, brightness)
    }
}

// MARK: - Footer (session energy + gear + quit)

struct FooterRowView: View {
    let sessionSummary: String
    var onSettings: () -> Void
    var onQuit: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if !sessionSummary.isEmpty {
                Text(sessionSummary)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color.PB.textMuted)
                    .lineLimit(1)
                    .help(L.sessionEnergyHelp)
            }

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Color.PB.textMuted)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button(action: { onQuit?() }) {
                Image(systemName: "power")
                    .font(.system(size: 14))
                    .foregroundColor(Color.PB.textMuted)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L.quit)
        }
    }
}

// MARK: - Settings Page

struct SettingsPageView: View {
    @ObservedObject var model: PopoverSettingsModel
    var onQuit: (() -> Void)?
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("SETTINGS")
                        .font(Font.PB.sectionTitle)
                        .tracking(1.5)
                }
                .foregroundColor(Color.PB.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, Spacing.sm)

            SettingsFooterView(model: model, onQuit: onQuit)
        }
    }
}

// MARK: - Settings Footer

struct SettingsFooterView: View {
    @ObservedObject var model: PopoverSettingsModel
    @StateObject private var loginItem = LoginItemService()
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // 1. Power Averaging Period
            SettingPickerRow(
                label: L.averagingPeriod,
                icon: "chart.bar",
                help: L.averagingPeriodHelp,
                value: $model.displayModeSeconds,
                options: [
                    (0, L.instant), (3, "3s"), (10, "10s"), (30, "30s"),
                    (60, "1m"), (300, "5m"), (3600, "1h")
                ]
            )

            // 2. Battery Averaging (drives the time-remaining estimate)
            SettingPickerRow(
                label: L.batteryAveraging,
                icon: "battery.75",
                help: L.batteryAveragingHelp,
                value: $model.batteryModeSeconds,
                options: [
                    (60, "1m"), (300, "5m"), (600, "10m"), (1800, "30m"), (3600, "1h")
                ]
            )

            // 3. Process Averaging
            SettingPickerRow(
                label: L.processAveraging,
                icon: "cpu",
                help: L.processAveragingHelp,
                value: $model.processAveragingSeconds,
                options: [
                    (0, "Raw"), (5, "5s"), (10, "10s"), (30, "30s"), (60, "1m"), (300, "5m")
                ]
            )

            // 4. Refresh Rate
            SettingPickerRow(
                label: L.refreshRate,
                icon: "arrow.clockwise",
                help: L.refreshRateHelp,
                value: $model.updateIntervalMs,
                options: [
                    (250, "250ms"), (500, "500ms"), (1000, "1s"), (2500, "2.5s")
                ]
            )

            // 5. Power-hog alerts: toggle + threshold
            SettingToggleRow(
                label: L.powerAlerts,
                icon: "bell.badge",
                help: L.powerAlertsHelp,
                isOn: $model.alertsEnabled
            )

            if model.alertsEnabled {
                SettingPickerRow(
                    label: L.alertThreshold,
                    icon: "bolt.trianglebadge.exclamationmark",
                    help: L.alertThresholdHelp,
                    value: $model.alertThresholdW,
                    options: [
                        (10, "10W"), (15, "15W"), (25, "25W"), (40, "40W"), (60, "60W")
                    ]
                )
            }

            // 6. Launch at login
            SettingToggleRow(
                label: L.launchAtLogin,
                icon: "arrow.right.circle",
                help: L.launchAtLoginHelp,
                isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                )
            )

            SectionSeparator()

            // Quit
            HStack {
                Spacer()
                Button(action: { onQuit?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.system(size: 10))
                        Text(L.quit)
                            .font(Font.PB.caption)
                    }
                    .foregroundColor(Color.PB.textMuted)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: CornerRadius.sm).fill(Color.PB.surface))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)
        }
    }
}

struct SettingPickerRow: View {
    let label: String
    let icon: String
    var help: String? = nil
    @Binding var value: Int
    let options: [(Int, String)]

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Color.PB.textMuted)
                .frame(width: 14)

            Text(label)
                .font(Font.PB.caption)
                .foregroundColor(Color.PB.textMuted)
                .lineLimit(1)

            if let help {
                InfoHintView(text: help)
            }

            Spacer()

            Menu {
                ForEach(options, id: \.0) { opt in
                    Button(opt.1) { value = opt.0 }
                }
            } label: {
                Text(options.first(where: { $0.0 == value })?.1 ?? customValueLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.PB.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: CornerRadius.sm).fill(Color.PB.surface))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 60)
        }
        .padding(.horizontal, Spacing.md)
        .help(help ?? label)
    }

    /// A value set outside the preset list (e.g. via right-click menu) —
    /// show it honestly instead of "---".
    private var customValueLabel: String {
        value >= 60 && value % 60 == 0 ? "\(value / 60)m" : "\(value)"
    }
}

/// Small ⓘ that makes a row's tooltip discoverable — hover shows the
/// explanation immediately via the same system help balloon.
struct InfoHintView: View {
    let text: String

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 9))
            .foregroundColor(Color.PB.textMuted.opacity(0.7))
            .help(text)
    }
}

struct SettingToggleRow: View {
    let label: String
    let icon: String
    var help: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Color.PB.textMuted)
                .frame(width: 14)

            Text(label)
                .font(Font.PB.caption)
                .foregroundColor(Color.PB.textMuted)
                .lineLimit(1)

            if let help {
                InfoHintView(text: help)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(Color.PB.accent)
        }
        .padding(.horizontal, Spacing.md)
        .help(help ?? label)
    }
}

struct SettingRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(Font.PB.caption)
                .foregroundColor(Color.PB.textMuted)
                .frame(width: 65, alignment: .leading)
            content
        }
        .padding(.horizontal, Spacing.md)
    }
}

// MARK: - Separator

struct SectionSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.PB.separator)
            .frame(height: 1)
            .padding(.horizontal, Spacing.md)
    }
}

// (Hero and 2x2 metric cards replaced by HeaderRowView + MetricStripView
//  in the compact redesign — see design-v1 tag for the previous layout.)

// MARK: - Collapsible Section Helper

struct CollapsibleSection<Content: View>: View {
    let title: String
    let badge: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.PB.textMuted)
                        .frame(width: 10)

                    Text(title)
                        .font(Font.PB.sectionTitle)
                        .tracking(1.5)
                        .foregroundColor(Color.PB.textMuted)

                    Spacer()

                    Text(badge)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color.PB.accent)
                }
                .padding(.horizontal, Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Details Section (system load + memory + temperatures)

struct DetailsSectionView: View {
    let metrics: SystemMetrics?
    @State private var isExpanded = false

    /// Sensor categories that add noise, not signal — hidden per feedback.
    private static let hiddenTempCategories: Set<String> = ["Memory", "ANE", "Trackpad"]

    /// Hottest sensor per category (plus the battery pack), hottest first.
    private var groupedTemps: [(category: String, maxC: Double)] {
        var byCategory: [String: Double] = [:]
        for t in metrics?.temperatures ?? [] {
            let cat = t.category ?? "Other"
            guard !Self.hiddenTempCategories.contains(cat) else { continue }
            byCategory[cat] = max(byCategory[cat] ?? 0, t.valueCelsius)
        }
        if let batteryC = metrics?.battery?.temperatureC {
            byCategory["Battery"] = max(byCategory["Battery"] ?? 0, batteryC)
        }
        return byCategory.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    /// macpow reports per-core usage already in percent (0-100).
    private var cpuLoadPct: Double? {
        guard let usage = metrics?.cpuUsagePct, !usage.isEmpty else { return nil }
        return usage.reduce(0, +) / Double(usage.count)
    }

    /// GPU utilization 0-100 — the higher of device/renderer counters.
    private var gpuLoadPct: Int? {
        let device = metrics?.soc.gpuUtilDevice
        let renderer = metrics?.soc.gpuUtilRenderer
        switch (device, renderer) {
        case let (d?, r?): return max(d, r)
        case let (d?, nil): return d
        case let (nil, r?): return r
        default: return nil
        }
    }

    var body: some View {
        if metrics != nil {
            CollapsibleSection(
                title: L.details,
                badge: badgeText,
                isExpanded: $isExpanded
            ) {
                VStack(spacing: 2) {
                    loadRows
                    systemStatsRows

                    ForEach(groupedTemps.prefix(7), id: \.category) { item in
                        SensorRowView(
                            icon: item.category == "Battery" ? "battery.75" : "thermometer.medium",
                            name: item.category,
                            value: String(format: "%.0f°C", item.maxC),
                            valueColor: tempColor(item.maxC)
                        )
                        .help(tempHelp(item.category))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var loadRows: some View {
        if let cpu = cpuLoadPct {
            SensorRowView(
                icon: "gauge.with.needle",
                name: "CPU Load",
                value: String(format: "%.0f%%", min(cpu, 100)),
                valueColor: cpu >= 80 ? Color.PB.error : Color.PB.textPrimary
            )
            .help(L.cpuLoadHelp)
        }

        if let gpu = gpuLoadPct {
            SensorRowView(
                icon: "cpu.fill",
                name: "GPU Load",
                value: "\(min(gpu, 100))%",
                valueColor: gpu >= 80 ? Color.PB.error : Color.PB.textPrimary
            )
            .help(L.gpuLoadHelp)
        }
    }

    /// Memory / swap / disk rows — syscall-backed, computed per render only
    /// while the section is expanded.
    @ViewBuilder
    private var systemStatsRows: some View {
        let stats = SystemStatsProvider.current()

        if let used = metrics?.memUsedGb, let total = metrics?.dramGb {
            let pct = used / Double(total) * 100
            SensorRowView(
                icon: "memorychip",
                name: "RAM",
                value: String(format: "%.1f / %d GB", used, total),
                valueColor: pct >= 90 ? Color.PB.error : Color.PB.textPrimary
            )
            .help(L.ramHelp)
        }

        if stats.swapTotalBytes > 0 {
            SensorRowView(
                icon: "arrow.left.arrow.right",
                name: "Swap",
                value: String(
                    format: "%.1f / %.0f GB",
                    Double(stats.swapUsedBytes) / 1_073_741_824,
                    Double(stats.swapTotalBytes) / 1_073_741_824
                ),
                valueColor: Color.PB.textPrimary
            )
            .help(L.swapHelp)
        }

        if stats.diskTotalBytes > 0 {
            SensorRowView(
                icon: "internaldrive",
                name: "Disk",
                value: String(
                    format: "%.0f GB free",
                    Double(stats.diskFreeBytes) / 1_000_000_000
                ),
                valueColor: Color.PB.textPrimary
            )
            .help(String(
                format: "%.0f of %.0f GB used",
                Double(stats.diskTotalBytes - stats.diskFreeBytes) / 1_000_000_000,
                Double(stats.diskTotalBytes) / 1_000_000_000
            ))
        }
    }

    private var badgeText: String {
        var parts: [String] = []
        if let cpu = cpuLoadPct { parts.append(String(format: "%.0f%%", min(cpu, 100))) }
        if let hottest = groupedTemps.first {
            parts.append(String(format: "%.0f°C", hottest.maxC))
        }
        return parts.joined(separator: " · ")
    }

    private func tempColor(_ celsius: Double) -> Color {
        if celsius >= 90 { return Color.PB.error }
        if celsius >= 75 { return Color.PB.accent }
        return Color.PB.textPrimary
    }

    private func tempHelp(_ category: String) -> String {
        category == "Battery" ? L.batteryTempHelp : L.sensorTempHelp(category)
    }
}


struct SensorRowView: View {
    let icon: String
    let name: String
    let value: String
    let valueColor: Color

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(Color.PB.textMuted)
                .frame(width: 14)

            Text(name)
                .font(Font.PB.caption)
                .foregroundColor(Color.PB.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(valueColor)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 2)
    }
}

// MARK: - Battery Icon

struct BatteryIconView: View {
    let percent: Double
    let isCharging: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.PB.textMuted, lineWidth: 1.5)
                .frame(width: 28, height: 14)

            RoundedRectangle(cornerRadius: 1)
                .fill(fillColor)
                .frame(width: max(2, 24 * percent), height: 10)
                .padding(.leading, 2)

            RoundedRectangle(cornerRadius: 1)
                .fill(Color.PB.textMuted)
                .frame(width: 2.5, height: 6)
                .offset(x: 29)
        }
        .frame(width: 32, height: 16)
    }

    private var fillColor: Color {
        if percent < 0.2 { return Color.PB.error }
        return Color.PB.success
    }
}

// MARK: - Process List

struct ProcessListSectionView: View {
    @ObservedObject var processVM: ProcessListViewModel
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Clickable header — toggles process list
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.PB.textMuted)
                        .frame(width: 10)

                    Text("ACTIVE PROCESSES")
                        .font(Font.PB.sectionTitle)
                        .tracking(1.5)
                        .foregroundColor(Color.PB.textMuted)

                    Spacer()

                    Text("\(processVM.attributedProcesses.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color.PB.accent)
                }
                .padding(.horizontal, Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable process list — scrolls internally so the popover
            // keeps its height while the full list stays reachable.
            // Lazy rows: icons/LLM descriptions load only for visible ones.
            if isExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(processVM.attributedProcesses.prefix(60)) { proc in
                            ProcessRowView(process: proc, onKill: {
                                _ = processVM.terminateProcess(proc)
                            })
                        }
                    }
                }
                .frame(maxHeight: 300)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct ProcessRowView: View {
    let process: AttributedPower
    var onKill: (() -> Void)?
    var descriptionService: ProcessDescriptionService?
    var language: String = "en"

    @State private var isHovered = false
    @State private var tooltip: String = ""

    /// Known system daemon suffixes and names
    private var isSystemProcess: Bool {
        let name = process.name.lowercased()
        // Check LLM cache first
        if let desc = descriptionService?.getCached(processName: process.name, language: language) {
            return desc.isSystem
        }
        // Heuristic fallback: daemons end with 'd', known system names
        let systemNames: Set = ["kernel_task", "windowserver", "loginwindow", "dock",
            "finder", "spotlight", "corespotlightd", "mds", "mds_stores",
            "trustd", "securityd", "opendirectoryd", "cfprefsd", "distnoted",
            "powerd", "wifid", "bluetoothd", "airportd", "contactsd", "suggestd",
            "controlcenter", "systemuiserver", "notificationcenterui"]
        return systemNames.contains(name) || (name.hasSuffix("d") && name.count <= 20 && !name.contains(" "))
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // App icon
            if let icon = MenuBuilder.appIcon(for: process.pids.first ?? 0) {
                Image(nsImage: iconResized(icon))
                    .frame(width: 16, height: 16)
            } else {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Color.PB.surfaceHover)
                    .frame(width: 16, height: 16)
            }

            Text(process.name)
                .font(Font.PB.body)
                .foregroundColor(isSystemProcess ? Color.PB.error.opacity(0.7) : Color.PB.textPrimary)
                .lineLimit(1)

            if isSystemProcess {
                Text("SYS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.PB.error.opacity(0.6))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color.PB.error.opacity(0.1)))
            }

            Spacer()

            Text(Formatters.processWatts(process.totalWatts))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color.PB.accent)

            Text(String(format: "%.0f%%", process.percentOfSystem))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.PB.textMuted)
                .frame(width: 30, alignment: .trailing)

            // Kill at the far right — same pattern as agent sessions:
            // always in layout, fades in on hover (no row shift)
            Button(action: { onKill?() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color.PB.error.opacity(0.85))
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered && onKill != nil ? 1 : 0)
            .help("\(L.terminate) \(process.name)")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Spacing.md)
        .background(RoundedRectangle(cornerRadius: CornerRadius.sm).fill(isHovered ? Color.PB.surfaceHover : Color.clear))
        .help(tooltip.isEmpty ? process.name : tooltip)
        .reliableHover { hovering in
            if isHovered != hovering { isHovered = hovering }
        }
        .onAppear {
            descriptionService?.getDescription(processName: process.name, language: language) { desc in
                tooltip = desc.tooltip(processName: process.name)
            }
        }
    }

    private func iconResized(_ icon: NSImage) -> NSImage {
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

// MARK: - Fan Control (MacFans daemon)

/// Fan mode switcher in MacFans style: Automatic / Battery Curve rows +
/// fixed-speed chips. Uses the info-blue accent so fan controls read as a
/// distinct subsystem from the amber power readouts.
struct FanControlSectionView: View {
    @ObservedObject var vm: FanControlViewModel
    @State private var isExpanded = false

    private static let fixedPresets = [0, 30, 70, 100]
    private let fanColor = Color.PB.info

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                if isExpanded { vm.refresh() }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.PB.textMuted)
                        .frame(width: 10)

                    Text(L.fanControl)
                        .font(Font.PB.sectionTitle)
                        .tracking(1.5)
                        .foregroundColor(Color.PB.textMuted)

                    Spacer()

                    Text(badgeText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(badgeColor)
                        .lineLimit(1)
                }
                .padding(.horizontal, Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // One chip row: two modes on the left, fixed speeds after.
                    // Each chip lights up in its own mode color when active.
                    HStack(spacing: Spacing.xs) {
                        chip(
                            label: "Auto",
                            color: Color(nsColor: MacFans.modeTint(mode: .auto, pct: 0)),
                            isActive: vm.reply?.mode == .auto,
                            help: L.fanAutoHelp
                        ) { vm.setAuto() }

                        chip(
                            label: "Curve",
                            color: Color(nsColor: MacFans.modeTint(mode: .curve, pct: 0)),
                            isActive: vm.reply?.mode == .curve,
                            help: L.fanCurveHelp
                        ) { vm.setCurve() }

                        ForEach(Self.fixedPresets, id: \.self) { pct in
                            chip(
                                label: "\(pct)",
                                color: Color(nsColor: MacFans.modeTint(mode: .manual, pct: pct)),
                                isActive: isFixedActive(pct),
                                help: L.fanFixedHelp
                            ) { vm.setManual(pct) }
                        }
                    }
                    .padding(.horizontal, Spacing.md)

                    // Battery curve bounds, editable in place — standard
                    // settings-picker styling (amber), not the mode color
                    if let curve = vm.reply?.curve {
                        CurveEditorRow(curve: curve, accent: Color.PB.accent) { vm.setCurve($0) }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Badge takes the active mode's color; neutral info-blue before the
    /// first status arrives.
    private var badgeColor: Color {
        guard let reply = vm.reply else { return fanColor }
        return Color(nsColor: MacFans.modeTint(mode: reply.mode, pct: reply.pct))
    }

    private var badgeText: String {
        guard let reply = vm.reply else {
            return vm.isBusy ? "…" : "—"
        }
        return "\(reply.modeTitle) · \(reply.rpmText) rpm"
    }

    private func isFixedActive(_ pct: Int) -> Bool {
        vm.reply?.mode == .manual && vm.reply?.pct == pct
    }

    private func chip(
        label: String,
        color: Color,
        isActive: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .fontWeight(isActive ? .bold : .regular)
                .foregroundColor(isActive ? Color.PB.bg : Color.PB.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(isActive ? color : Color.PB.surface)
                )
                .overlay(
                    // Inactive chips stay neutral — per-chip colored borders
                    // read as visual noise; only the active mode lights up.
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(isActive ? Color.clear : Color.PB.separator, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Inline battery-curve editor: low temp → low %, high temp → high %.
/// Every change applies live through the daemon (and switches to curve mode
/// on the daemon side only if it is already the active mode — setCurve
/// itself just stores the bounds).
struct CurveEditorRow: View {
    let curve: MacFans.Curve
    let accent: Color
    let onChange: (MacFans.Curve) -> Void

    private let temps = Array(30...45)
    private let pcts = Array(stride(from: 0, through: 100, by: 10))

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text("CURVE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundColor(Color.PB.textMuted)

            picker(Int(curve.lowTemp), options: temps, suffix: "°") { newTemp in
                var c = curve; c.lowTemp = Double(newTemp); onChange(c)
            }
            picker(curve.lowPct, options: pcts, suffix: "%") { newPct in
                var c = curve; c.lowPct = newPct; onChange(c)
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(Color.PB.textMuted)

            picker(Int(curve.highTemp), options: temps, suffix: "°") { newTemp in
                var c = curve; c.highTemp = Double(newTemp); onChange(c)
            }
            picker(curve.highPct, options: pcts, suffix: "%") { newPct in
                var c = curve; c.highPct = newPct; onChange(c)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .help(L.fanCurveHelp)
    }

    private func picker(
        _ value: Int,
        options: [Int],
        suffix: String,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button("\(option)\(suffix)") { onSelect(option) }
            }
        } label: {
            Text("\(value)\(suffix)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: CornerRadius.sm).fill(Color.PB.surface))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Agent Sessions (Claude Code / Codex CLI)

struct AgentSessionsSectionView: View {
    @ObservedObject var vm: AgentSessionsViewModel
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                if isExpanded { vm.refresh() }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.PB.textMuted)
                        .frame(width: 10)

                    Text(L.agentSessions)
                        .font(Font.PB.sectionTitle)
                        .tracking(1.5)
                        .foregroundColor(Color.PB.textMuted)

                    Spacer()

                    Text(vm.snapshot.summary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color.PB.accent)
                        .lineLimit(1)
                }
                .padding(.horizontal, Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 2) {
                    if vm.snapshot.sessions.isEmpty {
                        Text(vm.isLoading ? L.loading : L.noAgentSessions)
                            .font(Font.PB.caption)
                            .foregroundColor(Color.PB.textMuted)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)
                    } else {
                        ForEach(AgentKind.allCases, id: \.self) { kind in
                            let sessions = vm.snapshot.sessions(of: kind)
                            if !sessions.isEmpty {
                                AgentKindHeaderView(kind: kind, sessions: sessions)
                                ForEach(sessions) { session in
                                    AgentSessionRowView(session: session, vm: vm)
                                }
                            }
                        }

                        HStack {
                            Text(L.helpers(vm.snapshot.helpersMB))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color.PB.textMuted)
                            Spacer()
                            Button(action: { vm.refresh() }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.PB.textMuted)
                            }
                            .buttonStyle(.plain)
                            .help(L.refresh)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.xs)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct AgentKindHeaderView: View {
    let kind: AgentKind
    let sessions: [AgentSession]

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color.PB.textMuted)
                .frame(width: 14)

            Text(kind.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundColor(Color.PB.textMuted)

            Spacer()

            Text("\(sessions.count) · \(sessions.reduce(0) { $0 + $1.rssMB }) MB")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color.PB.textMuted)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
    }
}

struct AgentSessionRowView: View {
    let session: AgentSession
    let vm: AgentSessionsViewModel
    @State private var isHovered = false

    var body: some View {
        // Buttons are always in the layout and only fade in on hover —
        // conditionally inserting them shifted the row under the cursor,
        // which broke hover tracking and made the highlight flicker.
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(memoryColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 0) {
                Text(session.displayLabel)
                    .font(Font.PB.body)
                    .foregroundColor(Color.PB.textPrimary)
                    .lineLimit(1)
                if session.name != nil {
                    Text(session.shortPath)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color.PB.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.sm)

            Button(action: { vm.revealInFinder(session) }) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(Color.PB.textMuted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help(L.showInFinder)

            Text("\(session.rssMB) MB")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.PB.accent)
                .frame(width: 58, alignment: .trailing)

            Text(String(format: "%.0f%%", session.cpuPercent))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color.PB.textMuted)
                .frame(width: 26, alignment: .trailing)

            // Kill at the far right, larger, no confirmation —
            // the conversation survives on disk (`--resume`)
            Button(action: { vm.kill(session) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color.PB.error.opacity(0.85))
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help(L.killSessionConfirm)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Spacing.md)
        .background(RoundedRectangle(cornerRadius: CornerRadius.sm).fill(isHovered ? Color.PB.surfaceHover : Color.clear))
        .help("PID \(session.pid) · up \(session.uptime)\n\(session.cwd)")
        .reliableHover { hovering in
            if isHovered != hovering { isHovered = hovering }
        }
    }

    private var memoryColor: Color {
        switch session.rssMB {
        case ..<400: return Color.PB.success
        case ..<900: return Color.PB.accent
        default: return Color.PB.error
        }
    }
}

// MARK: - Sparkline Chart

struct SparklineChartView: View {
    @ObservedObject var powerVM: PowerDisplayViewModel

    /// Selected history window in seconds. Persisted across launches.
    @AppStorage("powerbar.historyPeriodSeconds") private var periodSeconds = 300
    @State private var samples: [PowerReading] = []
    @State private var hoverX: CGFloat? = nil

    private static let periods: [(seconds: Int, label: String)] = [
        (60, "1m"), (300, "5m"), (900, "15m"), (3600, "1h"), (21600, "6h")
    ]
    /// Max points drawn — history is bucket-averaged down to this.
    private let maxPoints = 180

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text("POWER HISTORY")
                    .font(Font.PB.sectionTitle)
                    .tracking(1.5)
                    .foregroundColor(Color.PB.textMuted)

                Spacer()

                // Period selector
                HStack(spacing: 2) {
                    ForEach(Self.periods, id: \.seconds) { period in
                        Button(action: {
                            periodSeconds = period.seconds
                            reloadSamples()
                        }) {
                            Text(period.label)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(periodSeconds == period.seconds ? Color.PB.bg : Color.PB.textMuted)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .fill(periodSeconds == period.seconds ? Color.PB.accent : Color.PB.surface)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let maxW = max(maxValue, 1)
                let pts = chartPoints(width: w, height: h, maxW: maxW)

                ZStack(alignment: .topLeading) {
                    // Area fill
                    Path { path in
                        guard let first = pts.first else { return }
                        path.move(to: CGPoint(x: first.x, y: h))
                        path.addLine(to: first)
                        for pt in pts.dropFirst() { path.addLine(to: pt) }
                        path.addLine(to: CGPoint(x: pts.last?.x ?? w, y: h))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Color.PB.accent.opacity(0.25), Color.PB.accent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))

                    // Line
                    Path { path in
                        guard let first = pts.first else { return }
                        path.move(to: first)
                        for pt in pts.dropFirst() { path.addLine(to: pt) }
                    }
                    .stroke(Color.PB.accent, lineWidth: 1.5)

                    // Hover crosshair + readout
                    if let x = hoverX, let idx = nearestIndex(to: x, points: pts), idx < samples.count {
                        let pt = pts[idx]
                        let sample = samples[idx]

                        Path { path in
                            path.move(to: CGPoint(x: pt.x, y: 0))
                            path.addLine(to: CGPoint(x: pt.x, y: h))
                        }
                        .stroke(Color.PB.textMuted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

                        Circle()
                            .fill(Color.PB.accent)
                            .frame(width: 5, height: 5)
                            .overlay(Circle().stroke(Color.PB.bg, lineWidth: 1))
                            .position(pt)

                        hoverReadout(for: sample)
                            .offset(x: readoutOffsetX(pointX: pt.x, chartWidth: w), y: 0)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hoverX = location.x
                    case .ended: hoverX = nil
                    }
                }
            }
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))

            // Footer: time axis + stats for the selected window
            HStack {
                Text("-\(periodLabel)")
                    .font(Font.PB.chartLabel)
                    .foregroundColor(Color.PB.textMuted)
                Spacer()
                if let stats = windowStats {
                    Text("avg \(String(format: "%.1f", stats.avg))W · max \(String(format: "%.1f", stats.max))W")
                        .font(Font.PB.chartLabel)
                        .foregroundColor(Color.PB.textMuted)
                }
                Spacer()
                Text("now")
                    .font(Font.PB.chartLabel)
                    .foregroundColor(Color.PB.textMuted)
            }
        }
        .onReceive(powerVM.$currentMetrics) { _ in
            reloadSamples()
        }
        .onAppear { reloadSamples() }
    }

    // MARK: - Hover readout

    private func hoverReadout(for sample: PowerReading) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: "%.1fW", sample.sysPower))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.PB.accent)
            Text("\(Self.timeFormatter.string(from: sample.timestamp)) · \(relativeAge(sample.timestamp))")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Color.PB.textMuted)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Color.PB.surface)
                .overlay(RoundedRectangle(cornerRadius: CornerRadius.sm).stroke(Color.PB.separator, lineWidth: 1))
        )
    }

    /// Keep the readout box inside the chart bounds.
    private func readoutOffsetX(pointX: CGFloat, chartWidth: CGFloat) -> CGFloat {
        let boxWidth: CGFloat = 92
        let preferred = pointX + 8
        return preferred + boxWidth > chartWidth ? pointX - boxWidth - 8 : preferred
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func relativeAge(_ date: Date) -> String {
        let age = max(0, -date.timeIntervalSinceNow)
        if age < 60 { return "-\(Int(age))s" }
        if age < 3600 { return "-\(Int(age / 60))m" }
        return String(format: "-%.1fh", age / 3600)
    }

    // MARK: - Data

    private func reloadSamples() {
        samples = Self.downsample(powerVM.historyReadings(seconds: periodSeconds), to: maxPoints)
    }

    /// Bucket-average readings down to `target` points, keeping the bucket's mid timestamp.
    static func downsample(_ readings: [PowerReading], to target: Int) -> [PowerReading] {
        guard readings.count > target, target > 0 else { return readings }
        let bucketSize = Double(readings.count) / Double(target)
        return (0..<target).map { i in
            let start = Int(Double(i) * bucketSize)
            let end = min(Int(Double(i + 1) * bucketSize), readings.count)
            let bucket = readings[start..<max(end, start + 1)]
            let avgSys = bucket.map(\.sysPower).reduce(0, +) / Double(bucket.count)
            let avgAll = bucket.map(\.allPower).reduce(0, +) / Double(bucket.count)
            let midTimestamp = bucket[bucket.startIndex + bucket.count / 2].timestamp
            return PowerReading(allPower: avgAll, sysPower: avgSys, timestamp: midTimestamp)
        }
    }

    private var periodLabel: String {
        Self.periods.first(where: { $0.seconds == periodSeconds })?.label ?? "\(periodSeconds)s"
    }

    private var windowStats: (avg: Double, max: Double)? {
        guard !samples.isEmpty else { return nil }
        let values = samples.map(\.sysPower)
        return (values.reduce(0, +) / Double(values.count), values.max() ?? 0)
    }

    private var maxValue: Double {
        let m = samples.map(\.sysPower).max() ?? 10
        return max(m * 1.2, 10)
    }

    private func chartPoints(width: CGFloat, height: CGFloat, maxW: Double) -> [CGPoint] {
        guard samples.count > 1 else { return [] }
        let step = width / CGFloat(samples.count - 1)
        return samples.enumerated().map { i, reading in
            CGPoint(x: CGFloat(i) * step, y: height - (CGFloat(reading.sysPower / maxW) * height))
        }
    }

    private func nearestIndex(to x: CGFloat, points: [CGPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        var best = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, pt) in points.enumerated() {
            let d = abs(pt.x - x)
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }
}
