# Windows Market Alerts and Unified Market UI Design

## Scope

This change keeps the macOS pet application as the visual reference while adding an independent WPF/.NET 8 Windows application. Both platforms use the same six market targets, threshold buckets, stale-data rules, debounce/cooldown behavior, notification policy, tone mapping, and persisted preference names. No Swift code is compiled by the Windows build.

## Core model boundaries

- `MarketTarget` is the only source of truth for the six index IDs, display names, and provider symbols.
- `Quote` represents one target only. A provider must return the requested target's symbol and name; a fallback provider may not substitute another index.
- `MarketSnapshot` is keyed by target ID and retains the last valid quote, fetch time, error, and stale/offline state. A menu refresh may update snapshots asynchronously without blocking menu construction.
- `MarketRules` owns raw-value classification (`< 0` 牛妈, `0...1` 牛来, `> 1` 豹拉), trading-session gating, signed formatting without `-0.00%`, and `MarketTone` (`> 0` red, `< 0` green, exactly zero/unavailable gray).
- `MarketStateEngine` continues to enforce 20 seconds of debounce and 120 seconds of cooldown. Invalid, offline, and stale samples never cause a switch.
- `NotificationPolicy` receives the settled automatic transition and only permits one notification for a real boundary crossing (`< 0`/`>= 0` or `<= 1`/`> 1`). Manual selection, first valid sample, polling rotation, same-bucket movement, and stale/offline data are suppressed.
- `PersistedState` gains schema version and `showMarketPill`, while preserving existing state migration. Polling and concrete target selection are mutually exclusive.

## macOS presentation

The floating panel keeps the existing single-pet animation and click audio. The quote label becomes independently toggleable and uses the current target's snapshot. Head glow, label, status summary, and menu percentages all resolve their color through `MarketTone`. The context menu and status-item menu share the same two-level `形态` and `指数` structure; `显示行情标签` is a first-level check item. Opening `指数` schedules an asynchronous stale/missing snapshot refresh and immediately shows cached values.

The status item uses a monochrome template `BrandMark` image only. The complete `AppIcon` remains the Finder/Launchpad icon. Automatic switches and manual pet selection retain the current click/audio behavior, with notification submission routed through the tested policy and dynamic current-target copy.

## Windows presentation

`platforms/windows/NiuLaiMarketPets.Windows.csproj` targets `net8.0-windows` with WPF enabled. The app owns a single-instance mutex, a borderless transparent topmost draggable `MainWindow`, a `NotifyIcon` tray menu, and a matching pet context menu. WebP sprites are decoded with ImageSharp and cropped into animated WPF frames; WAV files and the generated monochrome BrandMark ICO are copied into the publish directory. Toast notifications are attempted first and fall back to tray balloons.

The Windows config store writes `%APPDATA%\\NiuLaiMarketPets\\config.json` through a same-directory temporary file followed by replacement. It records schema version, target/mode/pet, polling, pill, scale, speech size, mute, window position, and startup state. Startup is a current-user Run entry with an explicit uninstall/rollback path.

## Verification

SwiftPM gets a real XCTest target in addition to the existing executable harness. Tests cover the four threshold inputs, raw-tone behavior, `-0.00%`, debounce/cooldown, stale/offline suppression, policy deduplication, current-target notification text, per-target snapshot isolation, polling exclusivity, pill migration, mute/manual/first-sample audio decisions, and shared JSON cases.

Windows tests consume the same `platforms/shared/market-model-cases.json` fixture for thresholds, tones, formatting, and notification transitions. GitHub Actions on `windows-latest` runs `dotnet test`, self-contained `win-x64` publish, creates a ZIP and SHA256, and uploads the ZIP as an artifact. CI success is reported as `WINDOWS_BUILD_PASS`; the completed Windows user acceptance is reported as `WINDOWS_VISUAL_PASS`.
