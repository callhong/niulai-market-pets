# Windows 版 1.1.0

Windows 版 1.1.0 是独立的 WPF + .NET 8 应用，目标为 Windows 10/11 `win-x64`。它不编译 Swift；核心模型在 `Core/` 中用 C# 重写，并由共享样例 `platforms/shared/market-model-cases.json` 与 macOS harness 对照。

## 1.1.0 新上线

- 普通桌面软件流程：中文安装器、当前用户安装、开始菜单卸载、旧版原地升级和应用内“检查更新”。
- Windows 真实 GUI：透明置顶单宠物浮窗、三套 WebP 动画、牛头托盘 Logo、宠物菜单与托盘菜单、Toast 失败时的托盘气泡降级。
- 行情体验：六个固定指数、同花顺微盘股 `883418`、股票/ETF 自选池、真实行情名称、10 秒刷新和 60 秒轮询互斥。
- 光效与声音：红涨绿跌头部柔光、边界形态切换、点击/手动切换声音、静音规则和中文四周台词气泡。
- 数据可靠性：同花顺/腾讯 GBK 响应按字节解码，避免 Windows 把有效行情误判为离线；配置仍保持 schema version 2，不迁移用户设置。

最新安装包位于 [v1.1.0 Release](https://github.com/callhong/niulai-market-pets/releases/tag/v1.1.0)：

- [NiuLaiMarketPets-windows-x64-setup.exe](https://github.com/callhong/niulai-market-pets/releases/download/v1.1.0/NiuLaiMarketPets-windows-x64-setup.exe)
- [NiuLaiMarketPets-windows-x64.zip](https://github.com/callhong/niulai-market-pets/releases/download/v1.1.0/NiuLaiMarketPets-windows-x64.zip)

安装器无商业 Authenticode 签名。下载后先校验 Release 中的 SHA256；SmartScreen 提示时使用系统提供的“更多信息 → 仍要运行”，不要关闭安全防护。

包含：

- 透明、置顶、可拖动的单宠物悬浮窗；三套 WebP spritesheet 通过 ImageSharp 解码并按帧播放，不退化为静态图。
- 托盘牛头 ICO、宠物右键菜单和托盘菜单；两处均保留 `指数 ▸` 二级菜单，指数名称与涨跌幅为独立左右两列。
- 六个指数、`<0` 牛妈、`0...1.00` 牛来、`>1.00` 豹拉、20 秒防抖、120 秒冷却、红涨绿跌及离线/过期灰色。
- 当前目标行情每 10 秒刷新；指数或自选池目标轮换仍为每 60 秒一次。有效行情在收盘后也会保持对应形态，通知仍按交易时段和跨越规则控制。
- 在六个固定轮询指数之外，支持“输入股票代码”建立本地自选池；股票和 ETF（例如 `688365`、`510300`、`159915`）都可单独选择或按 60 秒轮询。`883418`/`883421` 走同花顺指标页，普通 6 位代码走东方财富主行情源、腾讯备用行情源，名称以行情源返回的对应名称为准。
- 形态、指数、轮询、行情标签、大小百分比、台词字号、静音、显示/隐藏、开机启动和退出。
- 当前用户级 Mutex 单实例、HKCU 开机启动、原子 `%APPDATA%\NiuLaiMarketPets\config.json`、窗口位置保存、Toast 失败时的托盘气泡降级。

## 本地构建（Windows）

```powershell
dotnet test NiuLaiMarketPets.Windows.Tests\NiuLaiMarketPets.Windows.Tests.csproj -c Release
dotnet publish -c Release -r win-x64 --self-contained true
```

发布目录为 `bin\Release\net8.0-windows10.0.22621.0\win-x64\publish`。直接运行其中的 `NiuLaiMarketPets.Windows.exe` 即可；将整个目录或 CI 生成的 ZIP 放到用户可写目录，不需要管理员权限。

## 极简安装

推荐使用 Release 中的 `NiuLaiMarketPets-windows-x64-setup.exe`：双击安装，默认安装到当前用户的 `%LOCALAPPDATA%\Programs\NiuLaiMarketPets`，不需要管理员权限。安装程序界面、开始菜单名称和应用内诊断使用中文；安装程序会创建开始菜单入口，并可选创建桌面快捷方式；安装完成后可直接启动应用。CI artifact 仍保留，适合验收和回溯。

如果 Windows Defender SmartScreen 提示“Windows 已保护你的电脑”，这是因为当前安装包没有商业 Authenticode 签名，不代表安装包一定有问题。请先用发布页提供的 SHA256 校验文件，再点击“更多信息”→“仍要运行”；不要关闭或修改 Windows Defender/SmartScreen。要让普通用户完全不看到该提示，需要后续使用可信代码签名证书签署安装包，这不属于 1.1.0 范围。

同花顺全 A 页面使用 GBK 编码，Windows 版会按响应头解码；网络失败或返回格式异常时只显示中文诊断。台词气泡按 macOS 的规则从宠物四周出现，带独立漂移、旋转和淡入淡出；自动换行且不做省略，长台词会保持在窗口内完整显示。红涨和绿跌使用宠物头部后方的柔和散射光，不画硬圆环；点击宠物、手动切换形态和自动跨越形态时会播放已预加载的 WAV，静音后所有声音关闭。

四段内置 WAV 已统一为 44.1 kHz、16-bit、双声道，并以 `-14 LUFS` 统一综合响度、`-1.5 dBTP` 作为响度处理上限。后续替换音频源时请保持同一母带标准；如果只提供不同制作音量的成品文件，综合响度相同也可能因压缩、瞬态和开头静音造成听感差异。

`883418` 页面当前提供“微盘股”的点数、昨收和涨跌幅，程序将其作为一个可选行情指标使用；它不加入 60 秒轮询的六个固定指数集合。行情源由同花顺公开页面提供，页面不可访问或字段变化时会显示“网络连接失败”或“返回数据格式异常”。普通个股代码不再误走同花顺行业页；代码输入只接受 6 位数字，输入 `688365` 等个股或 ETF 后会显示为自选池目标，并从东方财富/腾讯返回的 `f58`/名称字段更新真实名称。自选池和固定指数轮询互斥；配置文件仍保留 `ShowMarketPill` 字段，并以新增字段保存自选代码和自选池轮询状态，不升级 schema version。

## 升级

Windows 安装器使用固定的应用标识和默认安装目录。已经安装过旧版本时，直接运行新版本 `NiuLaiMarketPets-windows-x64-setup.exe`，会沿用原安装目录并覆盖应用文件，不需要先卸载；应用配置 `%APPDATA%\NiuLaiMarketPets\config.json` 不在安装目录内，会继续保留。安装器会先关闭正在运行的旧实例，安装完成后可直接启动新版本。

如果之前是把 ZIP 解压到任意目录后直接运行，那属于便携运行，不是安装器登记的安装。第一次请运行安装器完成正式安装；之后每次都可以用新的安装器直接升级。应用菜单和托盘菜单中的“检查更新…”会查询 GitHub Release；发现带 SHA256 文件的 Windows 安装器后，用户确认即可下载、校验并启动安装器。它不会后台静默更新，也不会绕过 SmartScreen。

开始菜单中的“卸载 牛来行情宠物”会执行完整卸载。卸载时会移除当前用户开机启动、保留配置回滚副本，并删除安装目录。它不包含后台自动更新、商业签名或管理员级安装。

## 与 macOS 版的同步范围

Windows 和 macOS 继续共用 `platforms/shared/market-model-cases.json` 对照的涨跌幅、形态和通知边界。普通个股代码的 Windows 行情路由、Windows 安装器内更新、托盘菜单和 WPF 微光属于 Windows 实现；本次不修改 macOS Swift 代码，因此这些 Windows 专属入口不会自动出现在当前 macOS 客户端中。

## 卸载与回滚

在发布目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall-windows.ps1
```

脚本只移除当前用户开机启动，并将现有配置移动到 `%APPDATA%\NiuLaiMarketPets\rollback\<timestamp>`，不删除可恢复状态。

## 验收状态

GitHub Actions 在 job summary 写入 `WINDOWS_BUILD_PASS=<sha256>` 与 `WINDOWS_INSTALLER_PASS=<sha256>`，并上传 `NiuLaiMarketPets-windows-x64` ZIP、`NiuLaiMarketPets-windows-x64-installer` 安装器及各自的 `.sha256`。1.1.0 已完成 Windows 用户实机验收，覆盖完整菜单、托盘气泡和实际听音，验收标记为 `WINDOWS_VISUAL_PASS`。

1.1.0 不包含 Windows ARM64、MSIX/Microsoft Store、商业代码签名和后台自动更新器。
