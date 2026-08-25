;;====================================================================
;; LED_Interupt.asm — PIC16F18854 4位数码管动态显示 + 定时器/外部中断
;; 功能：
;;   1) TMR0 中断：按 Flag 切换 4 种闪烁频率，并点亮/熄灭指示 LED(LATB.4)
;;   2) 外部中断(INT)：Flag 0→1→2→3→0 循环切换
;;   3) 主循环：4 位数码管动态扫描，显示 p1~p4(0~9 数字 + A~Z 字母)
;;====================================================================
#include <xc.inc>

;;--- XC8 汇编器标准段声明(样板，勿删) ---
    psect   init, class=CODE, delta=2
    psect   end_init, class=CODE, delta=2
    psect   powerup, class=CODE, delta=2
    psect   cinit,class=CODE,delta=2
    psect   functab,class=ENTRY,delta=2
    psect   idloc,class=IDLOC,delta=2,noexec
    psect   eeprom_data,class=EEDATA,delta=2,space=3,noexec
    psect   intentry, class=CODE, delta=2
    psect   reset_vec, class=CODE, delta=2

    global _main, reset_vec, start_initialization

;;--- 系统参数常量(EQU)：编译期自动计算 TMR0 重装值 ---
;;   实际公式推导:
;;     FOSC(指令时钟) = HFINTOSC / 4                  → 1MHz
;;     TMR0 输入时钟   = FOSC / 4 = HFINTOSC / 16     → 250kHz
;;                      (硬件: T0CS=FOSC/4(1MHz) × T0CKPS=1:4)
;;     4 位数码管动态扫描 → 定时器溢出频率 = 刷新率 × 4 → 200Hz
;;     (2^16 - 重装值) = TMR0输入时钟 / 溢出频率 = 250000/200 = 1250
;;   → 重装值及其高/低8位全部由汇编器在编译期自动算出
;;
;;   刷新率取值范围(受 16 位重装值限制, 重装值须在 0~65535 内):
;;     重装值 = 65536 - 250000/(刷新率×4)
;;     → 最小值: 刷新率 = 250000/(65536×4) ≈ 0.95Hz   (重装值=0, 满量程 65536 个计数)
;;     → 最大值: 刷新率 = 250000/(1×4)     = 62500Hz  (重装值=65535, 每周期只计 1 个)
;;     → 实用推荐: 30~500Hz (常见 50~120Hz)
HFINTOSC     EQU  4000000   ; 系统振荡频率 4MHz
FOSC         EQU  HFINTOSC / 4      ; 指令时钟 = HFINTOSC/4 = 1MHz
DISP_REFRESH EQU  50        ; 4 位数码管刷新率(Hz, 整屏扫一遍)
DISP_DIGITS  EQU  4         ; 数码管位数(动态扫描)
TMR0_CLK     EQU  FOSC / 4          ; TMR0 输入时钟 = FOSC/4 = 250kHz
TMR0_OVF     EQU  DISP_REFRESH * DISP_DIGITS   ; 溢出频率 = 刷新率×4 = 200Hz
TMR0_TICKS   EQU  TMR0_CLK / TMR0_OVF           ; 每周期计数个数 1250
TMR0_RELOAD  EQU  65536 - TMR0_TICKS            ; 16 位重装值
TMR0_RELOAD_H EQU HIGH TMR0_RELOAD              ; 高 8 位(HIGH 操作符, 自动算出)
TMR0_RELOAD_L EQU LOW  TMR0_RELOAD              ; 低 8 位(LOW 操作符, 自动算出)

;;--- 配置字(CONFIG)：烧录时写入芯片的熔丝位 ---
psect config, class=CONFIG, delta=2
    dw	0xDFEC
    dw	0xF7FF
    dw	0xFFBF
    dw	0xEFFE
    dw	0xFFFF
    
;;--- 复位向量：上电/复位后从 reset_vec 跳转到 _main ---
    psect	reset_vec
reset_vec:
    ljmp	_main
    
    psect cinit
start_initialization:
   
