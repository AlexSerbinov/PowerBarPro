import SwiftUI

/// Main popover view — drops down from the menu bar icon.
struct PowerBarPopoverView: View {
    @ObservedObject var powerVM: PowerDisplayViewModel
    @ObservedObject var batteryVM: BatteryViewModel
    @ObservedObject var processVM: ProcessListViewModel
    var settings: SettingsStorage?
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Fixed top section — always visible
            HeroMetricView(metrics: powerVM.currentMetrics)

            SectionSeparator()

            MetricsGridView(metrics: powerVM.currentMetrics)
                .padding(.vertical, Spacing.sm)

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

            SectionSeparator()

            // Sparkline — compact
            SparklineChartView(powerVM: powerVM)
                .padding(.vertical, Spacing.xs)

            SectionSeparator()

            // Settings — compact
            SettingsFooterView(settings: settings, onQuit: onQuit)
                .padding(.vertical, Spacing.xs)
        }
        .padding(Spacing.md)
        .frame(width: 340)
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
    var settings: SettingsStorage?
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
                value: Binding(
                    get: { displayModeToSeconds(settings?.displayMode ?? .average(seconds: 3)) },
                    set: { settings?.displayMode = $0 == 0 ? .instant : .average(seconds: $0) }
                ),
                options: [
                    (0, L.instant), (3, "3s"), (10, "10s"), (30, "30s"),
                    (60, "1m"), (300, "5m"), (3600, "1h")
                ]
            )

            // 2. Process Averaging
            SettingPickerRow(
                label: L.processAveraging,
                icon: "cpu",
                value: Binding(
                    get: { settings?.processAveragingSeconds ?? 30 },
                    set: { settings?.processAveragingSeconds = $0 }
                ),
                options: [
                    (0, "Raw"), (5, "5s"), (10, "10s"), (30, "30s"), (60, "1m"), (300, "5m")
                ]
            )

            // 3. Refresh Rate
            SettingPickerRow(
                label: L.refreshRate,
                icon: "arrow.clockwise",
                value: Binding(
                    get: { settings?.updateIntervalMs ?? 1000 },
                    set: { settings?.updateIntervalMs = $0 }
                ),
                options: [
                    (250, "250ms"), (500, "500ms"), (1000, "1s"), (2500, "2.5s")
                ]
            )

            // 4. Language
            HStack(spacing: Spacing.sm) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundColor(Color.PB.textMuted)
                    .frame(width: 14)

                Text(L.language)
                    .font(Font.PB.caption)
                    .foregroundColor(Color.PB.textMuted)

                Spacer()

                Picker("", selection: Binding(
                    get: { settings?.language ?? .english },
                    set: { settings?.language = $0 }
                )) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            .padding(.horizontal, Spacing.md)

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

    private func displayModeToSeconds(_ mode: DisplayMode) -> Int {
        switch mode {
        case .instant: return 0
        case .average(let s): return s
        }
    }
}

struct SettingPickerRow: View {
    let label: String
    let icon: String
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
                Text(options.first(where: { $0.0 == value })?.1 ?? "---")
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

    var body: some View {
        VStack(spacing: 2) {
            Text("TOTAL POWER")
                .font(Font.PB.sectionTitle)
                .tracking(1.5)
                .foregroundColor(Color.PB.textMuted)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(heroValue)
                    .font(.system(size: 36, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(Color.PB.accent)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: heroValue)

                Text("W")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(Color.PB.textMuted)
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
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: value)

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
                    Text(batteryVM.timeRemainingText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color.PB.textMuted)
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

// MARK: - Sparkline Chart

struct SparklineChartView: View {
    @ObservedObject var powerVM: PowerDisplayViewModel

    @State private var readings: [Double] = []
    private let maxReadings = 60

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Text("POWER HISTORY")
                    .font(Font.PB.sectionTitle)
                    .tracking(1.5)
                    .foregroundColor(Color.PB.textMuted)
                Spacer()
                Text("0-\(Int(maxValue))W")
                    .font(Font.PB.chartLabel)
                    .foregroundColor(Color.PB.textMuted)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let maxW = max(maxValue, 1)

                ZStack {
                    // Area fill
                    Path { path in
                        let pts = chartPoints(width: w, height: h, maxW: maxW)
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
                        let pts = chartPoints(width: w, height: h, maxW: maxW)
                        guard let first = pts.first else { return }
                        path.move(to: first)
                        for pt in pts.dropFirst() { path.addLine(to: pt) }
                    }
                    .stroke(Color.PB.accent, lineWidth: 1.5)
                }
            }
            .frame(height: 45)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        }
        .onReceive(powerVM.$currentMetrics) { metrics in
            if let w = metrics?.sysPower {
                readings.append(w)
                if readings.count > maxReadings {
                    readings.removeFirst()
                }
            }
        }
    }

    private var maxValue: Double {
        let m = readings.max() ?? 10
        return max(m * 1.2, 10)
    }

    private func chartPoints(width: CGFloat, height: CGFloat, maxW: Double) -> [CGPoint] {
        guard readings.count > 1 else { return [] }
        let step = width / CGFloat(readings.count - 1)
        return readings.enumerated().map { i, val in
            CGPoint(x: CGFloat(i) * step, y: height - (CGFloat(val / maxW) * height))
        }
    }
}
