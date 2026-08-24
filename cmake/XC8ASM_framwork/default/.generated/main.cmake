include("${CMAKE_CURRENT_LIST_DIR}/rule.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/file.cmake")

set(XC8ASM_framwork_default_library_list )

# Handle files with suffix (s|as|asm|AS|ASM|As|aS|Asm), for group default-XC8
if(XC8ASM_framwork_default_default_XC8_FILE_TYPE_assemble)
add_library(XC8ASM_framwork_default_default_XC8_assemble OBJECT ${XC8ASM_framwork_default_default_XC8_FILE_TYPE_assemble})
    XC8ASM_framwork_default_default_XC8_assemble_rule(XC8ASM_framwork_default_default_XC8_assemble)
    list(APPEND XC8ASM_framwork_default_library_list "$<TARGET_OBJECTS:XC8ASM_framwork_default_default_XC8_assemble>")

endif()

# Handle files with suffix S, for group default-XC8
if(XC8ASM_framwork_default_default_XC8_FILE_TYPE_assemblePreprocess)
add_library(XC8ASM_framwork_default_default_XC8_assemblePreprocess OBJECT ${XC8ASM_framwork_default_default_XC8_FILE_TYPE_assemblePreprocess})
    XC8ASM_framwork_default_default_XC8_assemblePreprocess_rule(XC8ASM_framwork_default_default_XC8_assemblePreprocess)
    list(APPEND XC8ASM_framwork_default_library_list "$<TARGET_OBJECTS:XC8ASM_framwork_default_default_XC8_assemblePreprocess>")

endif()

# Handle files with suffix [cC], for group default-XC8
if(XC8ASM_framwork_default_default_XC8_FILE_TYPE_compile)
add_library(XC8ASM_framwork_default_default_XC8_compile OBJECT ${XC8ASM_framwork_default_default_XC8_FILE_TYPE_compile})
    XC8ASM_framwork_default_default_XC8_compile_rule(XC8ASM_framwork_default_default_XC8_compile)
    list(APPEND XC8ASM_framwork_default_library_list "$<TARGET_OBJECTS:XC8ASM_framwork_default_default_XC8_compile>")

endif()


# Main target for this project
add_executable(XC8ASM_framwork_default_image_VVG9z39a ${XC8ASM_framwork_default_library_list})

set_target_properties(XC8ASM_framwork_default_image_VVG9z39a PROPERTIES
    OUTPUT_NAME "default"
    SUFFIX ".elf"
    ADDITIONAL_CLEAN_FILES "${output_extensions}"
    RUNTIME_OUTPUT_DIRECTORY "${XC8ASM_framwork_default_output_dir}")
target_link_libraries(XC8ASM_framwork_default_image_VVG9z39a PRIVATE ${XC8ASM_framwork_default_default_XC8_FILE_TYPE_link})

# Add the link options from the rule file.
XC8ASM_framwork_default_link_rule( XC8ASM_framwork_default_image_VVG9z39a)