;;--- 变量区(COMMON 公共寄存器，各 bank 均可直接访问) ---
    psect	CommonVar, class=COMMON, space=1, delta=1
    charcase: ds 1h		;预留/暂存单元(本程序未使用)
    p1:    ds 1h		;数码管第1位显示的值(0~9 数字, 10~35 字母 A~Z)
    p2:    ds 1h		;数码管第2位显示的值(0~9 数字, 10~35 字母 A~Z)
    p3:    ds 1h		;数码管第3位显示的值(0~9 数字, 10~35 字母 A~Z)
    p4:    ds 1h		;数码管第4位显示的值(0~9 数字, 10~35 字母 A~Z)
    select_place: ds 1h ;位选第几位数码管
    sys_tick: ds 2h     ;全局可看的系统时钟(16 位: sys_tick 低字节, sys_tick+1 高字节)
    cur_bit: ds 1h     ;sys_tick 第8位当前值(上升沿检测暂存)
    prev_bit: ds 1h    ;sys_tick 第8位上一次的值(0→1 上升沿检测)
    i:     ds 1h
    key_data: ds 1h     ;保存按下时 PORTC 低 4 位数据(供状态机比较)
    key_cnt:  ds 1h     ;按键状态机通用计数(进入各状态清零)
    key_state: ds 1h    ;按键状态机状态(bit0-2=0~5, bit7=1 双击消抖)


    psect intentry
;;=============== 中断服务程序 ISR ===============
intentry:
    ;--- 判断中断源 1：外部中断 INT (PIR0 bit0) ---
    BANKSEL PIR0    ;4us
    BTFSS   PIR0, PIR0_INTF_POSN ;IF=1 是外部中断 → 顺序执行；IF=0 跳到 TMR0 处理
    Goto    TMR0_OP    
    BCF	    PIR0, PIR0_INTF_POSN ;清除外部中断标志
    
    ;--- 外部中断处理： ---
    call handle_int
    RETFIE
    
    ;--- 判断中断源 2：定时器 TMR0 溢出 (PIR0 bit5 / TMR0IF) ---
    TMR0_OP:
    BANKSEL PIR0
    BTFSS   PIR0, PIR0_TMR0IF_POSN ;TMR0IF=1 是 TMR0 中断；否则非本程序中断，直接返回
    RETFIE
    BCF     PIR0, PIR0_TMR0IF_POSN ;清除 TMR0 中断标志

    ;--- 16 位系统时钟 +1 (低字节回绕时高字节进位) ---
    INCF    sys_tick,F
    BTFSC   STATUS, STATUS_Z_POSN   ;低字节从 FF→00 回绕时 Z=1 → 高字节进位
    INCF    sys_tick+1,F

    ;重装 TMR0 初值
    BANKSEL TMR0H
    movlw   TMR0_RELOAD_H   ;重装值高8位(汇编器自动算出)
    movwf   TMR0H
    movlw   TMR0_RELOAD_L   ;重装值低8位(汇编器自动算出)
    movwf   TMR0L

    ;--- 按键扫描 + 状态机：每次 TMR0 中断调用一次(约5ms 采样一次) ---
    ;    识别 10 个按键的单击/双击/长按；同时按下两个键 → 显示 "Err"
    call    button_scan
    
    ;========根据位选变量值跳转到相应显示过程=========

    ;当位选值大于3时清零
    MOVF select_place, W
    ANDLW 0x03
    MOVWF select_place

    BTFSS select_place, 1
    ;这里是0和1
    goto first_two
    ;这里是2和3
    BTFSS select_place, 0
    ;这里是2
    goto display_2
    ;这里是3
    goto display_3
    
    first_two:
    BTFSC select_place, 0
    ;这里是1
    goto display_1
    ;这里是0

    ;======= 第 1 位显示刷新 =======
    display_0:
        movf    p1,W 
        call    seg_table       ;值(0~35) → 段码

        BANKSEL LATB
        bsf	    LATB,3          ;关闭第 3 位(上一个)
        bcf	    LATB,0          ;选中第 1 位(位选)      
        movwf   LATA            ;段码输出到 LATA
        INCF select_place
        retfie
    
    ;======= 第 2 位显示刷新 =======
    display_1:
        movf    p2,W 
        call    seg_table       ;值(0~35) → 段码

        BANKSEL LATB
        bsf	    LATB,0          ;关闭第 3 位(上一个)
        bcf	    LATB,1          ;选中第 1 位(位选)      
        movwf   LATA            ;段码输出到 LATA
        INCF select_place
        retfie
        
    ;======= 第 3 位显示刷新 =======
    display_2:
        movf    p3,W 
        call    seg_table       ;值(0~35) → 段码

        BANKSEL LATB
        bsf	    LATB,1          ;关闭第 3 位(上一个)
        bcf	    LATB,2          ;选中第 1 位(位选)      
        movwf   LATA            ;段码输出到 LATA
        INCF select_place
        retfie
        
    ;======= 第 4 位显示刷新 =======
    display_3:
        movf    p4,W 
        call    seg_table       ;值(0~35) → 段码

        BANKSEL LATB
        bsf	    LATB,2          ;关闭第 3 位(上一个)
        bcf	    LATB,3          ;选中第 1 位(位选)      
        movwf   LATA            ;段码输出到 LATA
        INCF select_place
        retfie
    
