# Windows platform hook

当前项目只实现 macOS 原生控制器。Windows 目录用于保留二期架构入口，不包含可运行的 Windows 程序。

建议后续复用以下稳定边界：

- `MarketTarget`：指数目标与行情符号。
- `QuoteProviding`：主备行情提供商协议。
- `MarketStateEngine`：自动切换规则、防抖和冷却。
- `PetID` 与 Codex v2 宠物包：宠物资源格式保持跨平台。

Windows 控制器可以替换 `AppKit` 悬浮窗、LaunchAgent 和 macOS 配置重载实现，但不应复制 macOS 的 UI 状态机。
