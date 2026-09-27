#Requires -Version 5.1
<#
.SYNOPSIS
    sysfetch —— 一眼看清这台 Windows 的全部配置。

.DESCRIPTION
    零依赖的 neofetch 风格系统信息工具，纯 PowerShell 实现。
    优先走 CIM/WMI 采集，取不到时自动回退到注册表 / 性能计数器 / .NET 接口，
    因此在 WMI 被限制的环境下依然能给出可用结果。

.PARAMETER NoLogo
    不显示左侧 ASCII Logo。

.PARAMETER NoColor
    关闭 ANSI 颜色，输出纯文本（便于重定向到文件）。

.PARAMETER Json
    以 JSON 输出采集到的原始数据，不渲染。

.PARAMETER Logo
    Logo 样式：blocks（默认）| mini | none。

.EXAMPLE
    .\sysfetch.ps1

.EXAMPLE
    .\sysfetch.ps1 -NoLogo -NoColor

.EXAMPLE
    .\sysfetch.ps1 -Json | ConvertFrom-Json
#>
[CmdletBinding()]
param(
    [switch]$NoLogo,
    [switch]$NoColor,
    [switch]$Json,
    [ValidateSet('blocks', 'mini', 'none')]
    [string]$Logo = 'blocks'
)

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$script:Palette = @{
    Neon   = '#39ff14'
    Accent = '#00e5a0'
    Cyan   = '#22d3ee'
    Text   = '#dff5e6'
    Dim    = '#4f7f60'
    Warn   = '#d8b25a'
    Bad    = '#ff5f57'
}

$script:UseColor = -not ($NoColor -or $env:NO_COLOR)
if ($script:UseColor) {
    $vt = $false
    try { $vt = [bool]$Host.UI.SupportsVirtualTerminal } catch { $vt = $false }
    if (-not $vt) { $script:UseColor = $false }
}
$script:ESC = [char]27

function Cl {
    param([string]$Hex, [string]$Text)
    if (-not $script:UseColor) { return $Text }
    if ($null -eq $Text) { $Text = '' }
    $r = [Convert]::ToInt32($Hex.Substring(1, 2), 16)
    $g = [Convert]::ToInt32($Hex.Substring(3, 2), 16)
    $b = [Convert]::ToInt32($Hex.Substring(5, 2), 16)
    return "$script:ESC[38;2;$r;$g;${b}m$Text$script:ESC[0m"
}

function Get-Reg {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name }
    catch { return $null }
}

function Bar {
    param([double]$Percent)
    $width = 16
    $fill = [int][Math]::Round($width * $Percent / 100)
    if ($fill -lt 0) { $fill = 0 }
    if ($fill -gt $width) { $fill = $width }
    $body = ([string][char]0x2588) * $fill + ([string][char]0x2591) * ($width - $fill)
    $tone = $script:Palette.Neon
    if ($Percent -ge 85) { $tone = $script:Palette.Bad }
    elseif ($Percent -ge 65) { $tone = $script:Palette.Warn }
    return (Cl $tone $body)
}

function Row {
    param([string]$Label, [string]$Value)
    return (Cl $script:Palette.Cyan $Label.PadRight(11)) + (Cl $script:Palette.Text $Value)
}

function Fmt-Size {
    param([double]$Bytes)
    if ($Bytes -le 0) { return '0 B' }
    $units = @('B', 'KiB', 'MiB', 'GiB', 'TiB')
    $i = [int][Math]::Floor([Math]::Log($Bytes, 1024))
    if ($i -lt 0) { $i = 0 }
    if ($i -gt 4) { $i = 4 }
    return ('{0:N1} {1}' -f ($Bytes / [Math]::Pow(1024, $i)), $units[$i])
}

function Fmt-Uptime {
    param([TimeSpan]$Span)
    $d = [int]$Span.Days
    $h = [int]$Span.Hours
    $m = [int]$Span.Minutes
    if ($d -gt 0) { return "${d}d ${h}h ${m}m" }
    if ($h -gt 0) { return "${h}h ${m}m" }
    return "${m}m"
}

function Clean-Name {
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text -replace '\s+', ' '
    $t = $t -replace '\(R\)|\(TM\)|\(C\)', ''
    $t = $t -replace '\bCPU\b', ''
    $t = $t -replace '@\s*[\d.]+\s*GHz', ''
    return ($t -replace '\s+', ' ').Trim()
}