psect   main,class=CODE,delta=2 ; PIC10/12/16
    
 global _main
;;=============== 主程序入口 ===============
_main:

    ;=============IO端口初始化=============
    ;关闭RABC模拟输入
    BANKSEL ANSELA
    CLRF    ANSELA  ;关闭 RA 口的模拟功能

    BANKSEL ANSELB
    CLRF    ANSELB  ;关闭 RB 口的模拟功能

    BANKSEL ANSELC
    CLRF    ANSELC  ;关闭 RC 口的模拟功能
    
    ;PORTA 初始化：全设为数字输出
    BANKSEL  LATA
    CLRF     LATA    ;RA 输出锁存清零
    CLRF    TRISA	;RA 全部设为输出

    ;PORTB 初始化：低 4 位(LED/位选)输出，高 3 位输入  
    CLRF     LATB    ;RB 输出锁存清零
    movlw   0b11100000	;bit7-5=1 输入, bit4-0=0 输出(0LED 1234)
    movwf   TRISB

    ;PORTC 初始化：低 4 位弱上拉输入(实时监测电平)，高 4 位输出
    CLRF    LATC     ;RC 输出锁存清零
    BANKSEL TRISC
    movlw   0b00001111   ;bit0-3=输入, bit4-7=输出
    movwf   TRISC
    BANKSEL WPUC
    movlw   0b00001111   ;bit0-3=弱上拉使能
    movwf   WPUC
 
    ;=============定时器初始化=============
    ;时钟：HFINTOSC 设为 4MHz
    BANKSEL OSCFRQ
    movlw   0b00000010
    movwf   OSCFRQ
 
    ;Timer0 配置
    BANKSEL T0CON0
    CLRF    T0CON0  ;先停止 Timer0，稍后启动
    
    BANKSEL T0CON1
    movlw   0b01000000
    movwf   T0CON1  ;T0CS=010(FOSC/4), T0ASYNC, T0CKPS=0000(1:1) → 定时基准
    
    ;===============中断初始化====================
    ;中断在变量初始化完成后开启
    BANKSEL INTCON	
    CLRF    INTCON
    
    ;中断使能：TMR0 中断 + 外部 INT 中断
    BANKSEL PIE0
    CLRF    PIE0
    bsf	    PIE0, PIE0_TMR0IE_POSN ;TMR0IE 使能
    bsf	    PIE0, PIE0_INTE_POSN    ;INTE：外部中断使能
    bcf	    PIR0, PIR0_TMR0IF_POSN  ;清除 TMR0 标志
    
    BANKSEL INTPPS
    movlw   0x0d
    movwf   INTPPS  ;外部中断引脚映射 (INT 接到指定引脚)
    
    ;启动 Timer0 (16位模式)
    BANKSEL T0CON0
    movlw   0b10010000
    movwf   T0CON0  
    
    ;======================变量初始化===========================
    ;变量初始化：显示初值 px=0，select_place=0
    movlw   0x00
    movwf   p1
    movlw   0x00
    movwf   p2
    movlw   0x00
    movwf   p3
    movlw   0x00
    movwf   p4
    CLRF select_place
    CLRF cur_bit
    CLRF prev_bit
    CLRF sys_tick
    CLRF sys_tick+1
    CLRF key_state      ;状态机从 KEY_IDLE 开始
    CLRF key_cnt


    ;--- 清除中断标志，再开启中断 ---
    BANKSEL PIR0
    CLRF    PIR0    ;清所有中断标志
    BANKSEL INTCON
    bsf	    INTCON, INTCON_PEIE_POSN ;PEIE Enable 外设中断使能
    bsf	    INTCON, INTCON_GIE_POSN  ;GIE Enable 全局中断使能
    

    ;===============主循环================
    ;按键扫描+状态机已移入 TMR0 中断(每次中断采样一次)
    main_loop:
    
    goto main_loop  ;空循环
    

