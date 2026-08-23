# CLAUDE.md

## Development Commands

- `make build` or `swift build -c release` - Build in release mode
- `make test` or `swift test` - Run all 287 tests
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

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health

## Design System
Always read DESIGN.md before making any visual or UI decisions.
All font choices, colors, spacing, and aesthetic direction are defined there.
Do not deviate without explicit user approval.
In QA mode, flag any code that doesn't match DESIGN.md.
