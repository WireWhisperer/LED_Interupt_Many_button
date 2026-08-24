# ============================================================
#  run_flash.ps1 —— 一键烧录 HEX 到芯片（串口 Bootloader）
# ------------------------------------------------------------
#  功能：
#    1. 检查 HEX 固件是否已编译：
#         - 已编译 → 直接烧录
#         - 未编译 → 先调用 make 编译生成 HEX，再烧录
#    2. 自动检测串口（多个串口时提示选择，或用 -ComPort 指定）
#    3. 调用 python flash_v3.py 通过串口 Bootloader 烧录
#
#  用法：
#    powershell -ExecutionPolicy Bypass -File scripts\run_flash.ps1
#    powershell -ExecutionPolicy Bypass -File scripts\run_flash.ps1 -ComPort COM3
#    powershell -ExecutionPolicy Bypass -File scripts\run_flash.ps1 -ComPort COM3 -BaudRate 115200
#
#  参数：
#    -ComPort   串口号（如 COM3）。省略时：仅有一个串口则自动使用，多个则提示选择
#    -BaudRate  波特率（默认 115200）
# ============================================================
param(
    [string]$ComPort = '',
    [int]$BaudRate = 115200
)
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot

# ---------------- 1. 定位工程相关文件 ----------------
# 工程名（从 MPLAB X 生成的 Makefile 中读取）
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
$MakeExe  = 'D:\PIC\MPLABX\v6.35\gnuBins\GnuWin32\bin\make.exe'

# 校验必要文件
if (-not (Test-Path $FlashPy)) {
    Write-Host "[错误] 未找到烧录脚本: $FlashPy" -ForegroundColor Red
    Write-Host "[提示] 请将 flash_v3.py 放到工程根目录。" -ForegroundColor Yellow
    exit 1
}

# ---------------- 2. 检查 HEX，未编译则先编译 ----------------
Write-Host "==> 检查 HEX 固件 ..." -ForegroundColor Cyan
if (Test-Path $HexFile) {
    Write-Host "    已存在: $HexFile" -ForegroundColor Green
    Write-Host "    直接烧录，跳过编译。" -ForegroundColor Green
} else {
    Write-Host "    未找到: $HexFile" -ForegroundColor Yellow
    Write-Host "    先编译生成 HEX 固件 ..." -ForegroundColor Yellow
    if (-not (Test-Path $MakeExe)) {
        Write-Host "[错误] 未找到 make.exe: $MakeExe" -ForegroundColor Red
        Write-Host "[提示] 请先运行 [配置XC8] 修正编译器路径，或修改本脚本的 MakeExe 变量。" -ForegroundColor Yellow
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

# ---------------- 3. 确定串口 ----------------
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
        for ($i = 0; $i -lt $ports.Count; $i++) {
            Write-Host "      [$i] $($ports[$i])"
        }
        $sel = Read-Host "请输入编号（回车取消）"
        if ($sel -match '^\d+$' -and [int]$sel -lt $ports.Count) {
            $ComPort = $ports[[int]$sel]
        } else {
            Write-Host "[提示] 未选择串口，取消烧录。" -ForegroundColor Yellow
            exit 1
        }
    }
}
Write-Host "    使用串口: $ComPort  @ $BaudRate" -ForegroundColor Green

# ---------------- 4. 调用烧录脚本 ----------------
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