;--- 软件分频器：sys_tick 第8位 0→1 上升沿检测 → 触发 tick8_handler ---
tick_divider:
    movf    sys_tick,W
    andlw   0x80
    movwf   cur_bit            ; 当前第8位
    xorwf   prev_bit,W         ; W = 当前^上次
    btfsc   STATUS, STATUS_Z_POSN
    goto    tick_checked       ; 无变化
    btfss   cur_bit, 7         ; 当前位(bit7)=1 才是 0→1 上升沿
    goto    tick_checked
    call    tick_handler       ; 触发函数
tick_checked:
    movf    cur_bit,W
    movwf   prev_bit           ; 更新上次值

;--- sys_tick 第8位 0→1 上升沿触发的函数 ---
tick_handler:
    INCF p1
    movlw   0x24            ; 36
    XORWF   p1, 0
    BTFSC   STATUS, STATUS_Z_POSN
    CLRF    p1              ; p1==36 时回到 0(保持 0~35)
    return

;按键处理
handle_int:
    INCF p2
    return

button_scan:
    movf    key_state, W
    btfsc   STATUS, STATUS_Z_POSN  ;key_state==KEY_IDLE(0) → 重新扫描矩阵
    goto    scan_matrix
    goto    State_machine           ;非空闲 → 直接进状态机

    ;--- 矩阵扫描(仅空闲时进入) ---
    scan_matrix:
    movlw 4
    movwf i

    BANKSEL WPUC
    movlw   0b00001111  ;bit0-3弱上拉输入，bit4-7输出
    movwf   WPUC

    banksel TRISC
    movlw   0b00001111  ;bit0-3弱上拉输入，bit4-7输出
    movwf   TRISC

    movf PORTC,0        ;读取按键电平(按下=0)
    ANDLW 0X0f          ;只保留低 4 位

    ;========= 统计 PORTC 低 i 位中 0 的个数 → 分支 =========
    ;  i = 扫描位数(1~4)；按键按下时对应位为 0
    ;  0 的个数(即按下的按键数)：
    ;    0 个 → 无按键   → no_zero
    ;    1 个 → 单键按下 → one_zero
    ;   ≥2 个 → 多键按下 → to_many_zero
    ;
    ;  算法：nz = mask ^ v (对低 i 位取反)，nz 中 1 的个数 = 零的个数
    ;    nz == 0            → 无零(低 i 位全 1)
    ;    nz 恰好 1 位为 1   → 一个零 (nz≠0 且 (nz&(nz-1))==0)
    ;    否则               → 多个零
    cal_0_num:
    ;--- 1) 保存 v，并按 i 查表得到掩码 mask=(1<<i)-1 ---
    ;    注意：不能用 retlw(它会 RETURN 提前退出本函数)，改为跳转+汇合
    movwf   charcase        ;charcase = v(PORTC 低 4 位)
    movf    i, W            ;i 须在 1~4
    addlw   -1              ;W = i-1 (0~3)
    BRW
    goto    mask_i1
    goto    mask_i2
    goto    mask_i3
    goto    mask_i4
mask_i1:
    movlw   0x01            ;i=1 → 掩码 0b0001
    goto    mask_done
