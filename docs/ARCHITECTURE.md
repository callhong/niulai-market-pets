# Architecture

```text
QuoteService
  ├─ primary provider
  └─ backup provider
        ↓
MarketSnapshot cache (one entry per MarketTarget)
  ├─ last valid Quote
  ├─ fetchedAt / stale state
  └─ async menu refresh
        ↓
MarketStateEngine
  ├─ threshold bucket
  ├─ debounce
  ├─ cooldown
  └─ trading-session gate
        ↓
ControllerModel
  ├─ persisted state
  ├─ audio and speech events
  ├─ NotificationPolicy
  ├─ MarketTone
  ├─ persisted pill / polling / mute state
  ├─ bundled pet resources
  └─ user Application Support state
        ↓
macOS AppKit / SwiftUI floating panel
  ├─ BrandMark template status item
  ├─ two-level target menu with two-column rows
  └─ independently toggleable market pill
```

Windows WPF/.NET 8 是独立可执行程序。它在 `platforms/windows/Core` 中重实现相同的模型边界，消费 `platforms/shared/market-model-cases.json`，不编译 Swift；界面增加透明置顶悬浮窗、WinForms 托盘、Toast/气泡降级、ImageSharp WebP 帧解码和原子 AppData 配置。

行情源和桌面 UI 通过核心模型隔离。`QuoteService` 只负责取数和主备降级；`MarketSnapshot` 按指数保存最后有效值并允许菜单异步刷新；`MarketStateEngine` 只负责百分比映射、防抖和冷却；`NotificationPolicy` 只允许真正跨越 0 或 1 的自动切换通知；`ControllerModel` 负责用户操作、持久化和音效；macOS 层负责悬浮窗、状态栏、菜单和登录启动。

宠物资源由 manifest 加 `spritesheet.webp` 组成，构建时复制到应用包的 `Contents/Resources/Pets/<pet-id>`。运行时只从应用包读取资源，用户状态保存在 `~/Library/Application Support/NiuLaiMarketPets`，不依赖外部配置或外置宠物目录；Windows 从发布目录读取相同三套 WebP/WAV，状态保存在 `%APPDATA%\\NiuLaiMarketPets\\config.json`。