function Get-SysInfo {
    $cs  = Get-CimInstance Win32_ComputerSystem  -ErrorAction SilentlyContinue
    $os  = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor       -ErrorAction SilentlyContinue | Select-Object -First 1
    $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    $prd = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $bio = Get-CimInstance Win32_BIOS            -ErrorAction SilentlyContinue
    $bat = Get-CimInstance Win32_Battery         -ErrorAction SilentlyContinue | Select-Object -First 1

    $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $hw  = 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0'
    $bioReg = 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS'

    $osName = $null
    if ($os -and $os.Caption) { $osName = $os.Caption -replace '^Microsoft\s+', '' }
    if (-not $osName -and $reg -and $reg.ProductName) { $osName = $reg.ProductName }
    if (-not $osName) { $osName = 'Windows' }

    $build = 0
    if ($reg -and $reg.CurrentBuild) { $build = [int]$reg.CurrentBuild }
    if ($build -ge 22000 -and $osName -like '*Windows 10*') {
        $osName = $osName -replace 'Windows 10', 'Windows 11'
    }

    $ver = @()
    if ($reg -and $reg.DisplayVersion) { $ver += $reg.DisplayVersion }
    if ($build -gt 0) {
        if ($reg -and $reg.UBR) { $ver += "build $build.$($reg.UBR)" } else { $ver += "build $build" }
    }
    if ($ver.Count -gt 0) { $osName = "$osName ($($ver -join ' '))" }

    $hostModel = $null
    if ($prd -and $prd.Vendor -and $prd.Name) {
        $hostModel = "$($prd.Vendor) $($prd.Name)".Trim()
    }
    if (-not $hostModel) {
        $mf = Get-Reg $bioReg 'SystemManufacturer'
        $pn = Get-Reg $bioReg 'SystemProductName'
        if ($pn) { $hostModel = "$mf $pn".Trim() }
    }

    $biosVer = $null
    if ($bio -and $bio.SMBIOSBIOSVersion) { $biosVer = "$($bio.SMBIOSBIOSVersion)".Trim() }
    if (-not $biosVer) { $biosVer = Get-Reg $bioReg 'BIOSVersion' }

    $cpuName = $null; $cpuCore = ''
    if ($cpu -and $cpu.Name) {
        $cpuName = Clean-Name $cpu.Name
        $cores = $cpu.NumberOfCores
        $threads = $cpu.NumberOfLogicalProcessors
        if ($cores -and $threads) { $cpuCore = " ($cores C / $threads T)" }
        if ($cpu.MaxClockSpeed) { $cpuCore += ' @ {0:N2} GHz' -f ($cpu.MaxClockSpeed / 1000) }
    }
    if (-not $cpuName) {
        $cpuName = Clean-Name (Get-Reg $hw 'ProcessorNameString')
        $mhz = Get-Reg $hw '~MHz'
        if ($env:NUMBER_OF_PROCESSORS) { $cpuCore += " ($($env:NUMBER_OF_PROCESSORS) T)" }
        if ($mhz) { $cpuCore += ' @ {0:N2} GHz' -f ([double]$mhz / 1000) }
    }
    if (-not $cpuName) { $cpuName = 'Unknown CPU' }

    $gpus = @()
    foreach ($g in $gpu) {
        $n = Clean-Name $g.Name
        if ($n -and $gpus -notcontains $n) { $gpus += $n }
    }
    if ($gpus.Count -eq 0) {
        try {
            Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction Stop |
                ForEach-Object {
                    $d = Clean-Name (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).DriverDesc
                    if ($d -and $gpus -notcontains $d) { $gpus += $d }
                }
        } catch { }
    }
    $gpus = @($gpus | Where-Object { $_ -notmatch 'Virtual|Mirror|Remote|Basic Display|Headless' })

    $memTotal = 0; $memFree = 0
    if ($os) {
        $memTotal = [double]$os.TotalVisibleMemorySize * 1KB
        $memFree = [double]$os.FreePhysicalMemory * 1KB
    }
    if ($memTotal -le 0) {
        try {
            $avail = (Get-Counter '\Memory\Available MBytes' -ErrorAction Stop).CounterSamples[0].CookedValue
            if ($avail) { $memFree = [double]$avail * 1MB }
        } catch { }
    }

    $disks = @()
    foreach ($d in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
        if ($d.Size -le 0) { continue }
        $disks += [pscustomobject]@{
            Name  = $d.DeviceID
            Total = [double]$d.Size
            Free  = [double]$d.FreeSpace
        }
    }
    if ($disks.Count -eq 0) {
        try {
            foreach ($dr in [System.IO.DriveInfo]::GetDrives()) {
                if ($dr.DriveType -ne [System.IO.DriveType]::Fixed) { continue }
                if (-not $dr.IsReady -or $dr.TotalSize -le 0) { continue }
                $disks += [pscustomobject]@{
                    Name  = $dr.Name.TrimEnd('\')
                    Total = [double]$dr.TotalSize
                    Free  = [double]$dr.AvailableFreeSpace
                }
            }
        } catch { }
    }

    $battery = $null
    if ($bat) {
        $state = 'Discharging'
        if ($bat.BatteryStatus -eq 2) { $state = 'Charging' }
        elseif ($bat.BatteryStatus -eq 3) { $state = 'Fully charged' }
        $battery = [pscustomobject]@{
            Percent = [int]$bat.EstimatedChargeRemaining
            State   = $state
        }
    }

    $res = $null
    foreach ($g in $gpu) {
        if ($g.CurrentHorizontalResolution -and $g.CurrentVerticalResolution) {
            $res = "$($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution)"
            break
        }
    }

    $uptime = $null
    if ($os -and $os.LastBootUpTime) {
        try { $uptime = (Get-Date) - $os.LastBootUpTime } catch { $uptime = $null }
    }

    $ip = $null
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
            Select-Object -First 1).IPAddress
    } catch { $ip = $null }
    if (-not $ip) {
        try {
            $ip = [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
                Where-Object { $_.AddressFamily -eq 'InterNetwork' -and "$_" -notlike '127.*' } |
                Select-Object -First 1 -ExpandProperty IPAddressToString
        } catch { $ip = $null }
    }

    $term = $Host.Name
    if ($env:WT_SESSION) { $term = 'Windows Terminal' }
    elseif ($env:TERM_PROGRAM) { $term = $env:TERM_PROGRAM }
    elseif ($env:ConEmuPID) { $term = 'ConEmu' }
    elseif ($env:VSCODE_INJECTION) { $term = 'VS Code' }

    [pscustomobject]@{
        User      = [Environment]::UserName
        Host      = $env:COMPUTERNAME
        HostModel = $hostModel
        OS        = $osName
        BIOS      = $biosVer
        CPU       = "$cpuName$cpuCore"
        GPU       = $gpus
        Memory    = [pscustomobject]@{ Total = $memTotal; Free = $memFree; Used = [Math]::Max(0, $memTotal - $memFree) }
        Disks     = $disks
        Battery   = $battery
        Display   = $res
        Uptime    = if ($uptime) { Fmt-Uptime $uptime } else { '' }
        Shell     = "PowerShell $($PSVersionTable.PSVersion)"
        Terminal  = $term
        Network   = $ip
    }
}

