# The following functions contains all the flags passed to the different build stages.

set(PACK_REPO_PATH "C:/Users/zjl/.mchp_packs" CACHE PATH "Path to the root of a pack repository.")

function(XC8ASM_framwork_default_default_XC8_assemble_rule target)
    set(options
        "-c"
        "${MP_EXTRA_AS_PRE}"
        "-mcpu=16F18854"
        "${DEBUGGER_NAME}"
        "-mdfp=${PACK_REPO_PATH}/Microchip/PIC16F1xxxx_DFP/1.31.465/xc8"
        "-fshort-double"
        "-fshort-float"
        "-O0"
        "-fasmfile"
        "-maddrqual=ignore"
        "-mwarn=-3"
        "-Wa,-a"
        "-msummary=-psect,-class,+mem,-hex,-file"
        "-Wl,-Pintentry=04h"
        "-ginhx32"
        "-Wl,--no-data-init"
        "-mkeep-startup"
        "-Wl,-nostartfiles"
        "-mno-osccal"
        "-mno-resetbits"
        "-mno-save-resetbits"
        "-mdownload"
        "-mno-stackcall"
        "-mdefault-config-bits"
        "-std=c90"
        "-gdwarf-3"
        "-mno-const-data-in-config-mapped-progmem"
        "-mstack=compiled:auto:auto")
    list(REMOVE_ITEM options "")
    target_compile_options(${target} PRIVATE "${options}")
    target_compile_definitions(${target}
        PRIVATE "__16F18854__"
        PRIVATE "__DEBUG=1"
        PRIVATE "XPRJ_default=default")
    target_include_directories(${target} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../../..")
endfunction()
function(XC8ASM_framwork_default_default_XC8_assemblePreprocess_rule target)
    set(options
        "-c"
        "${MP_EXTRA_AS_PRE}"
        "-mcpu=16F18854"
        "-x"
        "assembler-with-cpp"
        "-mdfp=${PACK_REPO_PATH}/Microchip/PIC16F1xxxx_DFP/1.31.465/xc8"
        "-fshort-double"
        "-fshort-float"
        "-O0"
        "-fasmfile"
        "-maddrqual=ignore"
        "-mwarn=-3"
        "-Wa,-a"
        "-msummary=-psect,-class,+mem,-hex,-file"
        "-Wl,-Pintentry=04h"
        "-ginhx32"
        "-Wl,--no-data-init"
        "-mkeep-startup"
        "-Wl,-nostartfiles"
        "-mno-osccal"
        "-mno-resetbits"
        "-mno-save-resetbits"
        "-mdownload"
        "-mno-stackcall"
        "-mdefault-config-bits"
        "-std=c90"
        "-gdwarf-3"
        "-mno-const-data-in-config-mapped-progmem"
        "-mstack=compiled:auto:auto")
    list(REMOVE_ITEM options "")
    target_compile_options(${target} PRIVATE "${options}")
    target_compile_definitions(${target}
        PRIVATE "__16F18854__"
        PRIVATE "__DEBUG=1"
        PRIVATE "XPRJ_default=default")
    target_include_directories(${target} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../../..")
endfunction()
function(XC8ASM_framwork_default_default_XC8_compile_rule target)
    set(options
        "-c"
        "${MP_EXTRA_CC_PRE}"
        "-mcpu=16F18854"
        "${DEBUGGER_NAME}"
        "-mdfp=${PACK_REPO_PATH}/Microchip/PIC16F1xxxx_DFP/1.31.465/xc8"
        "-fshort-double"
        "-fshort-float"
        "-O0"
        "-fasmfile"
        "-maddrqual=ignore"
        "-mwarn=-3"
        "-Wa,-a"
        "-msummary=-psect,-class,+mem,-hex,-file"
        "-Wl,-Pintentry=04h"
        "-ginhx32"
        "-Wl,--no-data-init"
        "-mkeep-startup"
        "-Wl,-nostartfiles"
        "-mno-osccal"
        "-mno-resetbits"
        "-mno-save-resetbits"
        "-mdownload"
        "-mno-stackcall"
        "-mdefault-config-bits"
        "-std=c90"
        "-gdwarf-3"
        "-mno-const-data-in-config-mapped-progmem"
        "-mstack=compiled:auto:auto")
    list(REMOVE_ITEM options "")
    target_compile_options(${target} PRIVATE "${options}")
    target_compile_definitions(${target}
        PRIVATE "__16F18854__"
        PRIVATE "__DEBUG=1"
        PRIVATE "XPRJ_default=default")
    target_include_directories(${target} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../../..")
endfunction()
function(XC8ASM_framwork_default_link_rule target)
    set(options
        "-Wl,-Map=mem.map"
        "${MP_EXTRA_LD_PRE}"
        "-mcpu=16F18854"
        "${DEBUGGER_NAME}"
        "-Wl,--defsym=__MPLAB_BUILD=1"
        "-mdfp=${PACK_REPO_PATH}/Microchip/PIC16F1xxxx_DFP/1.31.465/xc8"
        "-fshort-double"
        "-fshort-float"
        "-O0"
        "-fasmfile"
        "-maddrqual=ignore"
        "-mwarn=-3"
        "-Wa,-a"
        "-msummary=-psect,-class,+mem,-hex,-file"
        "-Wl,-Pintentry=04h"
        "-ginhx32"
        "-Wl,--no-data-init"
        "-mkeep-startup"
        "-Wl,-nostartfiles"
        "-mno-osccal"
        "-mno-resetbits"
        "-mno-save-resetbits"
        "-mdownload"
        "-mno-stackcall"
        "-mdefault-config-bits"
        "-std=c90"
        "-gdwarf-3"
        "-mno-const-data-in-config-mapped-progmem"
        "-mstack=compiled:auto:auto"
        "-Wl,--memorysummary,memoryfile.xml")
    list(REMOVE_ITEM options "")
    target_link_options(${target} PRIVATE "${options}")
    target_compile_definitions(${target}
        PRIVATE "__DEBUG=1"
        PRIVATE "XPRJ_default=default")
    target_include_directories(${target} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../../..")
endfunction()
