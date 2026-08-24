# ============================================================
#  init_project.ps1 —— MPLAB X 工程一键初始化
# ------------------------------------------------------------
#  在【全新空工程】中运行一次本脚本，将自动完成：
#    1. 探测工程信息：工程名、目标器件、器件包、源文件
#    2. 探测 MPLAB X 与 XC8 编译器安装路径（多版本时可交互选择）
#    3. 生成 scripts\setup_xc8.ps1    （一键配置 XC8 编译器环境）
#    4. 生成 scripts\run_simulate.ps1 （一键仿真）
#    5. 生成 .vscode\tasks.json        （编译/清理/仿真/配置任务）
#    6. 生成 .vscode\settings.json     （Task Buttons 状态栏按钮）
#    7. 生成 .vscode\launch.json       （VS Code 模拟器单步调试）
#    8. 立即配置编译器并尝试编译，验证环境可用
#
#  用法：
#    powershell -ExecutionPolicy Bypass -File scripts\init_project.ps1
#    powershell -ExecutionPolicy Bypass -File scripts\init_project.ps1 -ProjectPath D:\PIC\Project\MyProject
#    powershell -ExecutionPolicy Bypass -File scripts\init_project.ps1 -Xc8Version v4.00 -SkipPrompts
#
#  参数：
#    -ProjectPath   工程根目录（默认当前目录）
#    -Xc8Version    指定 XC8 版本（如 v4.00），省略时自动选择或提示
#    -MplabXPath    指定 MPLAB X 安装目录（如 D:\PIC\MPLABX\v6.35）
#    -Force         覆盖已存在的 .vscode 配置（默认会合并保留）
#    -SkipPrompts   跳过交互提问（自动使用最新版本）
# ============================================================
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$Xc8Version = '',
    [string]$Xc8Root = '',
    [string]$MplabXPath = '',
    [switch]$Force,
    [switch]$SkipPrompts
)
$ErrorActionPreference = 'Stop'

# ---------------- 工具函数 ----------------
function Write-Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "    WARN: $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "    ERROR: $m" -ForegroundColor Red }
function Write-FileUtf8Bom($path, $content) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($true))
}
function Write-FileUtf8($path, $content) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
}

# ---------------- 1. 校验工程 ----------------
Write-Step "1/8 校验工程目录 ..."
$ProjectPath = (Resolve-Path $ProjectPath).Path.TrimEnd('\')
$nbDir = Join-Path $ProjectPath 'nbproject'
if (-not (Test-Path $nbDir)) {
    Write-Err "未找到 nbproject 目录。请确认 $ProjectPath 是有效的 MPLAB X 工程（需含 nbproject\Makefile-variables.mk 等）。"
    exit 1
}
Write-Ok "工程目录: $ProjectPath"

# ---------------- 2. 探测工程信息 ----------------
Write-Step "2/8 探测工程信息 ..."
$projName = $null
$varsMk = Join-Path $nbDir 'Makefile-variables.mk'
if (Test-Path $varsMk) {
    $line = Get-Content $varsMk | Where-Object { $_ -match '^CND_ARTIFACT_NAME_default=' } | Select-Object -First 1
    if ($line) {
        $artifact = ($line -split '=', 2)[1].Trim()
        $projName = $artifact -replace '\.(production|debug)\.(hex|elf|rlf)$', ''
    }
}
if (-not $projName) { $projName = Split-Path $ProjectPath -Leaf }
Write-Ok "工程名: $projName"

$device = ''
$packVendor = 'Microchip'; $packName = ''; $packVersion = ''
$cfgXml = Join-Path $nbDir 'configurations.xml'
if (Test-Path $cfgXml) {
    try {
        $x = New-Object System.Xml.XmlDocument
        $x.Load($cfgXml)
        $conf = $x.configurationDescriptor.confs.conf
        $device = $conf.toolsSet.targetDevice
        if ($conf.packs.pack) {
            $packVendor = $conf.packs.pack.vendor
            $packName = $conf.packs.pack.name
            $packVersion = $conf.packs.pack.version
        }
    } catch { Write-Warn "解析 configurations.xml 失败: $($_.Exception.Message)" }
}
if (-not $device) { $device = 'PIC16F18854'; Write-Warn "未能从工程读取器件型号，使用默认 $device" }
Write-Ok "目标器件: $device  器件包: $packName $packVersion"

$sources = Get-ChildItem $ProjectPath -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Extension -in '.s', '.asm', '.c' } |
           Select-Object -ExpandProperty Name
Write-Ok "源文件: $(if ($sources) { $sources -join ', ' } else { '未找到 .s/.asm/.c 源文件' })"