mask_i2:
    movlw   0x03            ;i=2 → 掩码 0b0011
    goto    mask_done
mask_i3:
    movlw   0x07            ;i=3 → 掩码 0b0111
    goto    mask_done
mask_i4:
    movlw   0x0F            ;i=4 → 掩码 0b1111
mask_done:
    ;--- 2) nz = mask ^ v ---
    xorwf   charcase, W     ;W = mask ^ v = nz

    ;--- 3) 按 nz 中 1 的个数分支 ---
    movwf   charcase        ;charcase = nz
    movf    charcase, W
    btfsc   STATUS, STATUS_Z_POSN  ;nz==0 → 无零(低 i 位全 1)
    goto    no_zero
    decf    charcase, W     ;W = nz-1
    andwf   charcase, W     ;W = nz & (nz-1)
    btfsc   STATUS, STATUS_Z_POSN  ;Z=1 → nz 为 2 的幂(恰好 1 位) → 一个零
    goto    one_zero
    goto    to_many_zero    ;否则 → 多个零

    no_zero:
    ;--- 无按键：TRISC/WPUC 逻辑右移切到下一列，i-1 ---
    ;    i != 0 → 重新读 PORTC 再统计下一列(不能沿用 W 残留值!)
    ;    i == 0 → 4 列扫完无按键 → 返回
    banksel TRISC
    lsrf    TRISC, F        ;TRISC 逻辑右移(扫描列切换)
    banksel WPUC
    lsrf    WPUC, F         ;WPUC  逻辑右移(跟上 TRISC)
    decfsz  i, F            ;i = i-1；结果为 0 时跳过下一条
    goto    scan_next       ;i != 0 → 重新读 PORTC
    return                  ;i == 0 → 扫完所有列，返回
scan_next:
    ;右移后必须重新读 PORTC(此时 W 是统计残留值, 不能当 v 用)
    BANKSEL PORTC
    movf    PORTC, W
    ANDLW   0x0F
    goto    cal_0_num       ;重新统计下一列

    to_many_zero:
    ;--- 多个按键同时按下 → 4 位显示 "Err"(末位熄灭) 并返回 ---
    movlw   14              ;索引 14 = 'E'
    movwf   p1
    movlw   27              ;索引 27 = 'R'(表内无小写 r，用 R 近似)
    movwf   p2
    movlw   27              ;索引 27 = 'R'
    movwf   p3
    movlw   36              ;索引 36 = 全灭(第 4 位熄灭)
    movwf   p4
    return

    one_zero:
    ;--- 单键按下：保存本次 PORTC 数据，直接进入消抖状态 ---
    BANKSEL PORTC
    movf    PORTC, W        ;重新读 PORTC(此时 charcase 已被覆盖为 nz)
    ANDLW   0x0F
    movwf   key_data        ;保存按下时的 PORTC 低 4 位
    CLRF    key_cnt         ;按下次数清零(从按下时刻开始计数)
    movlw   KEY_DEBOUNCE    ;直接进入消抖(替代原 FLAG 标记)
    movwf   key_state
    return

    ;--- 按键状态机常量：key_state 的 01 组合区分状态 ---
    ;    bit0-2 = 状态(0~5, 共6个节点), bit7=1 → 消抖为二次(双击)模式
    ;    KEY_DEBOUNCE 被复用两次(首次→DOWN, 二次→DOUBLE_ACTIVE)
