# The following variables contains the files used by the different stages of the build process.
set(XC8ASM_framwork_default_default_XC8_FILE_TYPE_assemble "${CMAKE_CURRENT_SOURCE_DIR}/../../../helloworld.s")
set_source_files_properties(${XC8ASM_framwork_default_default_XC8_FILE_TYPE_assemble} PROPERTIES LANGUAGE ASM)

# For assembly files, add "." to the include path for each file so that .include with a relative path works
foreach(source_file ${XC8ASM_framwork_default_default_XC8_FILE_TYPE_assemble})
        set_source_files_properties(${source_file} PROPERTIES INCLUDE_DIRECTORIES "$<PATH:NORMAL_PATH,$<PATH:REMOVE_FILENAME,${source_file}>>")
endforeach()

set(XC8ASM_framwork_default_default_XC8_FILE_TYPE_assemblePreprocess)
set_source_files_properties(${XC8ASM_framwork_default_default_XC8_FILE_TYPE_assemblePreprocess} PROPERTIES LANGUAGE ASM)

# For assembly files, add "." to the include path for each file so that .include with a relative path works
foreach(source_file ${XC8ASM_framwork_default_default_XC8_FILE_TYPE_assemblePreprocess})
        set_source_files_properties(${source_file} PROPERTIES INCLUDE_DIRECTORIES "$<PATH:NORMAL_PATH,$<PATH:REMOVE_FILENAME,${source_file}>>")
endforeach()

set(XC8ASM_framwork_default_default_XC8_FILE_TYPE_compile)
set_source_files_properties(${XC8ASM_framwork_default_default_XC8_FILE_TYPE_compile} PROPERTIES LANGUAGE C)
set(XC8ASM_framwork_default_default_XC8_FILE_TYPE_link)
set(XC8ASM_framwork_default_image_name "default.elf")
set(XC8ASM_framwork_default_image_base_name "default")

# The output directory of the final image.
set(XC8ASM_framwork_default_output_dir "${CMAKE_CURRENT_SOURCE_DIR}/../../../out/XC8ASM_framwork")

# The full path to the final image.
set(XC8ASM_framwork_default_full_path_to_image ${XC8ASM_framwork_default_output_dir}/${XC8ASM_framwork_default_image_name})

# Potential output file extensions
set(output_extensions
    .hex
    .hxl
    .mum
    .o
    .sdb
    .sym
    .cmf)
list(TRANSFORM output_extensions PREPEND "${XC8ASM_framwork_default_output_dir}/${XC8ASM_framwork_default_image_base_name}")
