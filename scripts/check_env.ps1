# ============================================================
#  check_env.ps1 —— MPLAB XC8 环境检测
# ------------------------------------------------------------
#  检测以下依赖并给出处理建议：
#    1. MPLAB X（make.exe）         缺失 → 文件夹选择器选择目录
#    2. XC8 编译器（xc8-cc.exe）    缺失 → 文件夹选择器选择目录
#    3. Python 3（python.exe）      缺失 → 文件选择器选择 python.exe 路径
#    4. pyserial 库                 缺失 → 提醒 pip install pyserial
#    5. Debug Adapter for MPLAB 扩展 缺失 → 提醒安装 microchip.mplab-core-da
#    6. Language Support for MPLAB  缺失 → 提醒安装 microchip.mplab-clangd（语法高亮）
#  结束后会将结果写入 <工程>/.mplab_xc8_env_result（PASS/FAIL），供扩展读取。
#  用法：
#    powershell -ExecutionPolicy Bypass -File scripts\check_env.ps1
#    （-NoDialogs：由扩展调用时跳过 WinForms 弹窗，改为扩展侧用 VS Code 原生对话框引导）
# ============================================================
param(
    [switch]$SkipPrompts,
    [switch]$NoDialogs
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# 出错时兜底：把结果写成 FAIL，避免扩展等待超时
trap {
    try { Set-Content -Path (Join-Path $ProjectRoot '.mplab_xc8_env_result') -Value 'FAIL' -Encoding UTF8 } catch { }
    Write-Host "环境检测出错: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Write-Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-No($m)   { Write-Host "  [缺] $m" -ForegroundColor Red }
function Write-Warn($m) { Write-Host "  [提示] $m" -ForegroundColor Yellow }

# 弹出文件夹选择器（需 STA 线程）
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

# 弹出文件选择器（需 STA 线程），如选择 python.exe
function Show-FilePicker($title, $filter) {
    $script:fileResult = $null
    $thread = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $fd = New-Object System.Windows.Forms.OpenFileDialog
        $fd.Title = $title
        $fd.Filter = $filter
        $fd.CheckFileExists = $true
        if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:fileResult = $fd.FileName
        }
    })
    $thread.SetApartmentState([System.Threading.ApartmentState]::STA)
    $thread.Start()
    $thread.Join()
    return $script:fileResult
}

Write-Host ""
Write-Host "========== MPLAB XC8 环境检测 ==========" -ForegroundColor Cyan

