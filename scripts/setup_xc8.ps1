# ============================================================
#  setup_xc8.ps1  —— 一键配置 MPLAB XC8 编译器环境
# ------------------------------------------------------------
#  功能：
#    1. 自动探测 XC8 安装目录（支持 D:\PIC\xc8、标准安装路径、环境变量）
#    2. 自动选择已安装的最新版本
#    3. 重写 nbproject/Makefile-local-default.mk，把编译器路径指向真实安装版本
#    4. 同步更新 nbproject/configurations.xml 中的工具链版本号
#    5. 将 XC8 bin 加入当前会话 PATH，方便命令行直接调用 xc8-cc / pic-as
#  用法：
#    powershell -ExecutionPolicy Bypass -File scripts\setup_xc8.ps1
#    （幂等，可重复执行）
# ============================================================

param(
    [string]$Xc8Root = $env:XC8_ROOT
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$MakefileLocal = Join-Path $ProjectRoot 'nbproject\Makefile-local-default.mk'
$ConfigXml     = Join-Path $ProjectRoot 'nbproject\configurations.xml'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    WARN: $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "    ERROR: $msg" -ForegroundColor Red }

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

# ---------------- 1. 探测 XC8 安装目录 ----------------
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
# 注册表中查找 MPLAB XC8 安装信息
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

# 过滤出真正存在且含版本子目录的 XC8 根目录
$foundRoot = $null
foreach ($c in $candidates) {
    $c = $c.TrimEnd('\')
    if (!$c) { continue }
    if (Test-Path $c) {
        # 判断是否为根目录（内含版本子目录，如 v3.10 / v4.00）
        $verDirs = Get-ChildItem -Path $c -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^v?\d+\.\d+' }
        if ($verDirs) {
            $foundRoot = $c
            Write-Ok "发现 XC8 根目录: $foundRoot"
            break
        }
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

# ---------------- 2. 选择最新版本 ----------------
Write-Step "2/4 选择已安装的 XC8 版本 ..."
$versionDirs = Get-ChildItem -Path $foundRoot -Directory |
               Where-Object { $_.Name -match '^v?\d+\.\d+' } |
               Sort-Object Name -Descending

if (-not $versionDirs) {
    Write-Err "在 $foundRoot 下未找到版本目录（如 v4.00）。"
    exit 1
}

# 优先匹配 <版本>\bin\xc8-cc.exe，兼容 <版本>\xc8-cc.exe 两种结构
$selected = $null
$Xc8Bin = $null
foreach ($vd in $versionDirs) {
    $binDir = Join-Path $vd.FullName 'bin'
    if (Test-Path (Join-Path $binDir 'xc8-cc.exe')) {
        $selected = $vd
        $Xc8Bin = $binDir
        break
    }
}
if (-not $selected) {
    # 兼容旧版结构 xc8\<版本>\xc8-cc.exe（编译器直接位于版本目录下）
    foreach ($vd in $versionDirs) {
        if (Test-Path (Join-Path $vd.FullName 'xc8-cc.exe')) {
            $selected = $vd
            $Xc8Bin = $vd.FullName
            break
        }
    }
}

if (-not $selected) {
    # 兼容汇编工具链 pic-as（如 v3.10\pic-as\bin\pic-as.exe）
    foreach ($vd in $versionDirs) {
        $picBin = Join-Path $vd.FullName 'pic-as\bin'
        if (Test-Path (Join-Path $picBin 'pic-as.exe')) {
            $selected = $vd
            $Xc8Bin = $picBin
            break
        }
    }
}

if (-not $selected) {
    Write-Err "未在任何版本目录中找到 xc8-cc.exe / pic-as.exe。请检查 XC8 安装是否完整。"
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

# ---------------- 3. 更新/生成 Makefile-local-default.mk ----------------
Write-Step "3/4 更新 Makefile-local-default.mk ..."

$escapedBin = $Xc8Bin.Replace('\', '\\')

if (Test-Path $MakefileLocal) {
    $content = Get-Content $MakefileLocal -Raw

    # 找出当前引用的旧 XC8 目录（如 D:\PIC\xc8\v3.10\bin），并替换为新的
    $oldPathRegex = 'D:\\?[^"]*?\\xc8[^"\\]*(?:\\[^"\\]+)*\\bin'
    if ($content -match $oldPathRegex) {
        $oldPath = $Matches[0] -replace '\\\\', '\'
        Write-Ok "检测到旧路径: $oldPath"
        $content = $content.Replace($oldPath, $Xc8Bin)
    } else {
        # 未匹配到可替换的旧路径，直接整体重写关键变量
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

# ---------------- 4. 同步 configurations.xml 版本号 ----------------
Write-Step "4/4 同步工具链版本号到 configurations.xml ..."
if (Test-Path $ConfigXml) {
    $xml = Get-Content $ConfigXml -Raw -Encoding UTF8
    if ($xml -match '<languageToolchainVersion>[^<]*</languageToolchainVersion>') {
        $xml = $xml -replace '<languageToolchainVersion>[^<]*</languageToolchainVersion>',
                            "<languageToolchainVersion>$Xc8Version</languageToolchainVersion>"
        Set-Content -Path $ConfigXml -Value $xml -Encoding UTF8
        Write-Ok "configurations.xml 工具链版本已更新为 $Xc8Version"
    }
} else {
    Write-Warn "未找到 configurations.xml，跳过（不影响 make 构建）"
}

# 将 XC8 bin 加入当前进程 PATH（仅本次会话，不影响系统）
$env:PATH = "$Xc8Bin;$env:PATH"
Write-Ok "已将 $Xc8Bin 加入本次会话 PATH"

# ---------------- 结果输出 ----------------
Write-Host ""
Write-Host "=================== XC8 环境配置完成 ===================" -ForegroundColor Green
Write-Host "  XC8 根目录 : $foundRoot"
Write-Host "  版本        : $Xc8Version"
Write-Host "  编译器      : $Xc8Cc"
Write-Host "  下一步      : 运行 [Build hex] 任务编译生成 HEX 固件"
Write-Host "=========================================================" -ForegroundColor Green
exit 0
