# 牛来行情宠物

一个会看行情、会变形、会发光和发声的桌面小玩具。macOS 13+ 和 Windows 10/11 都支持，桌面上始终只显示一只宠物。

## 直接下载

打开 [最新 Release](https://github.com/callhong/niulai-market-pets/releases/latest)：

- macOS：下载 `NiuLaiMarketPets-1.1.0.dmg`，打开后双击 `Install NiuLai Market Pets.command`。已有旧版直接覆盖升级，不需要先卸载。
- Windows：下载 `NiuLaiMarketPets-windows-x64-setup.exe`，双击安装即可，不需要管理员权限；也可以下载 `NiuLaiMarketPets-windows-x64.zip` 便携运行。

Windows 安装包没有商业数字签名。首次下载请按 Release 页面提供的 `.sha256` 校验；SmartScreen 提示时选择“更多信息 → 仍要运行”。

## 怎么玩

右键宠物，或点击 macOS 状态栏牛头图标：

- 选择自动、牛妈、牛来或豹拉；
- 选择六个指数，或额外选择微盘股 `883418`；
- 输入 6 位股票/ETF 代码，保存到本地自选池；
- 开启固定指数或自选池轮询；
- 调整宠物大小、台词字号、静音和“显示行情标签”；
- 选择“检查更新…”获取新版本。

自动形态很简单：跌破 `0%` 是牛妈，`0%～1.00%` 是牛来，超过 `1.00%` 是豹拉。上涨显示红色，下跌显示绿色，零值和离线显示灰色。有效的形态变化会播放声音并按规则通知，单纯轮换指数不会打扰你。

支持的固定指数：上证指数、中证全指、同花顺全A（沪深）、创业板指、科创50、国证2000。

## 升级和卸载

macOS：打开新 DMG，双击安装命令即可覆盖旧版。安装器会先停止旧实例并保留回滚备份；不建议先手动删除旧 App。需要恢复时运行 DMG 内的卸载脚本。

Windows：直接运行新版安装器即可升级，配置会保留；从开始菜单运行卸载程序即可卸载。

## 从源码构建

macOS：需要 Swift 5.10+、macOS 13+、`jq` 和 Xcode Command Line Tools。

```sh
swift test
swift run NiuLaiMarketPetsTests
./scripts/build-app.sh
./scripts/build-dmg.sh
```

Windows：

```sh
dotnet test platforms/windows/NiuLaiMarketPets.Windows.Tests/NiuLaiMarketPets.Windows.Tests.csproj -c Release
cd platforms/windows && dotnet publish -c Release -r win-x64 --self-contained true
```

Windows CI 会生成安装器、ZIP 和 SHA256。Windows CI 通过不等于 Windows GUI 已完成实机验收。

本项目是娱乐化可视化，不构成投资建议。
