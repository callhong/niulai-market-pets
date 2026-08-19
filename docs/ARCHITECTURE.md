# Architecture

```text
QuoteService
  ├─ primary provider
  └─ backup provider
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
  ├─ bundled pet resources
  └─ user Application Support state
        ↓
macOS AppKit / SwiftUI floating panel
```

行情源和桌面 UI 通过核心模型隔离。`QuoteService` 只负责取数和主备降级；`MarketStateEngine` 只负责将百分比映射为宠物；`ControllerModel` 负责用户操作、持久化、通知和音效；macOS 层负责悬浮窗、状态栏、菜单和登录启动。

宠物资源由 manifest 加 `spritesheet.webp` 组成，构建时复制到应用包的 `Contents/Resources/Pets/<pet-id>`。运行时只从应用包读取资源，用户状态保存在 `~/Library/Application Support/NiuLaiMarketPets`，不依赖外部配置或外置宠物目录。