KEY_IDLE          EQU 0
KEY_DEBOUNCE      EQU 1
KEY_DOWN          EQU 2
KEY_LONG_ACTIVE   EQU 3
KEY_WAIT_DOUBLE   EQU 4
KEY_DOUBLE_ACTIVE EQU 5

    ;--- 按键状态机：单击/双击/长按 ---
    ;    入口：button_scan 判断 key_state 非空闲(KEY_IDLE)时直接跳这里
    ;    采样：当前有效位与 key_data 完全相同(同一键仍按下) → 视为按下, cnt+1
    ;          否则 → 视为松开/换键
    ;    计数：key_cnt 为通用计数(进入各状态清零)
    ;    事件：WAIT_DOUBLE 第129次超时→单击；进 LONG_ACTIVE→长按；进 DOUBLE_ACTIVE→双击
    ;    结束：回到 KEY_IDLE → 从头开始扫描
    State_machine:
    BANKSEL PORTC
    movf    PORTC, W
    andlw   0x0F
    movwf   charcase        ;charcase = v(PORTC 低4位)
    ;--- 与 key_data 比较：当前有效位 == 按下时有效位(同一键仍按下)才视为"按下" ---
    ;    结果写入 charcase：相同→非0(各状态 cnt+1), 不同→0(视为松开/换键)
    call    key_mask        ;W = mask
    movwf   cur_bit         ;cur_bit = mask
    movf    charcase, W
    andwf   cur_bit, W      ;W = v & mask (当前有效位)
    movwf   charcase        ;charcase = 当前有效位
    movf    key_data, W
    andwf   cur_bit, W      ;W = key_data & mask (按下时有效位)
    subwf   charcase, W     ;W = 当前 - key_data；Z=1 → 完全相同
    btfsc   STATUS, STATUS_Z_POSN
    goto    key_same
    clrf    charcase        ;不同 → charcase=0(各状态按"松开"处理, 不 cnt+1)
    goto    key_cmp_done
key_same:
    movf    cur_bit, W      ;相同 → charcase=非0(mask)(各状态按"按下"处理, cnt+1)
    movwf   charcase