function Get-LogoLines {
    param([string]$Style)
    $B = [string][char]0x2584
    $F = [string][char]0x2588
    $T = [string][char]0x2580
    $S = ' '
    if ($Style -eq 'none') { return @() }
    if ($Style -eq 'mini') {
        return @(
            "  $B$B$B$B$B$B$B  $B$B$B$B$B$B$B",
            "  $F$F$F$F$F$F$F  $F$F$F$F$F$F$F",
            "  $T$T$T$T$T$T$T  $T$T$T$T$T$T$T"
        )
    }
    return @(
        "  $B$B$B$B$B$B$B  $B$B$B$B$B$B$B",
        "  $F$S$S$S$S$S$F  $F$S$S$S$S$S$F",
        "  $F$S$S$S$S$S$F  $F$S$S$S$S$S$F",
        "  $F$S$S$S$S$S$F  $F$S$S$S$S$S$F",
        "  $T$T$T$T$T$T$T  $T$T$T$T$T$T$T",
        "",
        "  $B$B$B$B$B$B$B  $B$B$B$B$B$B$B",
        "  $F$S$S$S$S$S$F  $F$S$S$S$S$S$F",
        "  $F$S$S$S$S$S$F  $F$S$S$S$S$S$F",
        "  $F$S$S$S$S$S$F  $F$S$S$S$S$S$F",
        "  $T$T$T$T$T$T$T  $T$T$T$T$T$T$T"
    )
}

