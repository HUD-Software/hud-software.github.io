function(enable_sanitizer project_name lib_name)
	if(MSVC)
		if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
			get_filename_component(CMAKE_CXX_COMPILER_PATH ${CMAKE_CXX_COMPILER} DIRECTORY)
            if(NOT EXISTS "${CMAKE_CXX_COMPILER_PATH}/clang_rt.asan_dbg_dynamic-x86_64.dll")
                message(FATAL_ERROR "MSVC Address Sanitizer is not installed. Please install the C++ AddressSanitizer with Visual Studio Installer")
            endif()

			# MSVC ASAN is limited
			# https://devblogs.microsoft.com/cppblog/addresssanitizer-asan-for-windows-with-msvc/#compiling-with-asan-from-the-console
			target_compile_options(${project_name} PRIVATE /fsanitize=address /INCREMENTAL:NO)
			target_compile_options(${lib_name} PRIVATE /fsanitize=address /INCREMENTAL:NO)
			# Disable <vector> ASAN Linker verification 
			# https://learn.microsoft.com/en-us/answers/questions/864574/enabling-address-sanitizer-results-in-error-lnk203
			target_compile_definitions(${project_name} PRIVATE _DISABLE_VECTOR_ANNOTATION)
			
			add_custom_command(TARGET ${project_name} POST_BUILD 
				COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CXX_COMPILER_PATH}/clang_rt.asan_dbg_dynamic-x86_64.dll $<TARGET_FILE_DIR:${project_name}>
				COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CXX_COMPILER_PATH}/clang_rt.asan_dynamic-x86_64.dll $<TARGET_FILE_DIR:${project_name}>
				COMMAND $<TARGET_FILE_DIR:${project_name}>/${project_name}.exe
			)

		elseif( CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
			message(FATAL_ERROR "ASAN with Clang-cl is not supported")
			# https://github.com/aminya/project_options/issues/138
			# https://stackoverflow.com/questions/66531482/application-crashes-when-using-address-sanitizer-with-msvc
			# https://devblogs.microsoft.com/cppblog/asan-for-windows-x64-and-debug-build-support/
			# https://learn.microsoft.com/en-us/cpp/sanitizers/asan-runtime?view=msvc-170
		endif()
	elseif( CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
	    # https://developers.redhat.com/blog/2021/05/05/memory-error-checking-in-c-and-c-comparing-sanitizers-and-valgrind
		set(SANTIZE_COMPILE_ARGS 
			-fsanitize=address 
			-fsanitize=undefined 
			-fno-sanitize-recover=all
			-fsanitize=float-divide-by-zero
			-fsanitize=float-cast-overflow 
			-fno-sanitize=null
			-fno-sanitize=alignment
			$<$<CONFIG:Release>:-fno-omit-frame-pointer -g>
			$<$<CONFIG:MinSizeRel>:-fno-omit-frame-pointer -g>
			$<$<CONFIG:RelWithDebInfo>:-fno-omit-frame-pointer>
		)
		target_compile_options(${project_name} PRIVATE ${SANTIZE_COMPILE_ARGS})
		target_link_options(${project_name} PRIVATE ${SANTIZE_COMPILE_ARGS})
		target_compile_options(${lib_name} PRIVATE ${SANTIZE_COMPILE_ARGS})
		target_link_options(${lib_name} PRIVATE ${SANTIZE_COMPILE_ARGS})
	endif()
endfunction() 