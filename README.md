# NiuLai Market Pets

牛来行情宠物：一个 macOS 桌面悬浮宠物，把市场行情变成一只正在奔跑、跳跃或流泪的宠物。

它只显示当前选中的一只宠物，支持右键菜单和顶部状态栏切换形态、指数、轮询、字号、宠物大小和静音。当前实现 macOS 13+，Windows 只留下二期架构入口。

> 本项目是独立的开源二创项目，不代表投资建议，也不隶属于 OpenAI、Codex 或任何影视/音频权利方。

## 预览

| 牛来 | 豹拉 | 牛妈 |
| --- | --- | --- |
| ![牛来](assets/showcase/niulai.jpg) | ![豹拉](assets/showcase/baola.jpg) | ![牛妈](assets/showcase/muamua.jpg) |

### 动效

![牛来奔跑](assets/showcase/niulai-running.gif)
![豹拉跳跃](assets/showcase/baola-jumping.gif)
![牛妈状态](assets/showcase/muamua-idle.gif)

## 功能

- 单宠物桌面悬浮窗：牛来、豹拉、牛妈不会同时显示。
- 自动模式：跌幅 `< 0%` 选择牛妈，`0%...1%`（含边界）选择牛来，`> 1%` 选择豹拉。
- 20 秒防抖、切换冷却、交易时段判断、主备行情源和故障降级。
- 上证指数、同花顺全 A、中证全指、创业板指、科创 50、国证 2000。
- 轮询指数每 60 秒推进一个目标；手动选择具体指数会自动关闭轮询，二者互斥。
- 间歇台词气泡、点击连击台词、红涨绿跌光晕与四个本地 WAV 音效。
- 宠物和台词字号均可用百分比滑动调节；静音状态持久化。
- 可选登录启动，并保留可回滚的配置备份。

## 直接安装

从 [Releases](https://github.com/callhong/niulai-market-pets/releases) 下载最新 `.dmg`，打开后双击 `Install NiuLai Market Pets.command`。它会把应用、三套宠物包和用户级 LaunchAgent 一起安装到当前用户；安装完成后会自动启动控制器。

如果只想手动拖拽应用，也可以将 `NiuLaiMarketPets.app` 放入 `~/Applications`，但仍需先运行 DMG 中的安装命令来安装 `~/.codex/pets` 宠物包。

首次运行如果 macOS 提示应用来自未验证开发者，请在“系统设置 → 隐私与安全性”中允许打开。公开 Release 默认使用本地临时签名，未配置 Apple Developer 签名与公证。

宠物切换需要 Codex 的用户配置文件存在；应用只改写 `[desktop]` 下的 `selected-avatar-id`，写入前会在 `~/.codex/market-pet/config-backups` 保留最多五份备份。

## 从源码构建

需要 macOS 13+、Swift 5.10+ 工具链和 `jq`；Swift 6 工具链同样支持。

```bash
swift run NiuLaiMarketPetsTests
./scripts/validate-public.sh
./scripts/build-app.sh
./scripts/build-dmg.sh
```

项目当前使用一个可执行回归 harness，以便在没有 XCTest UI 环境时复现核心规则；它会输出 `swift-test-harness: PASS (15 groups)`。SwiftPM 的 `swift test` 目前不会发现可执行 harness，因此不把它作为验收命令。

如果要安装应用、宠物包和用户级 LaunchAgent：

```bash
./scripts/install.sh
```

卸载并恢复安装前的应用、LaunchAgent 和配置备份：

```bash
./scripts/uninstall.sh
```

安装脚本不会修改 `/Applications/ChatGPT.app`。它只写入当前用户的 `~/Applications`、`~/.codex/pets`、`~/.codex/market-pet` 和用户级 LaunchAgent。

## 项目状态

当前发布目标是 macOS。行情提供商是公开网页接口，接口变更、休市和网络故障都可能让报价变成离线或过期状态；界面会保留最后一个有效报价并显示故障状态。

## 参与贡献

欢迎提交 bug、需求、截图、动效和二创宠物。请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，涉及音频、影视画面或角色素材时同时补充授权说明。

## 路线图

见 [ROADMAP.md](ROADMAP.md)。二期候选包括个股监控、自建指数、KDJ、均线、日内择时提醒，以及“牛回速归”“上车再补票”等抽象提示。

## 目录说明

- `Sources/NiuLaiMarketPets`：行情、规则、状态、音频和 Codex 配置核心。
- `Sources/NiuLaiMarketPetsApp`：原生 macOS 悬浮窗、状态栏和右键菜单。
- `assets/pets`：三套 Codex v2 宠物最终包。
- `Resources/Audio`：公开发布的本地音效。
- `platforms/windows`：Windows 端接口预留说明。
