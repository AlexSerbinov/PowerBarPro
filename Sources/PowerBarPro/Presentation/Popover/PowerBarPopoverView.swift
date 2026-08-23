import SwiftUI

/// Main popover view — drops down from the menu bar icon.
struct PowerBarPopoverView: View {
    @ObservedObject var powerVM: PowerDisplayViewModel
    @ObservedObject var batteryVM: BatteryViewModel
    @ObservedObject var processVM: ProcessListViewModel
    var agentSessionsVM: AgentSessionsViewModel?
    var settingsModel: PopoverSettingsModel?
    var onQuit: (() -> Void)?

    var body: some View {
        // Content grew past the popover's max height — sections scroll,
        // the hero stays reachable at the top.
        ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 0) {
            // Fixed top section — always visible
            HeroMetricView(metrics: powerVM.currentMetrics, sessionSummary: powerVM.sessionSummary)

            SectionSeparator()

            MetricsGridView(metrics: powerVM.currentMetrics)
                .padding(.vertical, Spacing.sm)

            // CPU clusters & sensors — collapsible detail sections
            CPUClustersSectionView(metrics: powerVM.currentMetrics)
                .padding(.bottom, Spacing.xs)
            SensorsSectionView(metrics: powerVM.currentMetrics)
                .padding(.bottom, Spacing.sm)

            // Display power
            if let display = powerVM.currentMetrics?.display, display.available {
                DisplayPowerRow(
                    watts: processVM.displayPowerW,
                    brightness: display.brightnessPct
                )
                .padding(.bottom, Spacing.sm)
            }

            BatteryBarView(batteryVM: batteryVM)
                .padding(.bottom, Spacing.sm)

            // Process list — collapsible
            SectionSeparator()
            ProcessListSectionView(processVM: processVM)
                .padding(.vertical, Spacing.sm)

            // Claude/Codex agent sessions — collapsible, snapshot on expand
            if let sessionsVM = agentSessionsVM {
                SectionSeparator()
                AgentSessionsSectionView(vm: sessionsVM)
                    .padding(.vertical, Spacing.sm)
            }

            SectionSeparator()

            // Sparkline — compact
            SparklineChartView(powerVM: powerVM)
                .padding(.vertical, Spacing.xs)

            SectionSeparator()

            // Settings — compact
            if let model = settingsModel {
                SettingsFooterView(model: model, onQuit: onQuit)
                    .padding(.vertical, Spacing.xs)
            }
        }
        .padding(Spacing.md)
        .frame(width: 340)
        }
        .background(
            ZStack {
                Color.PB.bg
                Color.white.opacity(0.015)
            }
        )
    }
}

// MARK: - Settings Footer

struct SettingsFooterView: View {
    @ObservedObject var model: PopoverSettingsModel
    @StateObject private var loginItem = LoginItemService()
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("SETTINGS")
                .font(Font.PB.sectionTitle)
                .tracking(1.5)
                .foregroundColor(Color.PB.textMuted)
                .padding(.horizontal, Spacing.md)

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

// MARK: - Hero Metric

struct HeroMetricView: View {
    let metrics: SystemMetrics?
    var sessionSummary: String = ""

    var body: some View {
        VStack(spacing: 2) {
            Text("TOTAL POWER")
                .font(Font.PB.sectionTitle)
                .tracking(1.5)
                .foregroundColor(Color.PB.textMuted)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                // Monospaced digits update in place — no morphing transition,
                // it reads as constant flicker at 1s refresh.
                Text(heroValue)
                    .font(.system(size: 36, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(Color.PB.accent)

                Text("W")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(Color.PB.textMuted)
            }

            if !sessionSummary.isEmpty {
                Text("\(L.session): \(sessionSummary)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color.PB.textMuted)
                    .help(L.sessionEnergyHelp)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private var heroValue: String {
        guard let m = metrics else { return "--.-" }
        return String(format: "%.1f", m.sysPower)
    }
}

// MARK: - Metrics Grid (2x2)

struct MetricsGridView: View {
    let metrics: SystemMetrics?

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: Spacing.sm),
            GridItem(.flexible(), spacing: Spacing.sm)
        ], spacing: Spacing.sm) {
            MetricCardView(name: "CPU", value: format(metrics?.cpuPower), sub: cpuSub, isAccent: true)
            MetricCardView(name: "GPU", value: format(metrics?.gpuPower), sub: gpuSub, isAccent: true)
            MetricCardView(name: "Package", value: format(metrics?.allPower), sub: aneSub)
            MetricCardView(name: "DRAM", value: format(metrics?.ramPower), sub: dramSub)
        }
    }

    private func format(_ w: Double?) -> String {
        guard let w = w else { return "--.-W" }
        return String(format: "%.1fW", w)
    }

    private var cpuSub: String {
        guard let m = metrics else { return "" }
        let fabric = m.soc.fabricW
        return fabric > 0.01 ? "Fabric: \(String(format: "%.2fW", fabric))" : ""
    }

    private var gpuSub: String {
        guard let cores = metrics?.gpuCores else { return "" }
        return "\(cores) cores"
    }

    private var aneSub: String {
        guard let m = metrics else { return "" }
        return "ANE: \(String(format: "%.3fW", m.anePower))"
    }

    private var dramSub: String {
        guard let gb = metrics?.dramGb else { return "" }
        return "\(gb) GB unified"
    }
}

struct MetricCardView: View {
    let name: String
    let value: String
    let sub: String
    var isAccent: Bool = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(Font.PB.caption)
                .foregroundColor(Color.PB.textMuted)