key_cmp_done:
    ;按低3位状态分支
    movf    key_state, W
    andlw   0x07
    BRW
    goto    st_idle           ;0 KEY_IDLE
    goto    st_debounce       ;1 KEY_DEBOUNCE
    goto    st_down           ;2 KEY_DOWN
    goto    st_long_active    ;3 KEY_LONG_ACTIVE
    goto    st_wait_double    ;4 KEY_WAIT_DOUBLE
    goto    st_double_active  ;5 KEY_DOUBLE_ACTIVE

    ;--- KEY_IDLE：空闲。现由 one_zero 直接转入 KEY_DEBOUNCE，此状态不可达，仅占位 ---
    st_idle:
    return

    ;--- KEY_DEBOUNCE(复用)：连续3次按下才有效；<3次回IDLE ---
    st_debounce:
    movf    charcase, W
    btfsc   STATUS, STATUS_Z_POSN   ;松开 → 消抖失败回 IDLE
    goto    debounce_fail
    INCF    key_cnt, F
    movlw   3
    subwf   key_cnt, W              ;W = 3 - key_cnt
    btfss   STATUS, STATUS_Z_POSN   ;未满3次
    return
    ;连续3次按下 → 按 bit7 区分去向
    btfss   key_state, 7            ;bit7=1 → 二次(双击)消抖
    goto    debounce_to_down
    movlw   KEY_DOUBLE_ACTIVE       ;二次消抖成功 → 双击激活
    movwf   key_state
    CLRF    key_cnt
    goto    trigger_double
    debounce_to_down:
    movlw   KEY_DOWN                ;首次消抖成功 → 按下状态
    movwf   key_state
    CLRF    key_cnt
    return
    debounce_fail:
    movlw   KEY_IDLE
    movwf   key_state
    CLRF    key_cnt
    return

    ;--- KEY_DOWN：按下保持。连续256次→长按；松开→等待双击 ---
    st_down:
    movf    charcase, W
    btfsc   STATUS, STATUS_Z_POSN   ;松开
    goto    down_release
    INCF    key_cnt, F
    BTFSC   STATUS, STATUS_Z_POSN   ;key_cnt 255→0(第256次) → 长按
    goto    trigger_long
    return
    down_release:
    CLRF    key_cnt
    movlw   KEY_WAIT_DOUBLE
    movwf   key_state
    return

    ;--- KEY_LONG_ACTIVE：长按已触发。连续3次松开→回IDLE ---
    st_long_active:
    movf    charcase, W
    btfss   STATUS, STATUS_Z_POSN   ;仍按下 → 重置松开计数
    goto    long_still_pressed
    INCF    key_cnt, F
    movlw   3
    subwf   key_cnt, W
    btfss   STATUS, STATUS_Z_POSN
    return
    movlw   KEY_IDLE                ;连续3次松开 → 回待机
    movwf   key_state
    CLRF    key_cnt
    return
    long_still_pressed:
    CLRF    key_cnt
    return

    ;--- KEY_WAIT_DOUBLE：等待双击窗口。128次内再按下→二次消抖；第129次未按下→单击 ---
    st_wait_double:
    movf    charcase, W
    btfss   STATUS, STATUS_Z_POSN   ;检测到再次按下
    goto    wait_double_pressed
    INCF    key_cnt, F              ;窗口计数 +1
    movlw   129
    subwf   key_cnt, W
    btfsc   STATUS, STATUS_Z_POSN   ;第129次仍未按下 → 超时单击
    goto    trigger_click
    return
    wait_double_pressed:
    CLRF    key_cnt
    movlw   KEY_DEBOUNCE | 0x80     ;二次消抖(bit7=1)
    movwf   key_state
    return

    ;--- KEY_DOUBLE_ACTIVE：双击已触发。连续3次松开→回IDLE ---
    st_double_active:
    movf    charcase, W
    btfss   STATUS, STATUS_Z_POSN
    goto    double_still_pressed
    INCF    key_cnt, F
    movlw   3
    subwf   key_cnt, W
    btfss   STATUS, STATUS_Z_POSN
    return
    movlw   KEY_IDLE                ;连续3次松开 → 回待机
    movwf   key_state
    CLRF    key_cnt
    return
    double_still_pressed:
    CLRF    key_cnt
    return

    ;--- 单击事件(WAIT_DOUBLE 第129次超时) ---
    trigger_click:
    call    click_event
    movlw   KEY_IDLE
    movwf   key_state
    CLRF    key_cnt
    return

    ;--- 长按事件(第256次按下) ---
    trigger_long:
    call    long_event
    movlw   KEY_LONG_ACTIVE
    movwf   key_state
    CLRF    key_cnt
    return

    ;--- 双击事件(二次消抖成功) ---
    trigger_double:
    call    double_event
    ;key_state 已是 KEY_DOUBLE_ACTIVE
    CLRF    key_cnt
    return

    ;--- 单击事件处理：1、2位=按键号, 3、4位=DJ(单击) ---
    click_event:
    call    key_number       ;W = 按键号(1~10)
    call    disp_key_num     ;p1=十位(0全灭), p2=个位
    movlw   13              ;'D'
    movwf   p3
    movlw   19              ;'J'
    movwf   p4
    return

    ;--- 双击事件处理：1、2位=按键号, 3、4位=SJ(双击) ---
    double_event:
    call    key_number
    call    disp_key_num
    movlw   28              ;'S'
    movwf   p3
    movlw   19              ;'J'
    movwf   p4
    return

    ;--- 长按事件处理：1、2位=按键号, 3、4位=CA(长按) ---
    long_event:
    call    key_number
    call    disp_key_num
    movlw   12              ;'C'
    movwf   p3
    movlw   10              ;'A'
    movwf   p4
    return

;--- 按 i(1~4) 返回扫描层掩码 mask=(1<<i)-1 ---
;    输出: W = mask
key_mask:
    movf    i, W
    addlw   -1              ;i-1 (0~3)
    BRW
    retlw   0x01            ;i=1 → 0b0001
    retlw   0x03            ;i=2 → 0b0011
    retlw   0x07            ;i=3 → 0b0111
    retlw   0x0F            ;i=4 → 0b1111

;--- 计算当前按键号(1~10)：根据 i 和 key_data(按下位=0) ---
;    i=4: C3→10 C2→9 C1→8 C0→7
;    i=3: C2→6  C1→5  C0→4
;    i=2: C1→3  C0→2
;    i=1: C0→1
;    输入: i(1~4), key_data; 输出: W=按键号
key_number:
    movf    i, W
    addlw   -1              ;i-1 (0~3)
    BRW
    goto    key_i1          ;i=1
    goto    key_i2          ;i=2
    goto    key_i3          ;i=3
    goto    key_i4          ;i=4
