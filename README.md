# sysfetch

> 一眼看清这台 Windows 的全部配置。

零依赖、纯 PowerShell 的 neofetch 风格系统信息工具。单文件，下载即用。

## 快速开始

```powershell
# 直接运行
.\sysfetch.ps1

# 被执行策略拦住的话，用这一行绕过（只对本次生效）
powershell -ExecutionPolicy Bypass -File .\sysfetch.ps1
```

## 参数

| 参数 | 说明 |
| --- | --- |
| `-NoLogo` | 不显示左侧 ASCII Logo |
| `-NoColor` | 关闭颜色输出纯文本，方便重定向或写进报告 |
| `-Json` | 输出采集到的原始 JSON，不渲染 |
| `-Logo` | Logo 样式：`blocks`（默认）/ `mini` / `none` |

## 示例

```powershell
# 纯文本
.\sysfetch.ps1 -NoColor

# 写入报告（PowerShell 5.1 / 7 均可）
.\sysfetch.ps1 -NoColor -NoLogo > report.txt

# 只取数据接管道
.\sysfetch.ps1 -Json | ConvertFrom-Json | Select-Object CPU, OS, Uptime

# 紧凑版
.\sysfetch.ps1 -Logo mini
```

## 采集内容

用户 / 主机名 / 机型 / 系统版本与 build / CPU 型号与频率 / 显卡 /
内存占用条 / 磁盘占用条（最多 3 块）/ 电池电量与充电状态 / 分辨率 /
运行时间 / PowerShell 版本 / 终端类型 / 本机 IP / BIOS 版本

## 兼容性

- Windows PowerShell 5.1 与 PowerShell 7+ 均可运行
- 优先走 CIM/WMI 采集；取不到时自动回退到注册表、性能计数器、`.NET` 接口，
  因此在 WMI 被限制或服务异常的环境下依然能给出可用结果
- 支持 ANSI 真彩色的终端显示完整配色，不支持的终端自动降级为纯文本
- 脚本以 **UTF-8 with BOM** 保存，保证 Windows PowerShell 5.1 正确读取中文与制表符

## 常见问题

**输出全是方块或问号？**
终端需要 UTF-8。Windows Terminal 默认没问题；老式控制台先执行 `chcp 65001`。

**没有颜色？**
说明当前终端不支持 ANSI。换成 Windows Terminal，或加 `-NoColor` 明确关闭。

**内存只显示一行 `available`？**
说明 WMI 不可用（被安全软件限制，或 `Winmgmt` 服务没在跑），这时只能读到可用内存。
可以用 `winmgmt /verifyrepository` 检查 WMI 是否正常。

## 下载

无需克隆仓库，直接下载打包文件：

1. 前往 [Releases 最新版](https://github.com/Yuh302331-ctrl/sysfetch/releases/latest) 下载 `sysfetch-v1.0.0.zip`
2. 解压得到 `sysfetch.ps1`，按上面的「快速开始」运行

> English: single-file, zero-dependency PowerShell tool. Grab the zip from the
> [latest release](https://github.com/Yuh302331-ctrl/sysfetch/releases/latest), extract, and run — no install needed.


## 许可证

MIT

## 作者

👤 [Yuh302331-ctrl](https://github.com/Yuh302331-ctrl) · 🏠 [个人主页](https://yuh302331-ctrl.github.io)
