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
  └─ PetSwitcher → Codex user config
        ↓
macOS AppKit / SwiftUI floating panel
```

行情源和桌面 UI 通过核心模型隔离。`QuoteService` 只负责取数和主备降级；`MarketStateEngine` 只负责将百分比映射为宠物；`ControllerModel` 负责用户操作、持久化、通知和音效；macOS 层负责悬浮窗、状态栏、菜单和登录启动。

宠物资源使用 Codex v2 manifest 加 `spritesheet.webp`，安装时复制到 `~/.codex/pets/<pet-id>`。仓库中的 `assets/pets` 是可发布源资源，不依赖生成机器的目录。
