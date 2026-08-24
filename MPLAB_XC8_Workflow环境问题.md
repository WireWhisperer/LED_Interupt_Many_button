# MPLAB XC8 Workflow 环境检测与初始化问题总结

## 当前结论

MPLAB X 安装完整，`make.exe` 路径有效。最初的报错来自旧的路径探测逻辑或扩展缓存状态，并不是 `make.exe` 缺失。

实际安装目录为：

```text
D:\MAPLAB_X_IDE
```

其中关键文件实际位于：

```text
D:\MAPLAB_X_IDE\gnuBins\GnuWin32\bin\make.exe
D:\MAPLAB_X_IDE\mplab_platform\bin\mdb.bat
D:\MAPLAB_X_IDE\sys\java\zulu8.86.0.25-ca-fx-jre8.0.452-win_x64\bin\java.exe
```

应配置为 MPLAB X 安装根目录：

```text
D:\MAPLAB_X_IDE
```

不要把 `gnuBins\GnuWin32\bin` 作为安装根目录传入；这是 `make.exe` 所在的 bin 目录。

## 问题定位

实际安装采用“根目录直接包含工具目录”的布局：

```text
D:\MAPLAB_X_IDE\gnuBins\GnuWin32\bin\make.exe
```

早期脚本主要假设存在版本子目录，例如 `MPLABX\v6.35`，因此会漏掉当前布局。当前工程中的探测脚本已经加入根目录直接检查，能够识别：

```text
gnuBins\GnuWin32\bin\make.exe
mplab_platform\bin\mdb.bat
```

```text
gnuBins\GnuWin32\bin\make.exe
mplab_platform\bin\mdb.bat
```

## 工程目录

工作区上一级目录是：

```text
D:\MPLAB_Project\4_Number_Horse
```

真正的 MPLAB X 工程目录是：

```text
D:\MPLAB_Project\4_Number_Horse\4_Number_Horse.X
```

只有后者包含：

```text
nbproject\
Makefile
4_Number_Horse.s
```

初始化和任务执行必须使用 `4_Number_Horse.X`，不能使用上一级目录。

## 已验证结果

最近一次验证结果如下：

| 项目 | 结果 |
|---|---|
| MPLAB X | 正常，检测到 `D:\MAPLAB_X_IDE` |
| XC8 编译器 | 正常，检测到 `C:\Program Files\Microchip\xc8` |
| Python 3 | 正常，检测到 `D:\python3.11.4\python.exe` |
| pyserial | 正常 |
| Debug Adapter for MPLAB | 正常 |
| Language Support for MPLAB | 正常 |

另外已直接验证：

| 验证项 | 结果 |
|---|---|
| `make.exe` 文件存在 | 通过，大小 413904 字节 |
| `mdb.bat` 文件存在 | 通过，大小 827 字节 |
| `check_env.ps1 -NoDialogs` | 通过，结果为 `PASS` |
| VS Code `Build hex` 任务 | 通过，HEX 已生成或为最新 |

## 当前工程状态

工程配置中的 MPLAB X 路径已经指向正确的安装根目录：

```text
D:/MAPLAB_X_IDE
```

工程目标器件为：

```text
PIC16LF18854
```

工程使用的工具链为：

```text
pic-as 3.10
```

当前 Makefile 中 XC8/pic-as 路径指向：

```text
C:\Program Files\Microchip\xc8\v3.10\pic-as\bin
```

## 推荐操作

在正确工程目录下执行：

```powershell
cd "D:\MPLAB_Project\4_Number_Horse\4_Number_Horse.X"

powershell -ExecutionPolicy Bypass -File ".\scripts\check_env.ps1" -NoDialogs

`D:\MAPLAB_X_IDE` 是正确的 MPLAB X 路径。重新检测：

```powershell
powershell -ExecutionPolicy Bypass -File ".\scripts\check_env.ps1" -NoDialogs
```

若 VS Code 仍显示旧的“找不到 make.exe”提示，执行“开发人员: 重新加载窗口”，再重新运行环境检测。构建可直接运行工作区任务 `Build hex (编译生成HEX)`。

## 脚本兼容性

当前 `check_env.ps1`、`init_project.ps1` 和 `setup_xc8.ps1` 均包含直接根目录判断，核心逻辑为：

```powershell
if (
    (Test-Path (Join-Path $c 'gnuBins\GnuWin32\bin\make.exe')) -and
    (Test-Path (Join-Path $c 'mplab_platform\bin\mdb.bat'))
) {
    $mplabRoot = $c
}
```

因此同时兼容以下两种布局：

```text
MPLABX\v6.35\gnuBins\GnuWin32\bin\make.exe
MPLAB_X_IDE\gnuBins\GnuWin32\bin\make.exe
```

## 总结

这不是 XC8、Python、pyserial 或 VS Code 官方 MPLAB 扩展缺失导致的问题。当前环境检测和实际构建均已正常完成。后续若再次出现相同提示，应优先检查扩展是否仍持有旧配置或旧缓存，并确认工作区设置中的路径为 `D:\MAPLAB_X_IDE`。
