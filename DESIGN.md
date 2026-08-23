# Design System — PowerBarPro

## Product Context
- **What this is:** macOS menu bar utility for real-time power consumption monitoring (CPU, GPU, Package, DRAM watts via macmon)
- **Who it's for:** Developers, power users, and hardware enthusiasts who want precise energy data at a glance
- **Space/industry:** macOS system monitoring (peers: iStat Menus, Stats, MenuBar Stats, MoniThor)
- **Project type:** Native macOS menu bar app with SwiftUI popover

## Aesthetic Direction
- **Direction:** Industrial/Utilitarian with Luxury touches
- **Decoration level:** Intentional — subtle grain texture on backgrounds, thin separator lines, monospace numbers that feel like a real meter
- **Mood:** A beautifully machined instrument panel. Precise, premium, quietly confident. Not a dashboard, not a spreadsheet — an instrument.
- **Reference sites:** bjango.com/mac/istatmenus, mac-stats.com, seense.com/menubarstats, monithor.dev

## Typography
- **Display/Hero:** SF Pro Display — native macOS, crisp at all sizes, tight letter-spacing at large sizes (-0.5px)
- **Body:** SF Pro Text — best legibility at small sizes in the popover, 15px/1.6
- **UI/Labels:** SF Pro Text — same as body, 11px uppercase with 1.5px letter-spacing for section headers
- **Data/Numbers:** SF Mono — tabular-nums, tight tracking (-1px at hero size). THE signature design choice. All numeric values use SF Mono for that precision instrument readout feel.
- **Code:** SF Mono
- **Loading:** System fonts, zero loading overhead
- **Scale:** Hero: 42px, Section value: 18px, Body: 15px, Label: 13px, Caption: 11px, Mono data: 10-42px contextual

## Color
- **Approach:** Restrained — 1 accent + warm neutrals. Color is rare and meaningful ("this number matters").
- **Background:** #1C1B1F — warm charcoal (not pure black, not cold blue-black)
- **Surface:** #2B2930 — elevated cards and metric tiles
- **Surface hover:** #343240
- **Primary text:** #E8E5E0 — warm white
- **Muted text:** #8A8690
- **Accent:** #E8A44A — amber/gold. Maps to energy/power. Every competitor uses blue/purple — this is distinctive AND meaningful.
- **Accent dim:** rgba(232, 164, 74, 0.15) — for tag backgrounds, hover states
- **Semantic:** success #5CB85C (battery healthy), warning #E8A44A (high power), error #D64545 (temperature critical), info #5B9BD5
- **Separator:** rgba(232, 229, 224, 0.08)
- **Dark mode:** Primary mode (power monitoring is a glance-at task, dark reduces visual weight)
- **Light mode:** Background #F5F3F0, Surface #FFFFFF, Text #1C1B1F, Muted #6B6670, Accent #C4872E (slightly darkened for contrast)

## Spacing
- **Base unit:** 4px
- **Density:** Comfortable — popover should feel airy but data-rich
- **Scale:** 2xs(2) xs(4) sm(8) md(16) lg(24) xl(32) 2xl(48) 3xl(64)
- **Popover padding:** 16px (md)
- **Card internal padding:** 8px vertical, 16px horizontal
- **Metric grid gap:** 8px (sm)

## Layout (v2 — compact tool)
- **Approach:** Glanceable menu bar tool — everything important in one screen, no scrolling in the default state, details behind progressive disclosure
- **Popover width:** 320px; height fits content (reported via PreferenceKey, capped to screen)
- **Popover structure:**
  1. Header row: total watts (26px) left + battery chip (icon/%/time) right
  2. Metric strip: CPU · GPU · PKG · RAM in one 4-column row (subs in tooltips)
  3. Status line: display watts/brightness + hottest temp, one thin row
  4. Power History: period chips + chart + avg/max footer
  5. Disclosure rows (collapsed): DETAILS (clusters+sensors+fans), ACTIVE PROCESSES, AGENT SESSIONS
  6. Footer: session energy (tiny) + gear (settings page) + quit
- **Settings:** separate page behind the gear, back chevron returns to main
- **Border radius:** sm:4px (buttons, tags), md:8px (strip, chips), lg:12px (popover container)
- **v1 layout** (hero + 2x2 cards + inline settings) preserved at git tag `design-v1`

## Motion
- **Approach:** Minimal-functional — precision, not playfulness
- **Number transitions:** Smooth value changes when wattage updates (ease-out, 200ms)
- **Chart:** Line draws smoothly, area fill follows
- **Easing:** enter(ease-out) exit(ease-in) move(ease-in-out)
- **Duration:** micro(50-100ms) for hover states, short(150-250ms) for number transitions, medium(250-400ms) for chart updates
- **Forbidden:** No bouncing, no spring animations, no overshoot, no decorative motion

## Key Design Principles
1. **SF Mono is the brand.** Every number in the app uses SF Mono. This is what makes PowerBarPro feel like a precision instrument, not another system utility.
2. **Amber means energy.** The accent color is not decorative — it maps to the product's core concept. Use it sparingly: hero values, accent metrics, active states.
3. **Warm, not cold.** Warm charcoal (#1C1B1F) instead of cold blue-black. Warm white (#E8E5E0) instead of pure white. This subtle warmth is the premium feel.
4. **Data density with breathing room.** The popover is compact but never cramped. 4px base unit, 8px gaps between cards, 16px section padding.
5. **Grain texture.** Subtle noise overlay on the popover background. Adds depth and material quality. Keep it very subtle (3% opacity max).

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-05 | Initial design system created | Created by /design-consultation based on competitive research (iStat Menus 7, Stats, MenuBar Stats, MoniThor) |
| 2026-04-05 | Amber accent #E8A44A | All competitors use blue/purple. Amber maps to energy/power and is instantly recognizable |
| 2026-04-05 | SF Mono for all numbers | Precision instrument readout feel. Signature design choice that differentiates from dashboard-style monitors |
| 2026-04-05 | Warm neutrals over cool grays | Premium feel. Warm charcoal #1C1B1F vs industry standard cold #1A1A2E |
| 2026-04-05 | SwiftUI popover format | Modern UI approach vs NSMenu dropdown. Enables charts, animations, rich layout |
| 2026-08-23 | Compact v2 layout | v1 scrolled (~810pt). Menu bar tools must be glanceable: header+strip replace hero+cards, settings moved to a gear page, popover auto-sizes to content. A big scrolling panel reads as "heavy app" — opposite of the product's low-footprint positioning |