key_i4:
    btfss   key_data, 3
    retlw   10
    btfss   key_data, 2
    retlw   9
    btfss   key_data, 1
    retlw   8
    btfss   key_data, 0
    retlw   7
    retlw   0               ;无匹配(不应发生)
key_i3:
    btfss   key_data, 2
    retlw   6
    btfss   key_data, 1
    retlw   5
    btfss   key_data, 0
    retlw   4
    retlw   0
key_i2:
    btfss   key_data, 1
    retlw   3
    btfss   key_data, 0
    retlw   2
    retlw   0
key_i1:
    btfss   key_data, 0
    retlw   1
    retlw   0

;--- 显示按键号(1~10)到数码管1、2位 ---
;    输入: W=按键号; p1=十位(为0时全灭36), p2=个位
disp_key_num:
    movwf   charcase        ;charcase = 按键号
    movlw   10
    subwf   charcase, W     ;W = 10 - n
    btfsc   STATUS, STATUS_Z_POSN  ;n==10
    goto    num_is_10
    movlw   36              ;n<10 → 十位全灭
    movwf   p1
    movf    charcase, W
    movwf   p2              ;个位 = n
    return
num_is_10:
    movlw   1
    movwf   p1              ;十位 = 1
    movlw   0
    movwf   p2              ;个位 = 0
    return

;--- 实时显示 PORTC 低 4 位电平(0/1)到 4 位数码管 ---
;    p1=RC0, p2=RC1, p3=RC2, p4=RC3
;    PORTC 低 4 位须为上拉输入(TRISC=0x0F, WPUC=0x0F)
disp_portc:
    BANKSEL PORTC
    movf    PORTC, W        ;读 PORTC
    andlw   0x0F            ;只留低 4 位
    movwf   charcase        ;暂存

    ;RC0 → p1
    movlw   0
    btfsc   charcase, 0
    movlw   1
    movwf   p1

    ;RC1 → p2
    movlw   0
    btfsc   charcase, 1
    movlw   1
    movwf   p2

    ;RC2 → p3
    movlw   0
    btfsc   charcase, 2
    movlw   1
    movwf   p3

    ;RC3 → p4
    movlw   0
    btfsc   charcase, 3
    movlw   1
    movwf   p4

    return
   

    
;;--- 7段码字形表：值 0~36 → 段码(共阴数码管) ---
;;    输入：W = 值(0~9 数字, 10~35 字母 A~Z, 36=全灭/熄灭)；输出：W = 对应段码
seg_table:
    BRW
    retlw   0x3F    ; 0
    retlw   0x06    ; 1
    retlw   0x5B    ; 2
    retlw   0x4F    ; 3
    retlw   0x66    ; 4
    retlw   0x6D    ; 5
    retlw   0x7D    ; 6
    retlw   0x07    ; 7
    retlw   0x7F    ; 8
    retlw   0x6F    ; 9
    retlw   0x77    ; A
    retlw   0x7C    ; b
    retlw   0x39    ; C
    retlw   0x5E    ; d
    retlw   0x79    ; E
    retlw   0x71    ; F
    retlw   0x3D    ; G
    retlw   0x76    ; H
    retlw   0x06    ; I(≈1)
    retlw   0x1E    ; J
    retlw   0x75    ; K(近似)
    retlw   0x38    ; L
    retlw   0x37    ; M(近似)
    retlw   0x57    ; N(近似)
    retlw   0x3F    ; O(≈0)
    retlw   0x73    ; P
    retlw   0x67    ; Q(近似)
    retlw   0x71    ; R(≈F)
    retlw   0x6D    ; S(≈5)
    retlw   0x78    ; T
    retlw   0x3E    ; U
    retlw   0x3E    ; V(≈U)
    retlw   0x6B    ; W(近似)
    retlw   0x76    ; X(≈H)
    retlw   0x6E    ; Y(近似)
    retlw   0x5B    ; Z(≈2)
    retlw   0x00    ; 36 空白/全灭(熄灭一位)
    RETURN
    
end reset_vec