# ---------------- 3. 探测 MPLAB X ----------------
Write-Step "3/8 探测 MPLAB X ..."
function Find-MplabXRoot {
    $cands = @()
    if ($MplabXPath) { $cands += $MplabXPath }
    if ($env:MPLABX_PATH) { $cands += $env:MPLABX_PATH }
    # PATH 中查找 make.exe（<MPLABX>\gnuBins\GnuWin32\bin）
    foreach ($p in ($env:PATH -split ';')) {
        if ($p -and (Test-Path (Join-Path $p 'make.exe'))) {
            $root = (Split-Path (Split-Path (Split-Path $p -Parent) -Parent) -Parent)
            $cands += $root
        }
    }
    $cands += 'D:\PIC\MPLABX'
    $cands += 'C:\Program Files\Microchip\MPLABX'
    $cands += 'C:\Program Files (x86)\Microchip\MPLABX'
    $cands += 'D:\Program Files\Microchip\MPLABX'
    $reg = @(
        'HKLM:\SOFTWARE\Microchip\MPLAB X IDE',
        'HKLM:\SOFTWARE\WOW6432Node\Microchip\MPLAB X IDE',
        'HKCU:\SOFTWARE\Microchip\MPLAB X IDE'
    )
    foreach ($rp in $reg) {
        try {
            if (Test-Path $rp) {
                $v = Get-ItemProperty $rp -ErrorAction Stop
                foreach ($prop in $v.PSObject.Properties) {
                    if ($prop.Name -match 'InstallDir|Location|Path') {
                        $p = $prop.Value -replace '"', ''
                        if ($p) { $cands += $p }
                    }
                }
            }
        } catch { }
    }
    foreach ($c in $cands) {
        if (-not $c) { continue }
        $c = $c.TrimEnd('\')
        if (-not (Test-Path $c)) { continue }
        # 兼容根目录直接布局：如 D:\MAPLAB_X_IDE\gnuBins\GnuWin32\bin\make.exe
        $rootMake = Join-Path $c 'gnuBins\GnuWin32\bin\make.exe'
        $rootMdb  = Join-Path $c 'mplab_platform\bin\mdb.bat'
        if ((Test-Path $rootMake) -and (Test-Path $rootMdb)) { return $c }
        $verDirs = Get-ChildItem $c -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^v?\d+\.\d+' } |
                   Sort-Object Name -Descending
        foreach ($vd in $verDirs) {
            $make = Join-Path $vd.FullName 'gnuBins\GnuWin32\bin\make.exe'
            $mdb  = Join-Path $vd.FullName 'mplab_platform\bin\mdb.bat'
            if ((Test-Path $make) -and (Test-Path $mdb)) {
                return $vd.FullName
            }
        }
    }
    return $null
}
$mplabRoot = Find-MplabXRoot
if (-not $mplabRoot) {
    Write-Err "未找到 MPLAB X 安装目录（需含 gnuBins\GnuWin32\bin\make.exe）。请用 -MplabXPath 指定。"
    exit 1
}
$makeExe = Join-Path $mplabRoot 'gnuBins\GnuWin32\bin\make.exe'
$mdbBat  = Join-Path $mplabRoot 'mplab_platform\bin\mdb.bat'
$packsDir = Join-Path $mplabRoot 'packs'
Write-Ok "MPLAB X: $mplabRoot"
Write-Ok "make.exe: $makeExe"
Write-Ok "mdb.bat:  $mdbBat"

# ---------------- 4. 探测 XC8 并选择版本 ----------------
Write-Step "4/8 探测 XC8 编译器 ..."
function Find-Xc8Versions {
    $cands = @()
    if ($Xc8Root) { $cands += $Xc8Root }
    if ($env:XC8_ROOT) { $cands += $env:XC8_ROOT }
    # PATH 中查找 xc8-cc.exe 或 pic-as.exe（<root>\vX.Y\bin 或 <root>\vX.Y\pic-as\bin）
    foreach ($p in ($env:PATH -split ';')) {
        if ($p -and ((Test-Path (Join-Path $p 'xc8-cc.exe')) -or (Test-Path (Join-Path $p 'pic-as.exe')))) {
            $vdir = Split-Path -Parent $p
            if ((Split-Path -Leaf $vdir) -match '^v?\d+\.\d+$') { $cands += (Split-Path -Parent $vdir) } else { $cands += $vdir }
        }
    }
    $cands += 'D:\PIC\xc8'
    $cands += 'C:\Program Files\Microchip\xc8'
    $cands += 'C:\Program Files (x86)\Microchip\xc8'
    $cands += 'D:\Program Files\Microchip\xc8'
    $reg = @(
        'HKLM:\SOFTWARE\Microchip\MPLAB XC8',
        'HKLM:\SOFTWARE\WOW6432Node\Microchip\MPLAB XC8',
        'HKCU:\SOFTWARE\Microchip\MPLAB XC8'
    )
    foreach ($rp in $reg) {
        try {
            if (Test-Path $rp) {
                $v = Get-ItemProperty $rp -ErrorAction Stop
                foreach ($prop in $v.PSObject.Properties) {
                    if ($prop.Name -match 'InstallDir|Location|Path') {
                        $p = $prop.Value -replace '"', ''
                        if ($p) { $cands += $p }
                    }
                }
            }
        } catch { }
    }
    $result = @()
    foreach ($c in $cands) {
        if (-not $c) { continue }
        $c = $c.TrimEnd('\')
        if (-not (Test-Path $c)) { continue }
        $verDirs = Get-ChildItem $c -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^v?\d+\.\d+' } |
                   Sort-Object Name -Descending
        foreach ($vd in $verDirs) {
            $binDir = Join-Path $vd.FullName 'bin'
            if (Test-Path (Join-Path $binDir 'xc8-cc.exe')) {
                $result += @{ Root = $c; Version = $vd.Name; Bin = $binDir }
            } elseif (Test-Path (Join-Path $vd.FullName 'xc8-cc.exe')) {
                $result += @{ Root = $c; Version = $vd.Name; Bin = $vd.FullName }
            } elseif (Test-Path (Join-Path $vd.FullName 'pic-as\bin\pic-as.exe')) {
                # 兼容汇编工具链 pic-as（如 v3.10\pic-as\bin\pic-as.exe）
                $result += @{ Root = $c; Version = $vd.Name; Bin = (Join-Path $vd.FullName 'pic-as\bin') }
            }
        }
    }
    return $result
}
$xc8s = @(Find-Xc8Versions)
if ($xc8s.Count -eq 0) {
    Write-Err "未找到 XC8 编译器。请先安装 XC8 或设置环境变量 XC8_ROOT。"
    exit 1
}
$chosen = $null
if ($Xc8Version) {
    $chosen = $xc8s | Where-Object { $_.Version -eq $Xc8Version } | Select-Object -First 1
    if (-not $chosen) {
        Write-Err "未找到 XC8 版本 $Xc8Version，可用版本: $($xc8s.Version -join ', ')"
        exit 1
    }
} elseif ($xc8s.Count -eq 1) {
    $chosen = $xc8s[0]
} else {
    if ($SkipPrompts) { $chosen = $xc8s[0] }
    else {
        Write-Host "检测到多个 XC8 版本，请选择要使用的版本：" -ForegroundColor Yellow
        for ($i = 0; $i -lt $xc8s.Count; $i++) {
            Write-Host "  [$i] $($xc8s[$i].Version)   ($($xc8s[$i].Root))"
        }
        $sel = Read-Host "请输入版本编号（回车默认 0）"
        if ($sel -match '^\d+$') { $sel = [int]$sel } else { $sel = 0 }
        if ($sel -lt 0 -or $sel -ge $xc8s.Count) { $sel = 0 }
        $chosen = $xc8s[$sel]
    }
}
Write-Ok "选用 XC8: $($chosen.Version)  ($($chosen.Bin)\xc8-cc.exe)"

# ---------------- 5. 生成 scripts\setup_xc8.ps1 ----------------
Write-Step "5/8 生成 scripts\setup_xc8.ps1 ..."
$setupTemplate = @'
# ============================================================
#  setup_xc8.ps1 —— 一键配置 MPLAB XC8 编译器环境（自动生成）
# ------------------------------------------------------------
#  功能：
#    1. 自动探测 XC8 安装目录（支持常见路径、注册表、环境变量）
#    2. 自动选择已安装的最新版本（可用 -Version 指定版本）
#    3. 重写 nbproject/Makefile-local-default.mk，修正编译器路径
#    4. 同步更新 nbproject/configurations.xml 中的工具链版本号
#    5. 将 XC8 bin 加入当前会话 PATH
#  用法：
#    powershell -ExecutionPolicy Bypass -File scripts\setup_xc8.ps1 [-Xc8Root <路径>] [-Version v4.00]
# ============================================================
param(
    [string]$Xc8Root = $env:XC8_ROOT,
    [string]$Version = ''
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$MakefileLocal = Join-Path $ProjectRoot 'nbproject\Makefile-local-default.mk'
$ConfigXml     = Join-Path $ProjectRoot 'nbproject\configurations.xml'
function Write-Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "    WARN: $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "    ERROR: $m" -ForegroundColor Red }

# 弹出文件夹选择器（需 STA 线程），返回所选路径或空
function Show-FolderPicker($title) {
    $script:folderResult = $null
    $thread = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $fd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fd.Description = $title
        $fd.ShowNewFolderButton = $false
        if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:folderResult = $fd.SelectedPath
        }
    })
    $thread.SetApartmentState([System.Threading.ApartmentState]::STA)
    $thread.Start()
    $thread.Join()
    return $script:folderResult
}

