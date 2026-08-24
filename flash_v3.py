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
                        # After error, go back to OPERATING mode
                        time.sleep(2)
                        continue

                    lines = content_to_flash.splitlines()
                    for i, line in enumerate(lines):
                        ser.write((line + '\n').encode('utf-8'))
                        time.sleep(0.005) # Small delay for chip processing
                        print(f"\r烧录进度: {i+1}/{len(lines)}", end="")

                    print(f"\n{C_GREEN}烧录完成。{C_RESET}")

                    # 清空串口缓冲区，防止残留数据触发再次烧录
                    print(f"{C_YELLOW}清空串口缓冲区...{C_RESET}")
                    ser.read_all()
                    time.sleep(0.5) # Give a moment for any final bytes to arrive
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
