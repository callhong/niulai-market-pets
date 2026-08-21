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
  ├─ persisted stock/ETF watchlist
  ├─ fixed-index / watchlist polling (mutually exclusive)
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
  ├─ independently toggleable market pill
  ├─ native update check that opens a confirmed official DMG download
  └─ flock-based single-instance guard matching the Windows Mutex
```

Windows WPF/.NET 8 是独立可执行程序。它在 `platforms/windows/Core` 中重实现相同的模型边界，消费 `platforms/shared/market-model-cases.json`，不编译 Swift；界面增加透明置顶悬浮窗、WinForms 托盘、Toast/气泡降级、ImageSharp WebP 帧解码和原子 AppData 配置。

行情源和桌面 UI 通过核心模型隔离。`QuoteService` 只负责按同一目标取数和主备降级，并把服务端真实名称写入 `Quote`；`MarketSnapshot` 按目标保存最后有效值并允许菜单异步刷新；`MarketStateEngine` 只负责百分比映射、防抖和冷却；`NotificationPolicy` 只允许真正跨越 0 或 1 的自动切换通知；`MarketSoundPolicy` 统一点击、手动切换、自动切换、轮换和静音规则；`ControllerModel` 负责固定指数、自选池、轮询、用户操作和持久化；macOS 层负责悬浮窗、状态栏、两级菜单和通知。

macOS 的六个固定指数不进入自选池轮询；输入的六位股票/ETF 代码进入本地自选池，`883418` 作为内置微盘股目标保留。选择具体目标会关闭两种轮询，开启一种轮询会关闭另一种。行情药丸只由 `showMarketPill` 控制，不影响行情刷新、形态、声音或通知。

宠物资源由 manifest 加 `spritesheet.webp` 组成，构建时复制到应用包的 `Contents/Resources/Pets/<pet-id>`。运行时只从应用包读取资源，用户状态保存在 `~/Library/Application Support/NiuLaiMarketPets`，不依赖外部配置或外置宠物目录；Windows 从发布目录读取相同三套 WebP/WAV，状态保存在 `%APPDATA%\\NiuLaiMarketPets\\config.json`。

macOS DMG 内的安装命令属于当前用户安装流程：覆盖前停止同产品 LaunchAgent 和手动打开的同产品 App，先把旧 App/LaunchAgent 复制到安装回滚目录，再用暂存包替换应用并重新启动。更新检查只负责查询公开 Release 元数据和打开 DMG 下载，不做后台静默安装。