# ---------------- 1. MPLAB X ----------------
Write-Host ""
Write-Host "--- [1/6] MPLAB X (make.exe) ---" -ForegroundColor Cyan
$mplabRoot = $null
$mplabCands = @()
if ($env:MPLABX_PATH) { $mplabCands += $env:MPLABX_PATH }
foreach ($p in ($env:PATH -split ';')) {
    if ($p -and (Test-Path (Join-Path $p 'make.exe'))) { $mplabCands += (Split-Path (Split-Path (Split-Path $p -Parent) -Parent) -Parent) }
}
$mplabCands += 'D:\PIC\MPLABX', 'C:\Program Files\Microchip\MPLABX', 'C:\Program Files (x86)\Microchip\MPLABX', 'D:\Program Files\Microchip\MPLABX'
foreach ($c in ($mplabCands | Select-Object -Unique)) {
    if (-not $c -or -not (Test-Path $c)) { continue }
    $c = $c.TrimEnd('\')
    # 兼容根目录直接布局：如 D:\MAPLAB_X_IDE\gnuBins\GnuWin32\bin\make.exe
    if (Test-Path (Join-Path $c 'gnuBins\GnuWin32\bin\make.exe')) { $mplabRoot = $c; break }
    $vers = Get-ChildItem $c -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^v?\d+\.\d+' } | Sort-Object Name -Descending
    foreach ($v in $vers) {
        if (Test-Path (Join-Path $v.FullName 'gnuBins\GnuWin32\bin\make.exe')) { $mplabRoot = $v.FullName; break }
    }
    if ($mplabRoot) { break }
}

if ($mplabRoot) {
    Write-Ok "MPLAB X: $mplabRoot"
} else {
    Write-No "未找到 MPLAB X（make.exe）。"
    if (-not $NoDialogs) {
        $picked = Show-FolderPicker '请选择 MPLAB X 安装目录（含版本子目录，如 v6.35）'
        if ($picked -and (Test-Path $picked)) {
            foreach ($v in (Get-ChildItem $picked -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^v?\d+\.\d+' } | Sort-Object Name -Descending)) {
                if (Test-Path (Join-Path $v.FullName 'gnuBins\GnuWin32\bin\make.exe')) { $mplabRoot = $v.FullName; break }
            }
            if ($mplabRoot) { Write-Ok "已通过选择器指定 MPLAB X: $mplabRoot" }
        }
    }
    if (-not $mplabRoot) { Write-Warn "请到 https://www.microchip.com/mplabx 下载安装 MPLAB X IDE，或在扩展弹窗中选择安装目录。" }
}

# ---------------- 2. XC8 ----------------
Write-Host ""
Write-Host "--- [2/6] XC8 编译器 ---" -ForegroundColor Cyan
$xc8Root = $null
$xc8Cands = @()
if ($env:XC8_ROOT) { $xc8Cands += $env:XC8_ROOT }
foreach ($p in ($env:PATH -split ';')) {
    if ($p -and (Test-Path (Join-Path $p 'xc8-cc.exe'))) {
        $vdir = Split-Path -Parent $p
        if ((Split-Path -Leaf $vdir) -match '^v?\d+\.\d+$') { $xc8Cands += (Split-Path -Parent $vdir) } else { $xc8Cands += $vdir }
    }
}
$xc8Cands += 'D:\PIC\xc8', 'C:\Program Files\Microchip\xc8', 'C:\Program Files (x86)\Microchip\xc8', 'D:\Program Files\Microchip\xc8'
foreach ($c in ($xc8Cands | Select-Object -Unique)) {
    if (-not $c -or -not (Test-Path $c)) { continue }
    $c = $c.TrimEnd('\')
    $vers = Get-ChildItem $c -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^v?\d+\.\d+' } | Sort-Object Name -Descending
    foreach ($v in $vers) {
        $bin = Join-Path $v.FullName 'bin'
        # 兼容 xc8-cc.exe（C 编译器）与 pic-as.exe（汇编工具链）
        if ((Test-Path (Join-Path $bin 'xc8-cc.exe')) -or (Test-Path (Join-Path $v.FullName 'xc8-cc.exe')) -or (Test-Path (Join-Path $v.FullName 'pic-as\bin\pic-as.exe'))) { $xc8Root = $c; break }
    }
    if ($xc8Root) { break }
}
if ($xc8Root) {
    Write-Ok "XC8 编译器: $xc8Root"
} else {
    Write-No "未找到 XC8 编译器（xc8-cc.exe）。"
    if (-not $NoDialogs) {
        $picked = Show-FolderPicker '请选择 XC8 根目录（含版本子目录，如 D:\PIC\xc8）'
        if ($picked -and (Test-Path $picked)) { $xc8Root = $picked; Write-Ok "已通过选择器指定 XC8: $xc8Root" }
    }
    if (-not $xc8Root) { Write-Warn "请到 https://www.microchip.com/mplabxc8 下载安装 XC8 编译器，或在扩展弹窗中选择安装目录。" }
}

# ---------------- 3. Python 3 ----------------
Write-Host ""
Write-Host "--- [3/6] Python 3 ---" -ForegroundColor Cyan
$pyPath = $null
foreach ($cand in @('python', 'python3', 'py')) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { $pyPath = $cmd.Source; break }
}
if (-not $pyPath) {
    foreach ($base in @("$env:LOCALAPPDATA\Programs\Python", "$env:ProgramFiles\Python312", "$env:ProgramFiles\Python311", "$env:ProgramFiles\Python310", "$env:ProgramFiles\Python39", 'C:\Python312', 'C:\Python311', 'C:\Python310', 'C:\Python39')) {
        if (Test-Path $base) {
            $exe = Get-ChildItem $base -Recurse -Filter 'python.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exe) { $pyPath = $exe.FullName; break }
        }
    }
}
if ($pyPath) {
    Write-Ok "Python 3: $pyPath"
} else {
    Write-No "未找到 Python 3。"
    if (-not $SkipPrompts -and -not $NoDialogs) {
        $picked = Show-FilePicker '请选择 python.exe' 'Python 可执行文件 (*.exe)|python.exe'
        if ($picked -and (Test-Path $picked)) { $pyPath = $picked; Write-Ok "已指定 Python: $pyPath" }
    }
    if (-not $NoDialogs -and -not $pyPath) {
        $manual = Read-Host "请手动输入 python.exe 完整路径（回车跳过）"
        if ($manual -and (Test-Path $manual)) { $pyPath = $manual; Write-Ok "已指定 Python: $pyPath" }
    }
    if (-not $pyPath) { Write-Warn "请到 https://www.python.org/downloads/ 安装 Python 3，或在扩展弹窗中选择 python.exe。" }
}

# ---------------- 4. pyserial ----------------
Write-Host ""
Write-Host "--- [4/6] pyserial 库 ---" -ForegroundColor Cyan
$serialOk = $false
if ($pyPath) {
    try { & $pyPath -c "import serial" 2>$null; if ($LASTEXITCODE -eq 0) { $serialOk = $true } } catch { }
}
if ($serialOk) {
    Write-Ok "pyserial 库: 已安装"
} else {
    Write-No "未检测到 pyserial 库。"
    Write-Warn "请运行：  pip install pyserial    或    $pyPath -m pip install pyserial"
}

# ---------------- 5. Debug Adapter for MPLAB ----------------
Write-Host ""
Write-Host "--- [5/6] Debug Adapter for MPLAB 扩展 ---" -ForegroundColor Cyan
$daOk = $false
$extDir = Join-Path $env:USERPROFILE '.vscode\extensions'
if (Test-Path $extDir) {
    $daOk = @(Get-ChildItem $extDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'microchip.mplab-core-da*' }).Count -gt 0
}
if ($daOk) {
    Write-Ok "Debug Adapter for MPLAB: 已安装"
} else {
    Write-No "未安装官方扩展 Debug Adapter for MPLAB（microchip.mplab-core-da）。"
    Write-Warn "扩展将弹出窗口询问是否自动安装；也可手动运行：code --install-extension microchip.mplab-core-da"
    Write-Warn "该扩展用于 VS Code 模拟器单步调试（按 F5）。"
}

# ---------------- 6. Language Support for MPLAB（语法高亮） ----------------
Write-Host ""
Write-Host "--- [6/6] Language Support for MPLAB 扩展 ---" -ForegroundColor Cyan
$langOk = $false
if (Test-Path $extDir) {
    $langOk = @(Get-ChildItem $extDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'microchip.mplab-clangd*' }).Count -gt 0
}
if ($langOk) {
    Write-Ok "Language Support for MPLAB: 已安装"
} else {
    Write-No "未安装 Language Support for MPLAB（microchip.mplab-clangd）。"
    Write-Warn "扩展将弹出窗口询问是否自动安装；也可手动运行：code --install-extension microchip.mplab-clangd"
    Write-Warn "该扩展提供汇编/C 语法高亮、代码补全。"
}