Write-Step "1/4 探测 XC8 安装目录 ..."
$candidates = @()
if ($Xc8Root) { $candidates += $Xc8Root }
if ($env:XC8_ROOT) { $candidates += $env:XC8_ROOT }
# PATH 中查找 xc8-cc.exe（<root>\vX.Y\bin 或 <root>\vX.Y）
foreach ($p in ($env:PATH -split ';')) {
    if ($p -and (Test-Path (Join-Path $p 'xc8-cc.exe'))) {
        $vdir = Split-Path -Parent $p
        if ((Split-Path -Leaf $vdir) -match '^v?\d+\.\d+$') { $candidates += (Split-Path -Parent $vdir) } else { $candidates += $vdir }
    }
}
$candidates += 'D:\PIC\xc8'
$candidates += 'C:\Program Files\Microchip\xc8'
$candidates += 'C:\Program Files (x86)\Microchip\xc8'
$regPaths = @(
    'HKLM:\SOFTWARE\Microchip\MPLAB XC8',
    'HKLM:\SOFTWARE\WOW6432Node\Microchip\MPLAB XC8',
    'HKCU:\SOFTWARE\Microchip\MPLAB XC8'
)
foreach ($rp in $regPaths) {
    try {
        if (Test-Path $rp) {
            $val = (Get-ItemProperty $rp -ErrorAction Stop)
            foreach ($prop in $val.PSObject.Properties) {
                if ($prop.Name -match 'InstallDir|Location|Path') {
                    $p = $prop.Value -replace '"', ''
                    if ($p) { $candidates += $p }
                }
            }
        }
    } catch { }
}
$foundRoot = $null
foreach ($c in $candidates) {
    $c = $c.TrimEnd('\')
    if (!$c) { continue }
    if (Test-Path $c) {
        $verDirs = Get-ChildItem -Path $c -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^v?\d+\.\d+' }
        if ($verDirs) { $foundRoot = $c; break }
    }
}
if (-not $foundRoot) {
    Write-Warn "自动检测未找到 XC8 编译器。"
    $picked = Show-FolderPicker '请选择 XC8 根目录（含版本子目录，如 D:\PIC\xc8）'
    if ($picked -and (Test-Path $picked)) {
        $foundRoot = $picked.TrimEnd('\')
        Write-Ok "使用文件夹选择器指定: $foundRoot"
    } else {
        $manual = Read-Host "请手动输入 XC8 安装根目录（例如 D:\PIC\xc8，回车取消）"
        $manual = $manual.Trim().Trim('"')
        if ($manual) {
            $manual = $manual.TrimEnd('\')
            $verDirs = Get-ChildItem -Path $manual -Directory -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -match '^v?\d+\.\d+' }
            if (Test-Path $manual -and $verDirs) {
                $foundRoot = $manual
                Write-Ok "使用手动指定路径: $foundRoot"
            } else {
                Write-Err "路径无效或不是 XC8 根目录（应包含 vX.Y 版本子目录）: $manual"
                exit 1
            }
        } else {
            Write-Err "未提供路径，退出。请通过参数 -Xc8Root <路径> 指定，或手动安装 XC8。"
            exit 1
        }
    }
}
Write-Ok "XC8 根目录: $foundRoot"

Write-Step "2/4 选择 XC8 版本 ..."
$versionDirs = Get-ChildItem -Path $foundRoot -Directory |
               Where-Object { $_.Name -match '^v?\d+\.\d+' } |
               Sort-Object Name -Descending
if ($Version) { $versionDirs = $versionDirs | Where-Object { $_.Name -eq $Version } }
$selected = $null; $Xc8Bin = $null
foreach ($vd in $versionDirs) {
    $binDir = Join-Path $vd.FullName 'bin'
    if (Test-Path (Join-Path $binDir 'xc8-cc.exe')) { $selected = $vd; $Xc8Bin = $binDir; break }
}
if (-not $selected) {
    foreach ($vd in $versionDirs) {
        if (Test-Path (Join-Path $vd.FullName 'xc8-cc.exe')) { $selected = $vd; $Xc8Bin = $vd.FullName; break }
    }
}
if (-not $selected) {
    # 兼容汇编工具链 pic-as（如 v3.10\pic-as\bin\pic-as.exe）
    foreach ($vd in $versionDirs) {
        $picBin = Join-Path $vd.FullName 'pic-as\bin'
        if (Test-Path (Join-Path $picBin 'pic-as.exe')) { $selected = $vd; $Xc8Bin = $picBin; break }
    }
}
if (-not $selected) {
    Write-Err "未找到 xc8-cc.exe / pic-as.exe。请检查 XC8 安装是否完整。"
    exit 1
}
$Xc8Version = $selected.Name
$Xc8Cc = Join-Path $Xc8Bin 'xc8-cc.exe'
$Xc8Ar = Join-Path $Xc8Bin 'xc8-ar.exe'
Write-Ok "选用版本: $Xc8Version"
Write-Ok "编译器:   $Xc8Bin"

# ---------- 探测 MPLAB X 与器件包（用于新工程生成 Makefile） ----------
function Find-MplabXRoot {
    $cands = @(
        'D:\PIC\MPLABX',
        'C:\Program Files\Microchip\MPLABX',
        'C:\Program Files (x86)\Microchip\MPLABX',
        'D:\Program Files\Microchip\MPLABX'
    )
    foreach ($c in $cands) {
        if (-not (Test-Path $c)) { continue }
        # 兼容根目录直接布局：如 D:\MAPLAB_X_IDE\gnuBins\GnuWin32\bin\make.exe
        if (Test-Path (Join-Path $c 'gnuBins\GnuWin32\bin\make.exe')) { return $c }
        $vers = Get-ChildItem $c -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^v?\d+\.\d+' } |
                Sort-Object Name -Descending
        foreach ($v in $vers) {
            if (Test-Path (Join-Path $v.FullName 'gnuBins\GnuWin32\bin\make.exe')) { return $v.FullName }
        }
    }
    return $null
}
function Find-DfpDir($mplabRoot) {
    $packsBase = Join-Path $mplabRoot 'packs\Microchip'
    if (-not (Test-Path $packsBase)) { return '' }
    $device = ''
    if (Test-Path $ConfigXml) {
        try {
            $doc = New-Object System.Xml.XmlDocument
            $doc.Load($ConfigXml)
            $device = $doc.configurationDescriptor.confs.conf.toolsSet.targetDevice
        } catch { }
    }
    $prefix = ''
    if ($device -and $device -match '^(PIC\d+[A-Z]+\d)') { $prefix = $Matches[1] }
    $dfps = Get-ChildItem $packsBase -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*_DFP' }
    $candidate = $null
    if ($prefix) { $candidate = $dfps | Where-Object { $_.Name -like "$prefix*_DFP" } | Select-Object -First 1 }
    if (-not $candidate) { $candidate = $dfps | Select-Object -First 1 }
    if (-not $candidate) { return '' }
    $ver = Get-ChildItem $candidate.FullName -Directory -ErrorAction SilentlyContinue |
           Sort-Object Name -Descending | Select-Object -First 1
    if ($ver) { return $ver.FullName.Replace('\', '/') }
    return ''
}
function Find-JavaDir($mplabRoot) {
    $sys = Join-Path $mplabRoot 'sys\java'
    if (-not (Test-Path $sys)) { return '' }
    $jd = Get-ChildItem $sys -Directory -ErrorAction SilentlyContinue |
          Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') } | Select-Object -First 1
    if ($jd) { return $jd.FullName }
    return ''
}

Write-Step "3/4 更新 Makefile-local-default.mk ..."
if (Test-Path $MakefileLocal) {
    $content = Get-Content $MakefileLocal -Raw
    $oldPathRegex = 'D:\\?[^"]*?\\xc8[^"\\]*(?:\\[^"\\]+)*\\bin'
    if ($content -match $oldPathRegex) {
        $oldPath = $Matches[0] -replace '\\\\', '\'
        Write-Ok "检测到旧路径: $oldPath"
        $content = $content.Replace($oldPath, $Xc8Bin)
    } else {
        Write-Warn "未匹配到旧编译器路径，将按最新路径重建关键变量"
        $content = $content -replace '(?m)^MP_CC="[^"]*"', "MP_CC=`"$Xc8Cc`""
        $content = $content -replace '(?m)^MP_AS="[^"]*"', "MP_AS=`"$Xc8Cc`""
        $content = $content -replace '(?m)^MP_LD="[^"]*"', "MP_LD=`"$Xc8Cc`""
        $content = $content -replace '(?m)^MP_AR="[^"]*"', "MP_AR=`"$Xc8Ar`""
        $content = $content -replace '(?m)^MP_CC_DIR="[^"]*"', "MP_CC_DIR=`"$Xc8Bin`""
        $content = $content -replace '(?m)^MP_AS_DIR="[^"]*"', "MP_AS_DIR=`"$Xc8Bin`""
        $content = $content -replace '(?m)^MP_LD_DIR="[^"]*"', "MP_LD_DIR=`"$Xc8Bin`""
        $content = $content -replace '(?m)^MP_AR_DIR="[^"]*"', "MP_AR_DIR=`"$Xc8Bin`""
    }
    Set-Content -Path $MakefileLocal -Value $content -Encoding UTF8
    Write-Ok "已更新 $MakefileLocal"
} else {
    # 新工程：自动生成 Makefile-local-default.mk
    Write-Warn "未找到 Makefile-local-default.mk，为新工程自动生成 ..."
    $mplabRoot = Find-MplabXRoot
    $dfpDir = if ($mplabRoot) { Find-DfpDir $mplabRoot } else { '' }
    $javaDir = if ($mplabRoot) { Find-JavaDir $mplabRoot } else { '' }
    if (-not $mplabRoot) {
        Write-Warn "未找到 MPLAB X，DFP_DIR 与 java 相关变量可能为空，后续可重新运行 [配置XC8] 修正。"
    }
    $mplabFwd = ($mplabRoot -replace '\\', '/')
    $ideBin = "$mplabFwd/mplab_platform/platform/../mplab_ide/modules/../../bin/"
    $genContent = @"
SHELL=cmd.exe
PATH_TO_IDE_BIN=$ideBin
# Adding MPLAB X bin directory to path.
PATH:=${ideBin}:`$(PATH)
# Path to java used to run MPLAB X when this makefile was created
MP_JAVA_PATH="$javaDir/bin/"
OS_CURRENT="`$(shell uname -s)"
MP_CC="$Xc8Cc"
# MP_CPPC is not defined
# MP_BC is not defined
MP_AS="$Xc8Cc"
MP_LD="$Xc8Cc"
MP_AR="$Xc8Ar"
DEP_GEN=`${MP_JAVA_PATH}java -jar "${ideBin}extractobjectdependencies.jar"
MP_CC_DIR="$Xc8Bin"
# MP_CPPC_DIR is not defined
# MP_BC_DIR is not defined
MP_AS_DIR="$Xc8Bin"
MP_LD_DIR="$Xc8Bin"
MP_AR_DIR="$Xc8Bin"
DFP_DIR=$dfpDir
"@
    Set-Content -Path $MakefileLocal -Value $genContent -Encoding UTF8
    Write-Ok "已生成 $MakefileLocal"
}

Write-Step "4/4 同步工具链版本号 ..."
if (Test-Path $ConfigXml) {
    $xml = Get-Content $ConfigXml -Raw -Encoding UTF8
    if ($xml -match '<languageToolchainVersion>[^<]*</languageToolchainVersion>') {
        $xml = $xml -replace '<languageToolchainVersion>[^<]*</languageToolchainVersion>',
                            "<languageToolchainVersion>$Xc8Version</languageToolchainVersion>"
        Set-Content -Path $ConfigXml -Value $xml -Encoding UTF8
        Write-Ok "configurations.xml 工具链版本已更新为 $Xc8Version"
    }
}
$env:PATH = "$Xc8Bin;$env:PATH"
Write-Host ""
Write-Host "=================== XC8 环境配置完成 ===================" -ForegroundColor Green
Write-Host "  版本    : $Xc8Version"
Write-Host "  编译器  : $Xc8Cc"
Write-Host "  下一步  : 运行 [Build hex] 任务编译生成 HEX 固件"
Write-Host "=========================================================" -ForegroundColor Green
exit 0
'@
Write-FileUtf8Bom (Join-Path $ProjectPath 'scripts\setup_xc8.ps1') $setupTemplate
Write-Ok "已生成 scripts\setup_xc8.ps1"

# ---------------- 6. 生成 scripts\run_simulate.ps1 ----------------
Write-Step "6/8 生成 scripts\run_simulate.ps1 ..."
$runSimTemplate = @'
# ============================================================
#  run_simulate.ps1 —— 使用 MPLAB X 模拟器(mdb)仿真当前固件（自动生成）
# ============================================================
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
$HexFile = Join-Path $ProjectRoot 'dist\default\production\__PROJECT__.production.hex'
$MdbBat  = '__MDB_BAT__'
$MdbScript = Join-Path $env:TEMP '__PROJECT___simulate.mdb'
$Device  = '__DEVICE__'

if (-not (Test-Path $HexFile)) {
    Write-Host "[错误] 未找到 HEX 固件: $HexFile" -ForegroundColor Red
    Write-Host "[提示] 请先运行 [Build hex] 任务编译生成固件。" -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path $MdbBat)) {
    Write-Host "[错误] 未找到 mdb.bat: $MdbBat" -ForegroundColor Red
    Write-Host "[提示] 请确认 MPLAB X 安装路径，并修改本脚本中的 MdbBat 变量。" -ForegroundColor Yellow
    exit 1
}

$hex = $HexFile.Replace('\', '/')
$mdbContent = @"
# MPLAB X simulator script (auto-generated)
echo /* ============ SIMULATION START: $Device ============ */
set device $Device
set osc none
set simulator "sim"
set voltage 3.3
set poweroptions.resetDelay 100
device $Device
hwtool sim
echo /* Loading firmware ... */
Program "$hex"
echo /* Firmware loaded. Step 20 instructions to observe initialization */
Stepi 20
print /x LATA
print /x PORTA
print /x TRISA
echo /* Run for a while, then halt, check final state */
Run
Halt
print /x LATA
print /x PORTA
echo /* ============ SIMULATION END ============ */
quit
"@
[System.IO.File]::WriteAllText($MdbScript, $mdbContent, [System.Text.UTF8Encoding]::new($false))

Write-Host "正在调用 MPLAB X mdb 模拟器 ..." -ForegroundColor Cyan
Write-Host "固件: $HexFile" -ForegroundColor DarkGray
& cmd /c "`"$MdbBat`" `"$MdbScript`""
# mdb 的 quit 命令总是返回非 0 退出码，这里统一按成功处理（仿真结果以输出为准）
exit 0
'@
$runSimContent = $runSimTemplate.Replace('__PROJECT__', $projName).Replace('__MDB_BAT__', $mdbBat).Replace('__DEVICE__', $device)
Write-FileUtf8Bom (Join-Path $ProjectPath 'scripts\run_simulate.ps1') $runSimContent
Write-Ok "已生成 scripts\run_simulate.ps1"

# ---------------- 6b. 生成 scripts\run_flash.ps1（烧录） ----------------
$runFlashTemplate = @'
# ============================================================
#  run_flash.ps1 —— 一键烧录 HEX 到芯片（串口 Bootloader，自动生成）
# ============================================================
param(
    [string]$ComPort = '',
    [int]$BaudRate = 115200
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$projName = Split-Path $ProjectRoot -Leaf
$varsMk = Join-Path $ProjectRoot 'nbproject\Makefile-variables.mk'
if (Test-Path $varsMk) {
    $line = Get-Content $varsMk | Where-Object { $_ -match '^CND_ARTIFACT_NAME_default=' } | Select-Object -First 1
    if ($line) {
        $artifact = ($line -split '=', 2)[1].Trim()
        $n = $artifact -replace '\.(production|debug)\.(hex|elf|rlf)$', ''
        if ($n) { $projName = $n }
    }
}
$HexFile  = Join-Path $ProjectRoot "dist\default\production\$projName.production.hex"
$FlashPy  = Join-Path $ProjectRoot 'flash_v3.py'
$MakeExe  = '__MAKE_EXE__'
if (-not (Test-Path $FlashPy)) {
    Write-Host "[错误] 未找到烧录脚本: $FlashPy" -ForegroundColor Red
    Write-Host "[提示] 请将 flash_v3.py 放到工程根目录。" -ForegroundColor Yellow
    exit 1
}
Write-Host "==> 检查 HEX 固件 ..." -ForegroundColor Cyan
if (Test-Path $HexFile) {
    Write-Host "    已存在: $HexFile" -ForegroundColor Green
    Write-Host "    直接烧录，跳过编译。" -ForegroundColor Green
} else {
    Write-Host "    未找到: $HexFile" -ForegroundColor Yellow
    Write-Host "    先编译生成 HEX 固件 ..." -ForegroundColor Yellow
    if (-not (Test-Path $MakeExe)) {
        Write-Host "[错误] 未找到 make.exe: $MakeExe" -ForegroundColor Red
        Write-Host "[提示] 请先运行 [配置XC8] 修正编译器路径。" -ForegroundColor Yellow
        exit 1
    }
    Push-Location $ProjectRoot
    & $MakeExe -f nbproject/Makefile-default.mk build CONF=default TYPE_IMAGE=production | Out-Host
    $buildOk = ($LASTEXITCODE -eq 0)
    Pop-Location
    if (-not $buildOk -or -not (Test-Path $HexFile)) {
        Write-Host "[错误] 编译失败，未生成 HEX 固件。请查看上方错误信息。" -ForegroundColor Red
        exit 1
    }
    Write-Host "    编译完成: $HexFile" -ForegroundColor Green
}
Write-Host "==> 检测串口 ..." -ForegroundColor Cyan
$ports = @([System.IO.Ports.SerialPort]::GetPortNames())
if ($ports.Count -eq 0) {
    Write-Host "[错误] 未检测到任何串口。请连接芯片（USB转串口）后重试。" -ForegroundColor Red
    exit 1
}
if (-not $ComPort) {
    if ($ports.Count -eq 1) {
        $ComPort = $ports[0]
        Write-Host "    自动使用唯一串口: $ComPort" -ForegroundColor Green
    } else {
        Write-Host "    检测到多个串口，请选择芯片对应的串口：" -ForegroundColor Yellow
        for ($i = 0; $i -lt $ports.Count; $i++) { Write-Host "      [$i] $($ports[$i])" }
        $sel = Read-Host "请输入编号（回车取消）"
        if ($sel -match '^\d+$' -and [int]$sel -lt $ports.Count) { $ComPort = $ports[[int]$sel] }
        else { Write-Host "[提示] 未选择串口，取消烧录。" -ForegroundColor Yellow; exit 1 }
    }
}
Write-Host "    使用串口: $ComPort  @ $BaudRate" -ForegroundColor Green
Write-Host ""
Write-Host "==> 启动烧录 ..." -ForegroundColor Cyan
Write-Host "    固件: $HexFile" -ForegroundColor DarkGray
Write-Host "    请确保芯片已上电、Bootloader 就绪（按提示操作）。" -ForegroundColor DarkGray
Write-Host ""
& python $FlashPy $HexFile $ComPort $BaudRate
$exit = $LASTEXITCODE
Write-Host ""
Write-Host "烧录进程结束（退出码: $exit）。" -ForegroundColor DarkGray
exit $exit
'@
$runFlashContent = $runFlashTemplate.Replace('__MAKE_EXE__', $makeExe)
Write-FileUtf8Bom (Join-Path $ProjectPath 'scripts\run_flash.ps1') $runFlashContent
Write-Ok "已生成 scripts\run_flash.ps1（烧录）"

# ---------------- 6c. 生成 flash_v3.py（串口烧录脚本） ----------------
$flashPyTemplate = @'
#!/usr/bin/env python3
import sys
import time
import os
import serial
from colorama import init, Fore, Style
from enum import Enum, auto

# --- Platform-specific non-blocking input ---
try:
    import msvcrt
    def get_char_non_blocking():
        if msvcrt.kbhit():
            return msvcrt.getch().decode('utf-8').lower()
        return None
except ImportError:
    import tty, termios, select, atexit
    _fd = sys.stdin.fileno()
    _old_settings = termios.tcgetattr(_fd)
    def get_char_non_blocking():
        if select.select([sys.stdin], [], [], 0) == ([sys.stdin], [], []):
            return sys.stdin.read(1).lower()
        return None
    tty.setcbreak(sys.stdin.fileno())
    atexit.register(lambda: termios.tcsetattr(_fd, termios.TCSADRAIN, _old_settings))
# --- End of platform-specific input ---

class State(Enum):
    """Defines the main states of the application."""
    CONNECTING = auto()
    OPERATING = auto()
    RELEASED = auto()

def find_hex_file(path_arg):
    """Finds the HEX file heuristically if a directory is given."""
    if os.path.isfile(path_arg):
        print(f"{Fore.GREEN}直接使用文件: {path_arg}{Style.RESET_ALL}")
        return path_arg
    if os.path.isdir(path_arg):
        project_name = os.path.basename(os.path.abspath(path_arg))
        heuristic_path = os.path.join(path_arg, "dist", "default", "production", f"{project_name}.production.hex")
        print(f"{Fore.CYAN}输入为目录，尝试查找启发式路径: {heuristic_path}{Style.RESET_ALL}")
        if os.path.isfile(heuristic_path):
            print(f"{Fore.GREEN}成功找到HEX文件: {heuristic_path}{Style.RESET_ALL}")
            return heuristic_path
    return None

def flash_chip_interactive(serial_port_path, baud_rate, data_file_path):
    """Main interactive flashing loop with state management."""
    init(autoreset=True)
    C_GREEN, C_YELLOW, C_RED, C_CYAN, C_RESET = Fore.GREEN, Fore.YELLOW, Fore.RED, Fore.CYAN, Style.RESET_ALL

    print("\n--- 交互式烧录/调试工具 ---")
    print(f"按 {C_YELLOW}P{C_RESET} 暂停/恢复检测 | 按 {C_YELLOW}R{C_RESET} 释放/重新连接串口 | 按 {C_YELLOW}Ctrl+C{C_RESET} 退出")

    current_state = State.CONNECTING
    ser = None
    is_paused = False

    while True:
        try:
            # --- State: CONNECTING ---
            if current_state == State.CONNECTING:
                print(f"\r{C_YELLOW}[连接中]{C_RESET} 尝试连接串口 {serial_port_path}...", end="")
                try:
                    ser = serial.Serial(
                        port=serial_port_path, baudrate=baud_rate, bytesize=serial.EIGHTBITS,
                        parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE, timeout=0
                    )
                    ser.read_all()
                    print(f"\r{' ' * 80}\r{C_GREEN}[已连接]{C_RESET} 串口连接成功。请按RST键，将开始检测。")
                    current_state = State.OPERATING
                    is_paused = False
                except serial.SerialException as e:
                    print(f"\r{' ' * 80}\r{C_RED}[连接失败]{C_RESET} {e}. 等待用户指令...", end="")
                    current_state = State.RELEASED

            # --- State: RELEASED ---
            elif current_state == State.RELEASED:
                if ser and ser.is_open: ser.close()
                print(f"\r{C_RED}[已释放]{C_RESET} 串口已断开。按 {C_YELLOW}R{C_RESET} 重新连接。", end="")
                if get_char_non_blocking() == 'r':
                    current_state = State.CONNECTING
                time.sleep(0.1)

            # --- State: OPERATING ---
            elif current_state == State.OPERATING:
                char = get_char_non_blocking()
                if char == 'p': is_paused = not is_paused
                elif char == 'r':
                    print(f"\n{C_YELLOW}用户请求释放串口...{C_RESET}")
                    current_state = State.RELEASED
                    continue

                incoming_data = ""
                try:
                    if ser.in_waiting > 0:
                        incoming_data = ser.read(ser.in_waiting).decode('utf-8', errors='ignore')
                except serial.SerialException:
                    print(f"\n{C_RED}串口断开连接！{C_RESET}")
                    current_state = State.RELEASED
                    continue

                if incoming_data:
                    print(f"\r{' ' * 80}\r{C_CYAN}串口接收: {C_RESET}{incoming_data.strip()}")

                if 'W_HEX>' in incoming_data:
                    # --- Flashing Sub-routine ---
                    print(f"{C_GREEN}成功进入调试模式 ('W_HEX>' 已收到)。{C_RESET}")
                    print(f"{C_GREEN}[烧录中]{C_RESET} 正在从 '{os.path.basename(data_file_path)}' 烧录...")

                    try:
                        with open(data_file_path, 'r', encoding='utf-8') as f:
                            content_to_flash = f.read()
                    except FileNotFoundError:
                        print(f"{C_RED}错误: 烧录文件 '{data_file_path}' 未找到。{C_RESET}")
                        time.sleep(2)
                        continue

                    lines = content_to_flash.splitlines()
                    for i, line in enumerate(lines):
                        ser.write((line + '\n').encode('utf-8'))
                        time.sleep(0.005)
                        print(f"\r烧录进度: {i+1}/{len(lines)}", end="")

                    print(f"\n{C_GREEN}烧录完成。{C_RESET}")

                    # 清空串口缓冲区，防止残留数据触发再次烧录
                    print(f"{C_YELLOW}清空串口缓冲区...{C_RESET}")
                    ser.read_all()
                    time.sleep(0.5)
                    ser.read_all()

                    # 烧录成功后自动退出程序
                    print(f"{C_GREEN}烧录成功，程序自动退出。{C_RESET}")
                    break

                # Update status line for OPERATING state
                if is_paused:
                    print(f"\r{C_YELLOW}[已暂停]{C_RESET} 检测已暂停。串口已连接，正在监听... ", end="")
                else:
                    print(f"\r{C_GREEN}[检测中]{C_RESET} 正在发送换行符以进入调试模式... ", end="")
                    ser.write(b'\n')
                time.sleep(0.15)

        except (KeyboardInterrupt, SystemExit):
            raise
        except Exception as e:
            print(f"\n{C_RED}发生未知错误: {e}{C_RESET}")
            if ser and ser.is_open: ser.close()
            current_state = State.RELEASED
            time.sleep(2)

    # 退出前确保串口关闭
    if ser and ser.is_open:
        ser.close()
    print("程序已退出。")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"用法: {sys.argv[0]} <项目文件夹路径 或 .hex文件路径> [串口路径] [波特率]")
        print(f"  示例: {sys.argv[0]} /path/to/MyProject /dev/ttyUSB0 9600")
        sys.exit(1)

    hex_file = find_hex_file(sys.argv[1])
    if not hex_file:
        print(f"{Fore.RED}错误: 无法在 '{sys.argv[1]}' 中找到有效的 .production.hex 文件。{Style.RESET_ALL}")
        sys.exit(1)

    default_serial_path = '/dev/ttyUSB0'
    default_baud_rate = 115200
    serial_path = sys.argv[2] if len(sys.argv) > 2 else default_serial_path
    baud_rate = int(sys.argv[3]) if len(sys.argv) > 3 else default_baud_rate

    try:
        flash_chip_interactive(serial_path, baud_rate, hex_file)
    except (KeyboardInterrupt, SystemExit):
        print("\n\n用户中断，程序退出。")
        sys.exit(0)
'@
Write-FileUtf8 (Join-Path $ProjectPath 'flash_v3.py') $flashPyTemplate
Write-Ok "已生成 flash_v3.py（串口烧录脚本，自动退出）"

# ---------------- 7. 生成 .vscode\tasks.json ----------------
Write-Step "7/8 生成 .vscode 配置（任务 + 按钮 + 调试）..."
$vscodeDir = Join-Path $ProjectPath '.vscode'
if (-not (Test-Path $vscodeDir)) { New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null }

$setupTaskCmd = 'powershell -ExecutionPolicy Bypass -File "${workspaceFolder}\scripts\setup_xc8.ps1"'
$buildCmd  = '& "{0}" -f nbproject/Makefile-default.mk build CONF=default TYPE_IMAGE=production' -f $makeExe
$dbgCmd    = '& "{0}" -f nbproject/Makefile-default.mk build CONF=default TYPE_IMAGE=DEBUG_RUN' -f $makeExe
$cleanCmd  = '& "{0}" -f nbproject/Makefile-default.mk clean CONF=default; if ($LASTEXITCODE -eq 0) {{ & "{0}" -f nbproject/Makefile-default.mk build CONF=default TYPE_IMAGE=production }}' -f $makeExe
$simCmd    = 'powershell -ExecutionPolicy Bypass -File "${workspaceFolder}\scripts\run_simulate.ps1"'
$flashCmd  = 'powershell -ExecutionPolicy Bypass -File "${workspaceFolder}\scripts\run_flash.ps1"'

$srcDesc = if ($sources) { $sources -join ', ' } else { '源文件' }
$tasks = @(
    @{
        label   = 'XC8: 一键配置编译器环境'
        type    = 'shell'
        command = $setupTaskCmd
        options = @{ cwd = '${workspaceFolder}' }
        problemMatcher = @()
        detail  = '自动探测并配置 XC8 编译器路径，重写 Makefile-local-default.mk'
    },
    @{
        label   = 'Build hex (编译生成HEX)'
        type    = 'shell'
        command = $buildCmd
        options = @{ cwd = '${workspaceFolder}' }
        group   = @{ kind = 'build'; isDefault = $true }
        problemMatcher = @()
        detail  = "使用 XC8 编译 $srcDesc 并生成 HEX 固件 (dist/default/production)"
    },
    @{
        label   = 'Build debug ELF (编译调试固件)'
        type    = 'shell'
        command = $dbgCmd
        options = @{ cwd = '${workspaceFolder}' }
        group   = 'build'
        problemMatcher = @()
        detail  = '编译带调试符号的 ELF (dist/default/debug)，供 VS Code 模拟器单步调试使用'
    },
    @{
        label   = 'Clean build (清理并编译)'
        type    = 'shell'
        command = $cleanCmd
        options = @{ cwd = '${workspaceFolder}' }
        group   = 'build'
        problemMatcher = @()
        detail  = '先清理再编译，生成全新 HEX'
    },
    @{
        label   = 'Simulate (仿真)'
        type    = 'shell'
        command = $simCmd
        dependsOn    = 'Build hex (编译生成HEX)'
        dependsOrder = 'sequence'
        options = @{ cwd = '${workspaceFolder}' }
        problemMatcher = @()
        detail  = '先编译生成 HEX，再用 MPLAB X mdb 模拟器仿真并打印寄存器状态'
    },
    @{
        label   = 'Flash (烧录)'
        type    = 'shell'
        command = $flashCmd
        options = @{ cwd = '${workspaceFolder}' }
        problemMatcher = @()
        detail  = '若 HEX 未编译则先编译，再通过串口 Bootloader (flash_v3.py) 烧录到芯片'
    }
)
$tasksJson = @{ version = '2.0.0'; tasks = $tasks } | ConvertTo-Json -Depth 10
Write-FileUtf8 (Join-Path $vscodeDir 'tasks.json') $tasksJson
Write-Ok "已生成 .vscode\tasks.json"

# ---------------- 8. 生成 .vscode\settings.json（Task Buttons） ----------------
$settingsPath = Join-Path $vscodeDir 'settings.json'
$settings = [ordered]@{}
if (Test-Path $settingsPath) {
    try {
        $existing = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $existing.PSObject.Properties) { $settings[$p.Name] = $p.Value }
    } catch { Write-Warn "已有 settings.json 无法解析，将重建: $($_.Exception.Message)" }
}
$settings['VsCodeTaskButtons.showCounter'] = $false
$settings['VsCodeTaskButtons.tasks'] = @(
    @{
        label = '$(tools) 配置XC8'
        task  = 'XC8: 一键配置编译器环境'
        tooltip = '一键配置 XC8 编译器环境（自动探测并修正编译器路径）'
        alignment = 'left'
        color = 'default'
    },
    @{
        label = '$(gear) 编译HEX'
        task  = 'Build hex (编译生成HEX)'
        tooltip = '一键编译源文件并生成 HEX 固件'
        alignment = 'left'
        color = 'default'
    },
    @{
        label = '$(debug-start) 仿真'
        task  = 'Simulate (仿真)'
        tooltip = '使用 MPLAB X 模拟器仿真运行并打印寄存器状态'
        alignment = 'left'
        color = 'warning'
    },
    @{
        label = '$(flame) 烧录'
        task  = 'Flash (烧录)'
        tooltip = '烧录 HEX 到芯片（未编译则先编译，通过串口 Bootloader 烧录）'
        alignment = 'left'
        color = 'error'
    }
)
$settingsJson = $settings | ConvertTo-Json -Depth 10
Write-FileUtf8 $settingsPath $settingsJson
Write-Ok "已生成 .vscode\settings.json（Task Buttons 按钮：配置XC8 / 编译HEX / 仿真 / 烧录）"

# ---------------- 9. 生成 .vscode\launch.json（模拟器单步调试） ----------------
$dfpPath = ''
if ($packName -and $packVersion) {
    $candidate = Join-Path $packsDir "$packVendor\$packName\$packVersion"
    if (Test-Path $candidate) { $dfpPath = $candidate.Replace('\', '/') }
    else {
        # 尝试自动寻找匹配的器件包版本
        $packBase = Join-Path $packsDir "$packVendor\$packName"
        if (Test-Path $packBase) {
            $latest = Get-ChildItem $packBase -Directory | Sort-Object Name -Descending | Select-Object -First 1
            if ($latest) { $dfpPath = $latest.FullName.Replace('\', '/') }
        }
    }
}
if (-not $dfpPath) { Write-Warn "未找到器件包目录，launch.json 将不设置 mdfpPath" }

$launch = @{
    version = '0.2.0'
    configurations = @(
        @{
            name      = "MPLAB 模拟器调试 ($device)"
            type      = 'mplab-core-da'
            request   = 'launch'
            program   = '${workspaceFolder}/dist/default/debug/' + $projName + '.debug.elf'
            device    = $device
            tool      = 'Simulator'
            mprocessor = $device
            stopOnEntry = $true
            preLaunchTask = 'Build debug ELF (编译调试固件)'
        }
    )
}
if ($dfpPath) { $launch.configurations[0].mdfpPath = $dfpPath }
$launchJson = $launch | ConvertTo-Json -Depth 10
Write-FileUtf8 (Join-Path $vscodeDir 'launch.json') $launchJson
Write-Ok "已生成 .vscode\launch.json（VS Code 模拟器单步调试，按 F5 启动）"

# ---------------- 10. 配置编译器并验证编译 ----------------
Write-Step "8/8 配置编译器并验证编译 ..."
$setupScript = Join-Path $ProjectPath 'scripts\setup_xc8.ps1'
$setupArgs = @()
if ($Xc8Root) { $setupArgs += "-Xc8Root `"$Xc8Root`"" }
if ($Xc8Version) { $setupArgs += "-Version $Xc8Version" }
if ($setupArgs.Count -gt 0) {
    & powershell -ExecutionPolicy Bypass -File $setupScript $setupArgs
} else {
    & powershell -ExecutionPolicy Bypass -File $setupScript
}
if ($LASTEXITCODE -ne 0) {
    Write-Err "XC8 环境配置失败，请检查后重试。"
    exit 1
}

Write-Host ""
Write-Host "尝试编译以验证环境 ..." -ForegroundColor Cyan
Push-Location $ProjectPath
& $makeExe -f nbproject/Makefile-default.mk build CONF=default TYPE_IMAGE=production | Out-Host
$buildOk = ($LASTEXITCODE -eq 0)
Pop-Location

# ---------------- 结果汇总 ----------------
Write-Host ""
Write-Host "==================== 初始化完成 ====================" -ForegroundColor Green
Write-Host "  工程        : $projName"
Write-Host "  器件        : $device"
Write-Host "  MPLAB X     : $mplabRoot"
Write-Host "  XC8         : $($chosen.Version) ($($chosen.Bin))"
Write-Host "  编译验证    : $(if ($buildOk) { '成功 ✓' } else { '失败 ✗（可稍后运行 [Build hex] 查看详细错误）' })"
Write-Host ""
Write-Host "  使用方法："
Write-Host "    [环境检测]   先点状态栏 📋环境检测，确认 MPLAB X / XC8 / Python / 调试扩展 就绪"
Write-Host "    [状态栏按钮] 🛠配置XC8 / ⚙编译HEX / ▶仿真 / 🔥烧录"
Write-Host "    [任务面板]   终端 -> 运行任务 -> 选择任务"
Write-Host "    [调试]       F5 启动模拟器单步调试（需安装 MPLAB Debug Adapter 扩展）"
Write-Host "    [烧录]       已自动生成 flash_v3.py（串口 Bootloader 烧录脚本）"
Write-Host "    重启 VS Code 后状态栏按钮生效"
Write-Host "====================================================" -ForegroundColor Green
exit 0
