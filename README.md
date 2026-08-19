# NiuLai Market Pets

牛来行情宠物是一个完全独立的 macOS 桌面悬浮宠物：行情变化时，它会自动变形、发光、出声。桌面上始终只显示一只宠物，可通过右键菜单或顶部状态栏切换目标、形态、大小、台词字号、轮询和静音。

它不要求其他桌面软件、配置文件或外置资源目录；三套宠物、动效和本地音效都随应用包发布。当前支持 macOS 13+，Windows 只保留二期架构入口。

## 自动变形 + 光效 + 音效

自动模式严格按所选指数的涨跌幅切换：

| 涨跌幅 | 形态 | 光效 | 音效 |
| --- | --- | --- | --- |
| 小于 0% | 牛妈 | 绿色光晕 | 妈妈拖长音或妈妈救我 |
| 0% 到 1%（含边界） | 牛来 | 红色光晕 | 牛来 |
| 大于 1% | 豹拉 | 红色光晕 | 豹拉 |

切换包含防抖、冷却、交易时段判断、主备行情源和离线降级；临界值变化、手动切换和开盘后的首次有效行情都可以播放音效。静音按钮可以随时关闭声音，设置会持久化。

## 最新预览

| 牛来：微涨时奔跑 | 豹拉：上涨时直线上跳 | 牛妈：下跌时流泪 |
| --- | --- | --- |
| ![牛来](assets/showcase/niulai.jpg) | ![豹拉](assets/showcase/baola.jpg) | ![牛妈](assets/showcase/muamua.jpg) |

自动形态切换会把不同台词气泡分散飘出；点击宠物会快速连击台词并随机播放对应声音：

![自动形态与音效](assets/showcase/auto-sound.jpg)

动效预览：

![牛来奔跑](assets/showcase/niulai-running.gif)
![豹拉跳跃](assets/showcase/baola-jumping.gif)
![牛妈状态](assets/showcase/muamua-idle.gif)

## 功能

- 单宠物悬浮窗：牛来、豹拉、牛妈不会同时显示。
- 自动模式和手动模式；手动模式优先于自动切换。
- 上证指数、同花顺全 A、中证全指、创业板指、科创 50、国证 2000。
- 轮询指数每 60 秒推进一个目标；轮询开启后与具体指数选择互斥。
- 间歇台词气泡、点击连击台词、红涨绿跌光晕和四个本地 WAV 音效。
- 宠物大小和台词字号都使用百分比滑块调节。
- 顶部状态栏与右键菜单保持一致的两级入口：形态、指数。
- 登录启动、状态持久化、行情故障降级和可回滚安装。

## 直接安装

从 [Releases](https://github.com/callhong/niulai-market-pets/releases) 下载最新 DMG，打开后双击 Install NiuLai Market Pets.command。安装器会将独立应用放入当前用户的 Applications 目录，并安装用户级 LaunchAgent。

也可以直接下载当前版本：[NiuLaiMarketPets-1.0.3.dmg](https://github.com/callhong/niulai-market-pets/releases/download/v1.0.3/NiuLaiMarketPets-1.0.3.dmg)。

安装器会：

- 将宠物资源和 WAV 音效内置在应用包中，不再写入外置宠物目录；
- 将运行状态、日志和安装回滚备份保存到 ~/Library/Application Support/NiuLaiMarketPets；
- 发现旧的同产品 LaunchAgent 时先停用并备份，避免两个悬浮控制器同时运行；
- 安装失败时保留备份，卸载时恢复安装前的应用与 LaunchAgent。

首次打开如果 macOS 提示来自未验证开发者，请在系统设置的隐私与安全性中允许打开。公开 Release 默认使用本地临时签名，未配置 Apple Developer 公证。

## 从源码构建

需要 macOS 13+、Swift 5.10+ 工具链、jq 和 Xcode Command Line Tools。

    swift run NiuLaiMarketPetsTests
    ./scripts/validate-public.sh
    ./scripts/build-app.sh
    ./scripts/build-dmg.sh

回归 harness 输出 swift-test-harness: PASS。DMG 构建只包含应用包、安装命令和必要模板；应用包内部已经包含三套宠物、音效和资源清单。

从源码安装：

    ./scripts/install.sh

卸载并恢复安装前状态：

    ./scripts/uninstall.sh

卸载脚本不会删除回滚备份；如需彻底清理，可在确认不再需要恢复后手动删除 ~/Library/Application Support/NiuLaiMarketPets。

## 项目状态

当前发布目标是 macOS。行情提供商使用公开网页接口，接口变更、休市和网络故障都可能导致报价离线或短暂过期；界面会保留最后一个有效报价并显示故障状态。本项目是娱乐化可视化，不构成投资建议。

## 参与贡献

欢迎提交 bug、需求、截图、动效、音效和二创宠物。请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，涉及音频、影视画面或角色素材时同时补充授权说明。欢迎需求建议、问题反馈和 Pull Request。

## 路线图

见 [ROADMAP.md](ROADMAP.md)。二期候选包括个股监控、自建指数、KDJ、均线、日内择时提醒，以及“牛回速归”“上车再补票”等抽象提示。

## 目录说明

- Sources/NiuLaiMarketPets：行情、规则、状态、音频和宠物控制核心。
- Sources/NiuLaiMarketPetsApp：原生 macOS 悬浮窗、状态栏和右键菜单。
- assets/pets：三套宠物源资源；构建时会内置进应用包。
- Resources/Audio：公开发布的本地音效。
- platforms/windows：Windows 端接口预留说明。