$info = Get-SysInfo

if ($Json) {
    $info | ConvertTo-Json -Depth 6
    return
}

$rows = New-Object System.Collections.Generic.List[string]
$title = "$($info.User)@$($info.Host)"
$rows.Add((Cl $script:Palette.Neon $title))
$sepLen = [Math]::Min($title.Length, 34)
$rows.Add((Cl $script:Palette.Dim (([string][char]0x2500) * $sepLen)))

$rows.Add((Row 'OS' $info.OS))
if ($info.HostModel) { $rows.Add((Row 'Host' $info.HostModel)) }
$rows.Add((Row 'CPU' $info.CPU))
if ($info.GPU.Count -gt 0) { $rows.Add((Row 'GPU' ($info.GPU -join '  +  '))) }

if ($info.Memory.Total -gt 0) {
    $pct = [Math]::Round(100 * $info.Memory.Used / $info.Memory.Total, 0)
    $mem = '{0} / {1}  {2} {3}%' -f (Fmt-Size $info.Memory.Used), (Fmt-Size $info.Memory.Total), (Bar $pct), $pct
    $rows.Add((Row 'Memory' $mem))
} elseif ($info.Memory.Free -gt 0) {
    $rows.Add((Row 'Memory' ('available ' + (Fmt-Size $info.Memory.Free))))
}

foreach ($d in ($info.Disks | Select-Object -First 3)) {
    if ($d.Total -le 0) { continue }
    $used = $d.Total - $d.Free
    $pct = [Math]::Round(100 * $used / $d.Total, 0)
    $txt = '{0} / {1}  {2} {3}%' -f (Fmt-Size $used), (Fmt-Size $d.Total), (Bar $pct), $pct
    $rows.Add((Row "Disk $($d.Name)" $txt))
}

if ($info.Battery) { $rows.Add((Row 'Battery' "$($info.Battery.Percent)% ($($info.Battery.State))")) }
if ($info.Display) { $rows.Add((Row 'Display' $info.Display)) }
if ($info.Uptime) { $rows.Add((Row 'Uptime' $info.Uptime)) }
$rows.Add((Row 'Shell' $info.Shell))
$rows.Add((Row 'Terminal' $info.Terminal))
if ($info.Network) { $rows.Add((Row 'Network' $info.Network)) }
if ($info.BIOS) { $rows.Add((Row 'BIOS' $info.BIOS)) }

$logoLines = @()
if (-not $NoLogo) { $logoLines = @(Get-LogoLines $Logo) }

$indent = '  '
if ($logoLines.Count -eq 0) {
    foreach ($r in $rows) { Write-Host ($indent + $r) }
    Write-Host ''
    return
}

$logoWidth = 0
foreach ($l in $logoLines) { if ($l.Length -gt $logoWidth) { $logoWidth = $l.Length } }

$offset = 0
if ($rows.Count -gt $logoLines.Count) {
    $offset = [int][Math]::Floor(($rows.Count - $logoLines.Count) / 2)
}

$total = [Math]::Max($rows.Count, $logoLines.Count + $offset)
$logoColors = @($script:Palette.Neon, $script:Palette.Accent, $script:Palette.Cyan)

for ($i = 0; $i -lt $total; $i++) {
    $li = $i - $offset
    $left = ' ' * $logoWidth
    if ($li -ge 0 -and $li -lt $logoLines.Count) {
        $raw = $logoLines[$li]
        $tone = $logoColors[[Math]::Min([int][Math]::Floor($li / 4), $logoColors.Count - 1)]
        $left = Cl $tone ($raw + (' ' * ($logoWidth - $raw.Length)))
    }
    $right = ''
    if ($i -lt $rows.Count) { $right = $rows[$i] }
    Write-Host ($indent + $left + '   ' + $right)
}
Write-Host ''