# MPLAB XC8 Workflow

一键完成 MPLAB X 工程的 **XC8 编译器配置 → 编译(HEX) → 仿真 → 烧录** 的 VS Code 扩展。适配华中科技大学Dian团队自研PIC单片机，更适合种子班宝宝体质。

## 功能

- **初始化**：在全新 MPLAB X 工程中一键探测 XC8/MPLAB X、配置编译器、生成状态栏按钮与任务
-  **配置XC8**：自动探测并修正 XC8 编译器路径
-  **编译HEX**：一键编译生成 HEX 固件（未配置时提示先初始化）
- **清理并编译**：先 clean 再编译
- **仿真**：使用 MPLAB X 模拟器 (mdb) 仿真并打印寄存器状态
-  **烧录**：通过串口 Bootloader (flash_v3.py) 烧录 HEX（未编译则先编译）

## 使用方法

1. 安装扩展后，用 VS Code 打开一个 **MPLAB X 工程**（含 `nbproject` 目录）
2. 点击状态栏 **初始化**（或命令面板 `MPLAB XC8: 初始化新工程`）
3. 按提示选择 XC8 版本（多版本时）
4. 初始化会自动：探测工程/配置编译器 → 生成 `scripts/` 与 `.vscode/` 配置 → 验证编译
5. 之后点击状态栏 **编译HEX / 仿真 / 烧录** 即可

> 烧录需要工程根目录存在 `flash_v3.py`（串口 Bootloader 脚本），并在烧录时选择芯片对应的 COM 口、按芯片 RST 键。

## 依赖

- MPLAB X IDE（提供 make.exe 与 mdb 模拟器）
- MPLAB XC8 编译器（v2.x / v3.x / v4.00 均可）
- Python 3 + pyserial（烧录用）
- VS Code 模拟器单步调试需安装官方扩展 `Debug Adapter for MPLAB`（microchip.mplab-core-da）

## 命令

| 命令 | 说明 |
|------|------|
| `MPLAB XC8: 初始化新工程` | 一键初始化（配置编译器/生成按钮/编译/仿真/烧录） |
| `MPLAB XC8: 配置编译器` | 探测并配置 XC8 |
| `MPLAB XC8: 编译生成 HEX` | 编译生成 HEX |
| `MPLAB XC8: 清理并编译` | 清理后重新编译 |
| `MPLAB XC8: 仿真` | 模拟器仿真 |
| `MPLAB XC8: 烧录` | 串口烧录 |

## License

MIT