            Text(value)
                .font(Font.PB.metricValue)
                .foregroundColor(isAccent ? Color.PB.accent : Color.PB.textPrimary)

            if !sub.isEmpty {
                Text(sub)
                    .font(Font.PB.metricSub)
                    .foregroundColor(Color.PB.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(RoundedRectangle(cornerRadius: CornerRadius.md).fill(isHovered ? Color.PB.surfaceHover : Color.PB.surface))
        .overlay(RoundedRectangle(cornerRadius: CornerRadius.md).stroke(Color.PB.separator, lineWidth: 1))
        .onHover { isHovered = $0 }
    }
}

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

// MARK: - CPU Clusters Section

struct CPUClustersSectionView: View {
    let metrics: SystemMetrics?
    @State private var isExpanded = false

    private var clusters: [CPUCluster] {
        guard let soc = metrics?.soc else { return [] }
        var result = soc.ecpuClusters
        if let p = soc.pcpuCluster { result.append(p) }
        return result
    }

    var body: some View {
        if !clusters.isEmpty {
            CollapsibleSection(
                title: L.cpuClusters,
                badge: badgeText,
                isExpanded: $isExpanded
            ) {
                VStack(spacing: 2) {
                    ForEach(clusters, id: \.name) { cluster in
                        ClusterRowView(
                            cluster: cluster,
                            freqMhz: freq(for: cluster),
                            maxW: maxClusterW
                        )
                    }
                    if let gpuFreq = metrics?.soc.gpuFreqMhz, let gpuW = metrics?.gpuPower {
                        ClusterRowView(
                            cluster: CPUCluster(name: "GPU", totalW: gpuW, cores: []),
                            freqMhz: gpuFreq,
                            maxW: maxClusterW
                        )
                    }
                }
            }
        }
    }

    private var badgeText: String {
        let totalCores = clusters.reduce(0) { $0 + $1.cores.count }
        return "\(totalCores) cores"
    }

    private var maxClusterW: Double {
        let values = clusters.map(\.totalW) + [metrics?.gpuPower ?? 0]
        return max(values.max() ?? 1, 0.1)
    }

    /// E-clusters share ecpuFreqMhz; the P-cluster uses pcpuFreqMhz.
    private func freq(for cluster: CPUCluster) -> Int? {
        let isPerf = cluster.name == metrics?.soc.pcpuCluster?.name
        return isPerf ? metrics?.soc.pcpuFreqMhz : metrics?.soc.ecpuFreqMhz
    }
}

struct ClusterRowView: View {
    let cluster: CPUCluster
    let freqMhz: Int?
    let maxW: Double

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(cluster.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.PB.textPrimary)
                .frame(width: 64, alignment: .leading)

            // Relative load bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.PB.surface)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.PB.accent.opacity(0.7))
                        .frame(width: max(2, geo.size.width * CGFloat(cluster.totalW / maxW)))
                }
            }
            .frame(height: 5)

            if let freq = freqMhz {
                Text(freq >= 1000
                     ? String(format: "%.1fGHz", Double(freq) / 1000)
                     : "\(freq)MHz")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color.PB.textMuted)
                    .frame(width: 52, alignment: .trailing)
            }

            Text(String(format: "%.2fW", cluster.totalW))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.PB.accent)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 2)
        .help(cluster.cores.isEmpty ? cluster.name : "\(cluster.name): \(cluster.cores.count) cores")
    }
}

// MARK: - Sensors Section (temperatures + fans)

struct SensorsSectionView: View {
    let metrics: SystemMetrics?
    @State private var isExpanded = false

