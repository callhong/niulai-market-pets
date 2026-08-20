#ifndef AppVersion
  #define AppVersion "1.1.0"
#endif
#define AppName "牛来行情宠物"
#define AppExeName "NiuLaiMarketPets.Windows.exe"
#define PublishDir "..\bin\Release\net8.0-windows10.0.22621.0\win-x64\publish"
#define DistDir "..\dist"

[Setup]
AppId={{D3D1D617-0F28-4B05-A24D-5F6F9FD6CB72}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppName}
DefaultDirName={localappdata}\Programs\NiuLaiMarketPets
UsePreviousAppDir=yes
DisableDirPage=auto
CloseApplications=yes
RestartApplications=no
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
OutputDir={#DistDir}
OutputBaseFilename=NiuLaiMarketPets-windows-x64-setup
SetupIconFile=..\..\..\Resources\BrandMark.ico
UninstallDisplayIcon={app}\Assets\BrandMark.ico
Uninstallable=yes
CreateUninstallRegKey=yes
UninstallDisplayName={#AppName}
DisableWelcomePage=yes
DisableProgramGroupPage=yes
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Windows installer

[Languages]
Name: "chinese"; MessagesFile: "compiler:Default.isl"

[Messages]
SetupAppTitle=安装
SetupWindowTitle=安装 - %1
UninstallAppTitle=卸载
UninstallAppFullTitle=%1 卸载
InformationTitle=提示
ConfirmTitle=确认
ErrorTitle=错误
ButtonBack=< 上一步
ButtonNext=下一步 >
ButtonInstall=安装
ButtonOK=确定
ButtonCancel=取消
ButtonYes=是
ButtonNo=否
ButtonFinish=完成
ButtonBrowse=浏览...
ButtonWizardBrowse=浏览...
ButtonNewFolder=新建文件夹
ClickNext=点击“下一步”继续，或点击“取消”退出安装程序。
WelcomeLabel1=欢迎使用 [name] 安装向导
WelcomeLabel2=此向导将把 [name/ver] 安装到电脑上。%n%n建议在继续前关闭其他应用程序。
WizardSelectDir=选择安装位置
SelectDirDesc=将 [name] 安装到哪里？
SelectDirLabel3=安装程序将把 [name] 安装到以下文件夹。
SelectDirBrowseLabel=点击“下一步”继续；如需选择其他文件夹，请点击“浏览”。
WizardSelectTasks=选择附加任务
SelectTasksDesc=请选择要执行的附加任务：
SelectTasksLabel2=请选择安装 [name] 时需要执行的附加任务，然后点击“下一步”。
WizardSelectProgramGroup=选择开始菜单文件夹
SelectStartMenuFolderDesc=安装程序应将快捷方式放在哪里？
SelectStartMenuFolderLabel3=安装程序将在以下开始菜单文件夹中创建快捷方式。
SelectStartMenuFolderBrowseLabel=点击“下一步”继续；如需选择其他文件夹，请点击“浏览”。
WizardReady=准备安装
ReadyLabel1=安装程序已准备好将 [name] 安装到电脑上。
ReadyLabel2a=点击“安装”继续，或点击“上一步”检查或更改设置。
ReadyLabel2b=点击“安装”继续。
ReadyMemoDir=安装位置：
ReadyMemoGroup=开始菜单文件夹：
ReadyMemoTasks=附加任务：
WizardPreparing=正在准备安装
PreparingDesc=安装程序正在准备将 [name] 安装到电脑上。
WizardInstalling=正在安装
InstallingLabel=请稍候，安装程序正在安装 [name]。
DiskSpaceMBLabel=至少需要 [mb] MB 可用磁盘空间。
FinishedHeadingLabel=完成 [name] 安装向导
FinishedLabelNoIcons=已完成 [name] 的安装。
FinishedLabel=已完成 [name] 的安装。可通过已创建的快捷方式启动应用。
ClickFinish=点击“完成”退出安装程序。
RunEntryExec=运行 %1
StatusClosingApplications=正在关闭应用程序...
StatusCreateDirs=正在创建文件夹...
StatusExtractFiles=正在解压文件...
StatusCreateIcons=正在创建快捷方式...
StatusSavingUninstall=正在保存卸载信息...
StatusRunProgram=正在完成安装...
ExitSetupTitle=退出安装程序
ExitSetupMessage=安装尚未完成。现在退出将不会安装程序。%n%n以后可以再次运行安装程序完成安装。%n%n确定退出吗？
ConfirmUninstall=确定要完全删除 %1 及其所有组件吗？
UninstallStatusLabel=请稍候，正在从电脑中删除 %1。
UninstalledAll=已成功删除 %1。

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加选项："

[InstallDelete]
Type: files; Name: "{autodesktop}\NiuLai Market Pets.lnk"
Type: filesandordirs; Name: "{autoprograms}\NiuLai Market Pets"

[Code]
const
  UninstallRegistryKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{D3D1D617-0F28-4B05-A24D-5F6F9FD6CB72}_is1';

var
  InstallCompleted: Boolean;

procedure RefreshUninstallRegistration;
begin
  { Keep the per-user Add/Remove Programs entry correct when an older
    installation left the shared AppId key behind. }
  RegWriteStringValue(HKCU, UninstallRegistryKey, 'DisplayName', '{#AppName}');
  RegWriteStringValue(HKCU, UninstallRegistryKey, 'DisplayVersion', '{#AppVersion}');
  RegWriteStringValue(HKCU, UninstallRegistryKey, 'Publisher', '{#AppName}');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  { A portable copy and an installed copy share the same single-instance name.
    Stop the old copy before replacing files so Finish -> Run can start the
    newly installed version instead of being rejected by the old mutex. }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM "{#AppExeName}" /T /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) or (CurStep = ssDone) then
  begin
    InstallCompleted := CurStep = ssDone;
    RefreshUninstallRegistration;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) or (CurUninstallStep = usDone) then
    RegDeleteKeyIncludingSubkeys(HKCU, UninstallRegistryKey);
end;

procedure DeinitializeSetup;
begin
  if InstallCompleted then
    RefreshUninstallRegistration;
end;

procedure DeinitializeUninstall;
begin
  RegDeleteKeyIncludingSubkeys(HKCU, UninstallRegistryKey);
end;

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{autoprograms}\{#AppName}\卸载 {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/IM {#AppExeName} /T /F"; Flags: runhidden waituntilterminated
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\uninstall-windows.ps1"""; Flags: runhidden waituntilterminated

[Run]
Filename: "{app}\{#AppExeName}"; Description: "启动 {#AppName}"; Flags: nowait postinstall skipifsilent
