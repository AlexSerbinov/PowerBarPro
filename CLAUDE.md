# CLAUDE.md

## Development Commands

- `make build` or `swift build -c release` - Build in release mode
- `make test` or `swift test` - Run all 108 tests
- `make run` - Build and run directly
- `make install` - Install to /Applications/PowerBarPro.app
- `make restart` - Full rebuild, reinstall, and restart
- `make clean` - Clean build artifacts
- `make check` - Verify macmon is installed

### Dependencies
- **macmon** (`brew install macmon`) - power data collection
- macOS 13.0+ for Swift Charts framework

## Architecture

**Clean Architecture + MVVM + Combine + Protocol-Oriented DI**

### Layer Diagram
```
App Layer          → main.swift, AppDelegate, DependencyContainer
                      ↓ creates
Presentation       → MenuBarManager, MenuBuilder, ViewModels
                      ↓ uses
Services           → MacMonService, BatteryService, PowerAggregator, UserDefaultsStore
                      ↓ implements
Core (Protocols)   → PowerMonitoring, BatteryMonitoring, ProcessRunning, SettingsStorage
Core (Models)      → PowerMetrics, BatteryState, DisplayMode, PowerReading, AppError
```

### Key Design Decisions

1. **Protocol-based DI**: Every service depends on protocols, not concrete types. `DependencyContainer` is the only place that knows about concrete implementations.

2. **Separation from original PowerBar**: PowerManager (342 lines) was split into:
   - `MacMonService` - subprocess management only
   - `PowerAggregator` - averaging/history (pure logic, no I/O)
   - `PowerDisplayViewModel` - presentation formatting

3. **MenuBarController (462 lines)** was split into:
   - `MenuBarManager` - thin glue, binds VMs to NSStatusItem
   - `MenuBuilder` - pure menu construction
   - `BatteryViewModel` - battery display logic

4. **Typed errors**: `AppError` enum instead of string messages

5. **Persistent settings**: UserDefaults with Codable DisplayMode, auto-persists via Combine

### Component Map

| File | Responsibility | Tests |
|------|---------------|-------|
| PowerMetrics.swift | macmon JSON model | PowerMetricsTests (10) |
| BatteryState.swift | Battery hardware model | BatteryStateTests (10) |
| DisplayMode.swift | Averaging mode enum | DisplayModeTests (11) |
| MacMonService.swift | macmon subprocess | MockPowerMonitor |
| BatteryService.swift | ioreg integration | BatteryServiceTests (12) |
| PowerAggregator.swift | History + averaging | PowerAggregatorTests (15) |
| ProcessRunner.swift | Process abstraction | ProcessRunnerTests (7) |
| UserDefaultsStore.swift | Settings persistence | MockSettingsStore |
| PowerDisplayViewModel.swift | Menu bar display | PowerDisplayVMTests (8) |
| BatteryViewModel.swift | Battery display | BatteryVMTests (6) |
| MenuBuilder.swift | Menu construction | MenuBuilderTests (12) |
| Formatters.swift | Power/time formatting | FormattersTests (17) |

### Extension Points (Future Features)

The architecture is designed for these planned additions:

- **Per-core energy**: Add `PerCoreMetricsService` implementing new protocol, inject into DependencyContainer
- **Active processes**: Add `ProcessListService` with energy consumption data
- **Screen wattage**: Add `ScreenPowerService` using IOKit display APIs
- **Kill process**: Extend `ProcessRunning` protocol with termination capability
- **New menu sections**: Extend `MenuBuilder.buildMenu()` with additional sections

### Excluded from v1
- PowerGraph (SwiftUI Charts popover) - not ported per requirements