    /// Hottest sensor per category, hottest categories first.
    private var groupedTemps: [(category: String, maxC: Double)] {
        guard let temps = metrics?.temperatures, !temps.isEmpty else { return [] }
        var byCategory: [String: Double] = [:]
        for t in temps {
            let cat = t.category ?? "Other"
            byCategory[cat] = max(byCategory[cat] ?? 0, t.valueCelsius)
        }
        return byCategory.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private var fans: [FanMetrics] { metrics?.fans ?? [] }

    var body: some View {
        if !groupedTemps.isEmpty || !fans.isEmpty {
            CollapsibleSection(
                title: L.sensors,
                badge: badgeText,
                isExpanded: $isExpanded
            ) {
                VStack(spacing: 2) {
                    ForEach(groupedTemps.prefix(6), id: \.category) { item in
                        SensorRowView(
                            icon: "thermometer.medium",
                            name: item.category,
                            value: String(format: "%.0f°C", item.maxC),
                            valueColor: tempColor(item.maxC)
                        )
                    }
                    ForEach(fans, id: \.name) { fan in
                        SensorRowView(
                            icon: "fan",
                            name: fan.name,
                            value: String(format: "%.0f rpm", fan.actualRpm),
                            valueColor: Color.PB.textPrimary
                        )
                    }
                }
            }
        }
    }

    private var badgeText: String {
        if let hottest = groupedTemps.first {
            return String(format: "%.0f°C", hottest.maxC)
        }
        return "\(fans.count)"
    }

    private func tempColor(_ celsius: Double) -> Color {
        if celsius >= 90 { return Color.PB.error }
        if celsius >= 75 { return Color.PB.accent }
        return Color.PB.textPrimary
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

// MARK: - Display Power Row

struct DisplayPowerRow: View {
    let watts: Double
    let brightness: Double

    var body: some View {
        HStack {
            Image(systemName: "display")
                .foregroundColor(Color.PB.textMuted)
                .font(.system(size: 14))

            Text("Display")
                .font(Font.PB.body)
                .foregroundColor(Color.PB.textPrimary)

            Spacer()

            Text(String(format: "%.1fW", watts))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color.PB.accent)

            Text(String(format: "%.0f%%", brightness))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.PB.textMuted)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.md)
    }
}

// MARK: - Battery Bar

struct BatteryBarView: View {
    @ObservedObject var batteryVM: BatteryViewModel

    var body: some View {
        if batteryVM.isVisible {
            HStack(spacing: Spacing.md) {
                BatteryIconView(percent: batteryVM.percent / 100, isCharging: batteryVM.isCharging)

                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%.0f%%", batteryVM.percent))
                        .font(.system(size: 16, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(batteryColor)

                    Text(statusText)
                        .font(Font.PB.caption)
                        .foregroundColor(Color.PB.textMuted)
                }

                Spacer()

                if !batteryVM.timeRemainingText.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(batteryVM.timeRemainingText)
                            .font(.system(size: 15, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(Color.PB.accent)

                        // Estimate is always discharge time at current draw
                        // (see BatteryService.calculateRemainingTime)
                        Text(L.remaining)
                            .font(Font.PB.caption)
                            .foregroundColor(Color.PB.textMuted)
                    }
                    .help(L.timeRemainingHelp)
                }
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .background(RoundedRectangle(cornerRadius: CornerRadius.md).fill(Color.PB.surface))
            .overlay(RoundedRectangle(cornerRadius: CornerRadius.md).stroke(Color.PB.separator, lineWidth: 1))
        }
    }

    private var statusText: String {
        if batteryVM.isCharging { return "Charging" }
        if batteryVM.isOnBattery { return "On Battery" }
        return "Plugged In"
    }

    private var batteryColor: Color {
        if batteryVM.percent < 20 { return Color.PB.error }
        if batteryVM.isCharging { return Color.PB.success }
        return Color.PB.textPrimary
    }
}

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

            // Expandable process list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(processVM.attributedProcesses.prefix(12)) { proc in
                        ProcessRowView(process: proc)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct ProcessRowView: View {
    let process: AttributedPower
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
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Spacing.md)
        .background(RoundedRectangle(cornerRadius: CornerRadius.sm).fill(isHovered ? Color.PB.surfaceHover : Color.clear))
        .help(tooltip.isEmpty ? process.name : tooltip)
        .onHover { isHovered = $0 }
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

            Spacer()

            if isHovered {
                Button(action: { vm.revealInFinder(session) }) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(Color.PB.textMuted)
                }
                .buttonStyle(.plain)
                .help(L.showInFinder)

                Button(action: { vm.requestKill(session) }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(Color.PB.error.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help(L.killSessionConfirm)
            }

            Text("\(session.rssMB) MB")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.PB.accent)
                .frame(width: 58, alignment: .trailing)

            Text(String(format: "%.0f%%", session.cpuPercent))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color.PB.textMuted)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Spacing.md)
        .background(RoundedRectangle(cornerRadius: CornerRadius.sm).fill(isHovered ? Color.PB.surfaceHover : Color.clear))
        .help("PID \(session.pid) · up \(session.uptime)\n\(session.cwd)")
        .onHover { isHovered = $0 }
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