# ---------------- 汇总 ----------------
Write-Host ""
Write-Host "=================== 环境检测完成 ===================" -ForegroundColor Green
Write-Host "  MPLAB X        : $(if ($mplabRoot) { 'OK' } else { '缺失' })"
Write-Host "  XC8 编译器     : $(if ($xc8Root) { 'OK' } else { '缺失' })"
Write-Host "  Python 3       : $(if ($pyPath) { 'OK' } else { '缺失' })"
Write-Host "  pyserial       : $(if ($serialOk) { 'OK' } else { '缺失' })"
Write-Host "  MPLAB 调试扩展 : $(if ($daOk) { 'OK' } else { '缺失' })"
Write-Host "  语言支持扩展   : $(if ($langOk) { 'OK' } else { '缺失' })"
Write-Host "====================================================" -ForegroundColor Green

# 将结果写入结果文件，供扩展等待/读取（关键依赖 MPLAB X + XC8 均就绪才算 PASS）
# 格式：
#   第一行: PASS/FAIL
#   第二行: 缺失项列表（逗号分隔，如 mplab,xc8,python,serial,da,lang）
#   第三行: 检测到的 MPLAB X 路径（可能为空）
#   第四行: 检测到的 XC8 路径（可能为空）
$resultFile = Join-Path $ProjectRoot '.mplab_xc8_env_result'
$missing = @()
if (-not $mplabRoot) { $missing += 'mplab' }
if (-not $xc8Root) { $missing += 'xc8' }
if (-not $pyPath) { $missing += 'python' }
if (-not $serialOk) { $missing += 'serial' }
if (-not $daOk) { $missing += 'da' }
if (-not $langOk) { $missing += 'lang' }
$resultLines = @()
if ($mplabRoot -and $xc8Root) { $resultLines += 'PASS' } else { $resultLines += 'FAIL' }
if ($missing.Count -gt 0) { $resultLines += ($missing -join ',') } else { $resultLines += '' }
$resultLines += $mplabRoot
$resultLines += $xc8Root
Set-Content -Path $resultFile -Value $resultLines -Encoding UTF8
exit 0
