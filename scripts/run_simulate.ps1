# ============================================================
#  run_simulate.ps1  —— 使用 MPLAB X 模拟器(mdb)仿真当前固件
# ------------------------------------------------------------
#  功能：
#    1. 检查 HEX 固件是否存在（不存在则提示先编译）
#    2. 自动生成 mdb 仿真脚本（写入 %TEMP%）
#    3. 调用 MPLAB X 的 mdb 模拟器运行仿真
#    4. 在终端中打印关键寄存器状态，验证程序逻辑
# ============================================================

param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$HexFile = Join-Path $ProjectRoot 'dist\default\production\LED_Interupt.production.hex'
$MdbBat  = 'D:\PIC\MPLABX\v6.35\mplab_platform\bin\mdb.bat'
$MdbScript = Join-Path $env:TEMP 'led_interupt_simulate.mdb'

# ---------- 1. 前置检查 ----------
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

# ---------- 2. 生成 mdb 仿真脚本（绝对路径） ----------
$hex = $HexFile.Replace('\', '/')
$mdbContent = @"
# MPLAB X simulator script (auto-generated)
echo /* ============ SIMULATION START: LED interrupt demo (PIC16F18854) ============ */
set device PIC16F18854
set osc none
set simulator "sim"
set voltage 3.3
set poweroptions.resetDelay 100
device PIC16F18854
hwtool sim
echo /* Loading firmware ... */
Program "$hex"
echo /* Firmware loaded. Step 20 instructions to observe initialization */
Stepi 20
print /x LATA
print /x PORTA
print /x TRISA
print /x T0CON0
print /x T0CON1
echo /* Run for a while, then halt, check final state */
Run
Halt
print /x LATA
print /x PORTA
echo /* ============ SIMULATION END ============ */
quit
"@
[System.IO.File]::WriteAllText($MdbScript, $mdbContent, [System.Text.UTF8Encoding]::new($false))

# ---------- 3. 调用 mdb 模拟器 ----------
Write-Host "正在调用 MPLAB X mdb 模拟器 ..." -ForegroundColor Cyan
Write-Host "固件: $HexFile" -ForegroundColor DarkGray
& cmd /c "`"$MdbBat`" `"$MdbScript`""
# mdb 的 quit 命令总是返回非 0 退出码，这里统一按成功处理（仿真结果以输出为准）
exit 0
