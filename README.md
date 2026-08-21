# 牛来行情宠物

一个会看行情、会变形、会发光和发声的桌面小玩具。支持 macOS 13+ 和 Windows 10/11，桌面上始终只显示一只宠物。

## 直接下载

打开 [最新 Release](https://github.com/callhong/niulai-market-pets/releases/latest)：

- macOS：下载 `NiuLaiMarketPets-1.1.0.dmg`，打开后双击 `Install NiuLai Market Pets.command`。旧版可直接覆盖升级，不需要先卸载。
- Windows：下载 `NiuLaiMarketPets-windows-x64-setup.exe`，双击安装即可，不需要管理员权限；也可下载 `NiuLaiMarketPets-windows-x64.zip` 便携运行。

Windows 安装包暂未使用商业数字签名。首次下载可用 Release 页面提供的 `.sha256` 校验；遇到 SmartScreen 提示时，选择“更多信息 → 仍要运行”。

## 三只行情宠物

| 牛来：微涨时奔跑 | 豹拉：上涨时跳跃 | 牛妈：下跌时流泪 |
| --- | --- | --- |
| ![牛来](assets/showcase/niulai.jpg) | ![豹拉](assets/showcase/baola.jpg) | ![牛妈](assets/showcase/muamua.jpg) |

自动模式根据当前目标的原始涨跌幅切换形态：

| 涨跌幅 | 形态 |
| --- | --- |
| 小于 `0%` | 牛妈 |
| `0%`～`1.00%` | 牛来 |
| 大于 `1.00%` | 豹拉 |

涨为红色、跌为绿色，零值、离线和过期为灰色。自动切换带有 20 秒防抖和 120 秒冷却，离线、过期及同形态波动不会重复打扰。

## 它会做什么

- 支持上证指数、中证全指、同花顺全 A（沪深）、创业板指、科创 50、国证 2000，以及同花顺微盘股 `883418`。
- 可输入 6 位股票或 ETF 代码并保存到本地自选池，展示真实名称、点数和涨跌幅。
- 支持固定目标、六指数轮询和自选池轮询；三种选择互斥，轮换目标本身不会触发通知或声音。
- 点击宠物、手动切换或有效的自动跨形态切换会播放对应声音；静音后全部关闭。
- 宠物带有红涨绿跌微光；文字气泡会漂移并带倾斜角，可调整宠物大小和台词字号。
- 右键宠物或打开菜单栏/托盘菜单，可切换形态、目标、轮询、静音、显示行情标签及显示/隐藏宠物。
- macOS 使用原生菜单栏和系统通知；Windows 使用透明置顶悬浮窗、托盘和 Toast（不可用时降级为气泡）。
- 配置会自动恢复；“检查更新…”可获取新版安装包，不会在后台静默替换应用。

## 动效预览

自动形态切换会显示不同台词气泡；点击宠物也会触发台词和对应声音：

![自动形态与音效](assets/showcase/auto-sound.jpg)

| 牛来奔跑 | 豹拉跳跃 | 牛妈状态 |
| --- | --- | --- |
| ![牛来奔跑](assets/showcase/niulai-running.gif) | ![豹拉跳跃](assets/showcase/baola-jumping.gif) | ![牛妈状态](assets/showcase/muamua-idle.gif) |

[打开或下载 36 秒实机录屏](assets/showcase/niulai-market-pets-demo.mp4)

## 升级和卸载

- macOS：打开新版 DMG，双击安装命令即可覆盖旧版。安装器会停止旧实例、保留配置和回滚备份；需要恢复时运行 DMG 内的卸载脚本。
- Windows：直接运行新版安装器即可原地升级并保留配置；需要移除时，从开始菜单运行“卸载 牛来行情宠物”。

<details>
<summary>开发与源码构建</summary>

### macOS

需要 Swift 5.10+、macOS 13+、`jq` 和 Xcode Command Line Tools。

```sh
swift test
swift run NiuLaiMarketPetsTests
./scripts/validate-public.sh
./scripts/build-app.sh
./scripts/build-dmg.sh
```

### Windows

```sh
dotnet test platforms/windows/NiuLaiMarketPets.Windows.Tests/NiuLaiMarketPets.Windows.Tests.csproj -c Release
cd platforms/windows
dotnet publish -c Release -r win-x64 --self-contained true
```

GitHub Actions 会生成 Windows 安装器、便携 ZIP 和 SHA256。CI 构建通过只代表 `WINDOWS_BUILD_PASS`，不等同于 Windows GUI 实机视觉验收。

</details>

欢迎提交问题、截图、动效和改进建议。更多信息见 [贡献指南](CONTRIBUTING.md) 和 [路线图](ROADMAP.md)。

本项目是娱乐化可视化，不构成投资建议。
