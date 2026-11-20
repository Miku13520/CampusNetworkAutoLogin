# CampusNetworkAutoLogin

用于福州大学晋江校区校园网自动认证的 Windows 工具。当前配置针对 `Fzdxkjy-web` 和 `10.20.21.2` 门户，不是通用校园网客户端。

## 下载与安装

下载仓库中的 [Windows 安装包](dist/CampusNetworkAutoLogin-Windows.zip)，或使用 GitHub 的 **Code → Download ZIP** 下载源码。完整解压后，在日常使用的 Windows 账号下依次双击：

1. 双击 `1-Prepare.cmd`，安装程序并创建两个暂未启用的计划任务。
2. 首次安装时双击 `2-SaveAccount.cmd`，在本机窗口填写校园网账号密码，点击保存，然后关闭窗口。
3. 双击 `3-Enable.cmd`，开启开机登录和定时检查，并立即检查一次网络。

已安装旧版的用户用同一个 Windows 账号运行新版的 `1-Prepare.cmd` 和 `3-Enable.cmd` 即可升级，继续使用本机已保存的账号。

请先连接目标校园 Wi-Fi。支持 Windows 10/11 和系统自带的 Windows PowerShell 5.1。按提示完成后，在下一次正常开机时检查能否直接联网。

## 工作方式

- 当前 Windows 用户登录后延迟 15 秒检查一次。在用户保持登录且电脑唤醒期间，每 2 分钟再检查一次。任务以普通权限执行，单次最长 3 分钟。
- 检查发现目标 Wi-Fi 已连上且学校门户要求认证时，最多提交一次登录并验证外网。校园 Wi-Fi 中断后，等 Windows 重新连上再检查认证。
- 认证被拒、保存的凭据无法使用或门户需要人工操作时，会暂停自动提交。解决问题后可重新运行 `3-Enable.cmd`。如果认证结果不明或外网暂未恢复，后续仍会检查联网状态，10 分钟后才允许再次提交。
- 不依赖学校的无感认证绑定名额；校园网账号本身的同时在线数限制仍然适用。
- HTTP 认证接口与当前学校网页登录方式一致。学校修改接口、启用密码加密或验证码后，需要更新本工具。

## 开关

- 双击 `3-Enable.cmd` 开启自动登录，双击 `4-Disable.cmd` 关闭。
- 在 Windows **任务计划程序库**中，对应的两个任务是 `CampusNetworkAutoLogin` 和 `CampusNetworkAutoLogin-Periodic`。

## 安装目录与凭据

程序、配置、加密凭据和脱敏日志保存在：

```text
%LOCALAPPDATA%\CampusNetworkAutoLogin
```

凭据使用 Windows DPAPI 加密。`credential.xml` 只能由保存它的那台电脑上的同一 Windows 用户解密，不能直接迁移到另一台电脑。更换电脑时请重新输入账号密码。

仓库和安装包不包含实际账号、密码、凭据文件或个人诊断日志。不要上传自己的 `credential.xml`、日志或认证链接。安装完成后，删除下载或解压出来的安装包不影响运行。

## 验证与故障排查

运行日志位于安装目录中的 `campus-login.log`。退出码 `0` 表示当前已联网或认证后联网验证成功；若日志写着 `Internet is already available`，说明本次没有提交登录，不能据此认定离线认证已实测成功。应以正常开机后的联网结果或明确的认证成功日志为准。

本工具在原电脑上由用户完成过下线后自动登录测试，其他电脑仍需分别验证。当前没有跨电脑、所有 Windows 版本或所有安全软件环境的测试保证。

验证本版的掉线恢复时，在保持连接校园 Wi-Fi 且出现认证页后，等下一次定时检查，确认外网恢复，并在日志中找到 `Campus authentication succeeded and Internet access was verified`。定时检查发现外网已通时会直接退出，日志主要记录认证结果和异常。

安装不更改 PowerShell 执行策略或安全软件设置。若系统或安全软件拦截，请保留具体错误并停止后续步骤，不要关闭防护或将 PowerShell 整体加入白名单。

## 文件

| 文件 | 用途 |
| --- | --- |
| `CampusLogin.ps1` | 校园网探测、认证和失败后的暂停控制 |
| `CredentialSetup.ps1` | 本机加密凭据保存窗口 |
| `Prepare.ps1` | 安装程序并创建停用状态的计划任务 |
| `Enable.ps1` / `Disable.ps1` | 开关计划任务 |
| `CampusTasks.ps1` | 管理开机登录和定时检查任务 |
| `config.json` | 校园网默认配置，不包含密码 |

`dist` 内的 ZIP 与本仓库源码对应；用户凭据始终只在安装后由本人在本机填写。
