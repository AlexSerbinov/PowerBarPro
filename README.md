# PowerBarPro

macOS menu bar app that shows **real-time power consumption** — and, unlike most monitors, tells you **which apps are actually burning your watts**.

Successor to [powerBar](https://github.com/AlexSerbinov/powerBar) with a full rewrite: clean architecture, per-process power attribution, calibration tooling, and a SwiftUI popover.

## Features

- **Menu bar wattage** — instant or averaged (3s … 1h) system power draw
- **Per-process power attribution** — Kepler-style: exact component power (CPU / DRAM / GPU / storage from hardware counters) is distributed across processes proportionally to their usage of each component. The sum over processes ≈ total SoC power, which is far more accurate than raw `proc_pid_rusage` readings
- **Process list with kill action** — see the top consumers, terminate the hogs
- **App coalition grouping** — "Google Chrome Helper (Renderer)" × 12 rolls up into "Google Chrome"
- **Battery panel** — charge, health, time remaining, charging wattage
- **SwiftUI popover** — hero wattage, metric grid, sparkline history (up to 6h), process list
- **Calibration** — Python tooling (`Scripts/calibrate.py`) measures the real power impact of an app by kill-and-diff against baseline, producing per-app correction coefficients
- **Optional LLM tooltips** — one-line descriptions of unknown processes ("what is `mds_stores`, is it safe to close?") via OpenRouter. Fully optional; without an API key the app works normally, descriptions are just absent

## Requirements

- macOS 13.0+, Apple Silicon
- **[macpow](https://github.com/k06a/macpow)** — power metrics provider (reads IOReport/SMC):
  ```bash
  brew install k06a/tap/macpow
  ```
  If `macpow` is missing, the app falls back to [macmon](https://github.com/vladkens/macmon) (`brew install macmon`) with a reduced metric set (no display/SSD/WiFi breakdown).

> Why an external binary? Component-level power on Apple Silicon comes from private frameworks (IOReport, SMC). `macpow`/`macmon` wrap them well; bundling a native reader is on the roadmap but not worth blocking on.

## Install

```bash
git clone https://github.com/AlexSerbinov/PowerBarPro.git
cd PowerBarPro
make install   # builds release, creates /Applications/PowerBarPro.app, codesigns ad-hoc
open /Applications/PowerBarPro.app
```

Other targets: `make build`, `make test`, `make run`, `make restart`, `make clean`, `make check`.

## Usage

- **Left-click** the menu bar item — popover with metrics, history, process list
- **Right-click** — quick menu: averaging mode, update interval, process averaging, language, quit
- Settings persist via UserDefaults

### Optional: LLM process descriptions

Provide an [OpenRouter](https://openrouter.ai) API key in any of these (first match wins):

1. `OPENROUTER_API_KEY` environment variable
2. `defaults write com.alexserbinov.powerbar-pro openRouterAPIKey sk-or-...` (UserDefaults)
3. `~/Library/Application Support/PowerBarPro/config.json`:
   ```json
   { "openRouterAPIKey": "sk-or-...", "model": "openai/gpt-4.1-mini" }
   ```

Responses are cached on disk per (process, language), so the API is hit once per unknown process.

### Calibration

`proc_pid_rusage` undercounts real app impact (it misses DRAM, GPU, fabric, storage). To correct it:

```bash
python3 Scripts/calibrate.py "Telegram"   # kill-and-diff measurement for one app
python3 Scripts/calibrate_overnight.py    # batch calibration
```

Coefficients are stored in `~/Library/Application Support/PowerBarPro/calibration.json` and applied by the attribution engine on launch.

## Architecture

Clean Architecture + MVVM + Combine + protocol-oriented DI. Every service depends on protocols; `DependencyContainer` is the only composition root.

```
App           main.swift, AppDelegate, DependencyContainer
Presentation  MenuBarManager, MenuBuilder, PopoverManager, ViewModels
Services      MacPowService, ProcessEnergyService, PowerAttributionEngine,
              CoalitionGrouper, CalibrationService, BatteryService, ...
Core          Protocols + Models (SystemMetrics, AttributedPower, ...)
```

287 unit tests: `swift test`.

## License

MIT — see [LICENSE](LICENSE).
