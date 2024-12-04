# Help
# - https://docs.teamscale.com/howto/setting-up-profiler-tga/cpp/
# https://gcovr.com/en/6.0/getting-started.html 
#  - Install it with sudo pip install gcovr

# Coverage configuration and build type
set(CMAKE_CXX_FLAGS_COVERAGE "${CMAKE_CXX_FLAGS_DEBUG}" CACHE STRING "Flags used by the C++ compiler during coverage builds.")
set(CMAKE_C_FLAGS_COVERAGE "${CMAKE_C_FLAGS_DEBUG}" CACHE STRING "Flags used by the C compiler during coverage builds.")
set(CMAKE_EXE_LINKER_FLAGS_COVERAGE "${CMAKE_EXE_LINKER_FLAGS_DEBUG}" CACHE STRING "Flags used for linking binaries during coverage builds.")
set(CMAKE_SHARED_LINKER_FLAGS_COVERAGE "${CMAKE_SHARED_LINKER_FLAGS_DEBUG}" CACHE STRING "Flags used by the shared libraries linker during coverage builds.")
mark_as_advanced(
	CMAKE_CXX_FLAGS_COVERAGE
	CMAKE_C_FLAGS_COVERAGE
	CMAKE_EXE_LINKER_FLAGS_COVERAGE
	CMAKE_SHARED_LINKER_FLAGS_COVERAGE)

set(CMAKE_BUILD_TYPE "${CMAKE_BUILD_TYPE}" CACHE STRING "Choose the type of build, options are: None Debug Release RelWithDebInfo MinSizeRel Coverage.")
if(CMAKE_CONFIGURATION_TYPES)
	set(CMAKE_CONFIGURATION_TYPES Debug Release MinSizeRel RelWithDebInfo Coverage)
	set(CMAKE_CONFIGURATION_TYPES "${CMAKE_CONFIGURATION_TYPES}" CACHE STRING "Reset the configurations to what we need" FORCE)
endif()

string(
	APPEND VS_CONFIG
	"$<IF:$<CONFIG:Debug>,"
	"Debug,"
	"$<IF:$<CONFIG:Release>,"
	"Release,"
	"$<IF:$<CONFIG:MinSizeRel>,"
	"MinSizeRel,"
	"$<IF:$<CONFIG:RelWithDebInfo>,"
	"RelWithDebInfo,>>>>"
)

function(enable_coverage project_name lib_name)
if(MSVC)
	if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
		set(MSVC_CODECOVERAGE_CONSOLE_PATH "C:\\Program Files\\Microsoft Visual Studio\\2022\\Enterprise\\Common7\\IDE\\Extensions\\Microsoft\\CodeCoverage.Console\\Microsoft.CodeCoverage.Console.exe" CACHE STRING "Path to Microsoft.CodeCoverage.Console.exe")
		find_program(MSVC_CODECOVERAGE_CONSOLE_EXE ${MSVC_CODECOVERAGE_CONSOLE_PATH})
		if(NOT MSVC_CODECOVERAGE_CONSOLE_EXE)
			message(FATAL_ERROR "Code coverage on Windows need Microsoft.CodeCoverage.Console.exe available in Visual Studio 2022 17.3 Enterprise Edition")
		endif()

		target_link_options(${project_name} PRIVATE /PROFILE)
		
		add_custom_command(
			TARGET ${project_name} POST_BUILD
			COMMAND echo Instrument ${project_name}.exe
			COMMAND ${MSVC_CODECOVERAGE_CONSOLE_EXE} instrument ${VS_CONFIG}/${project_name}.exe 
					--settings ../../coverage.runsettings
		)
		add_custom_command(
			TARGET ${project_name} POST_BUILD
			COMMAND echo Collect ${project_name}.exe
			COMMAND ${MSVC_CODECOVERAGE_CONSOLE_EXE} collect ${VS_CONFIG}/${project_name}.exe 
					--output ${VS_CONFIG}/coverage.msvc.cobertura 
					--output-format cobertura 
					--settings ../../coverage.runsettings
		)
	elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
		target_compile_options(${project_name} PRIVATE -fprofile-instr-generate -fcoverage-mapping)
		target_compile_options(${lib_name} PRIVATE -fprofile-instr-generate -fcoverage-mapping)
		target_link_options(${project_name} PRIVATE --coverage)
		# Add clang lib path to libraries paths
		get_filename_component(CMAKE_CXX_COMPILER_PATH ${CMAKE_CXX_COMPILER} DIRECTORY)
		target_link_directories(${project_name} PRIVATE "${CMAKE_CXX_COMPILER_PATH}\\..\\lib\\clang\\${CMAKE_CXX_COMPILER_VERSION}\\lib\\windows\\")

		add_custom_command( 
		 	TARGET ${project_name} POST_BUILD
			COMMAND echo Download Grcov...
			COMMAND Powershell.exe Invoke-WebRequest -Uri https://github.com/mozilla/grcov/releases/download/v0.8.13/grcov-x86_64-pc-windows-msvc.zip -OutFile ./grcov-x86_64-pc-windows-msvc.zip
			COMMAND Powershell.exe Expand-Archive -Path ./grcov-x86_64-pc-windows-msvc.zip -DestinationPath . -F
		)

		add_custom_command( 
		 	TARGET ${project_name} POST_BUILD
			COMMAND echo Start coverage...
			COMMAND ${CMAKE_COMMAND} -E env LLVM_PROFILE_FILE="${project_name}.profraw" ./${VS_CONFIG}/${project_name}.exe
		)

		add_custom_command( 
			TARGET ${project_name} POST_BUILD
			COMMAND echo Merge coverage info...
			COMMAND ${CMAKE_CXX_COMPILER_PATH}/llvm-profdata merge -sparse ${project_name}.profraw -o ${project_name}.profdata
		)

		add_custom_command( 
			TARGET ${project_name} POST_BUILD
			COMMAND echo Show coverage info...
			COMMAND ${CMAKE_CXX_COMPILER_PATH}/llvm-cov report ./${VS_CONFIG}/${project_name}.exe -instr-profile=${project_name}.profdata -dump
		)

		add_custom_command( 
			TARGET ${project_name} POST_BUILD
			COMMAND echo Show coverage info...
			COMMAND ${CMAKE_CXX_COMPILER_PATH}/llvm-cov show ./${VS_CONFIG}/${project_name}.exe -instr-profile=${project_name}.profdata --show-expansions >> show.txt
		)

		add_custom_command( 
			TARGET ${project_name} POST_BUILD
			COMMAND echo Generate HTML report...
			COMMAND del /s /q coverage.windows.clang.lcov.info # It appears that coverage.windows.clang.lcov.info impact this generation...
			COMMAND ./grcov.exe --llvm -t html -b ./${VS_CONFIG}/ -s ./../../
					--llvm-path ${CMAKE_CXX_COMPILER_PATH}
					--branch
					--keep-only "src/*" 
					--keep-only "interface/*"
					--excl-start "^.*LCOV_EXCL_START.*" 
					--excl-stop "^.*LCOV_EXCL_STOP.*" 
					--excl-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_LINE.*)\"" 
					--excl-br-start "^.*LCOV_EXCL_START.*" 
					--excl-br-stop "^.*LCOV_EXCL_STOP.*" 
					--excl-br-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_BR_LINE.*)\"" 
					-o windows
					..
		)

		add_custom_command( 
			TARGET ${project_name} POST_BUILD
			COMMAND echo Generate LCOV report...
			COMMAND del /s /q coverage.windows.clang.lcov.info
			COMMAND ./grcov.exe --llvm -t lcov -b ./${VS_CONFIG}/ -s ./../../
					--llvm-path ${CMAKE_CXX_COMPILER_PATH}
					--branch
					--keep-only "src/*"
					--keep-only "interface/*"
					--excl-start "^.*LCOV_EXCL_START.*" 
					--excl-stop "^.*LCOV_EXCL_STOP.*" 
					--excl-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_LINE.*)\"" 
					--excl-br-start "^.*LCOV_EXCL_START.*" 
					--excl-br-stop "^.*LCOV_EXCL_STOP.*" 
					--excl-br-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_BR_LINE.*)\"" 
					-o coverage.windows.clang.lcov.info
					..
		)
	endif()
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
	target_compile_options(${project_name} PRIVATE -fprofile-instr-generate -fcoverage-mapping)
	target_link_options(${project_name} PRIVATE -fprofile-instr-generate -fcoverage-mapping)
	target_compile_options(${lib_name} PRIVATE -fprofile-instr-generate -fcoverage-mapping)
	target_link_options(${lib_name} PRIVATE -fprofile-instr-generate -fcoverage-mapping)
	
	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Download Grcov...
		COMMAND curl -L https://github.com/mozilla/grcov/releases/latest/download/grcov-x86_64-unknown-linux-gnu.tar.bz2 | tar jxf -
	)

	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Start coverage...
		COMMAND ${CMAKE_COMMAND} -E env LLVM_PROFILE_FILE="${lib_name}.profraw" ./${project_name}
	)

	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Merge coverage info...
		COMMAND ${CMAKE_CXX_COMPILER_PATH}/llvm-profdata merge ${lib_name}.profraw -o ${lib_name}.profdata
	)

	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Show profraw...
		COMMAND ${CMAKE_CXX_COMPILER_PATH}/llvm-profdata show --all-functions ${lib_name}.profdata >> profraw.info.txt
	)

	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Show coverage info...
		COMMAND rm -f show.txt
		COMMAND ${CMAKE_CXX_COMPILER_PATH}/llvm-cov show ./${project_name} -instr-profile=${lib_name}.profdata --show-expansions >> show.txt
	)


	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Generate HTML report...
		COMMAND rm -f coverage.linux.clang.lcov.info
		COMMAND ./grcov --llvm -t html -b . -s ./../../
				--llvm-path /usr/bin/
				--branch
				--keep-only "src/*" 
				--keep-only "interface/*"
				--excl-start "^.*LCOV_EXCL_START.*" 
				--excl-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_LINE.*)\"" 
				--excl-br-start "^.*LCOV_EXCL_START.*" 
				--excl-br-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-br-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_BR_LINE.*)\"" 
				-o ubuntu
				..
	)

	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Generate LCOV report...
		COMMAND rm -f coverage.linux.clang.lcov.info
		COMMAND ./grcov --llvm -t lcov -b . -s ./../../
				--llvm-path /usr/bin/
				--branch
				--keep-only "src/*"
				--keep-only "interface/*"
				--excl-start "^.*LCOV_EXCL_START.*" 
				--excl-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_LINE.*)\"" 
				--excl-br-start "^.*LCOV_EXCL_START.*" 
				--excl-br-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-br-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_BR_LINE.*)\"" 
				-o coverage.linux.clang.lcov.info
				..
	)
endif()
endfunction()

function(enable_gcov_coverage project_name lib_name)
if(MSVC)
	if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
		set(MSVC_CODECOVERAGE_CONSOLE_PATH "C:\\Program Files\\Microsoft Visual Studio\\2022\\Enterprise\\Common7\\IDE\\Extensions\\Microsoft\\CodeCoverage.Console\\Microsoft.CodeCoverage.Console.exe" CACHE STRING "Path to Microsoft.CodeCoverage.Console.exe")
		find_program(MSVC_CODECOVERAGE_CONSOLE_EXE ${MSVC_CODECOVERAGE_CONSOLE_PATH})
		if(NOT MSVC_CODECOVERAGE_CONSOLE_EXE)
			message(FATAL_ERROR "Code coverage on Windows need Microsoft.CodeCoverage.Console.exe available in Visual Studio 2022 17.3 Enterprise Edition")
		endif()

		target_link_options(${project_name} PRIVATE /PROFILE)
		
		add_custom_command(
			TARGET ${project_name} POST_BUILD
			COMMAND echo Instrument ${project_name}.exe
			COMMAND ${MSVC_CODECOVERAGE_CONSOLE_EXE} instrument ${VS_CONFIG}/${project_name}.exe 
					--settings ../../coverage.runsettings
		)
		add_custom_command(
			TARGET ${project_name} POST_BUILD
			COMMAND echo Collect ${project_name}.exe
			COMMAND ${MSVC_CODECOVERAGE_CONSOLE_EXE} collect ${VS_CONFIG}/${project_name}.exe 
					--output ${VS_CONFIG}/coverage.msvc.cobertura 
					--output-format cobertura 
					--settings ../../coverage.runsettings
		)
	elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
		# Disable compiler batching to fix a clang-cl bug when activate --coverage
		# See: https://developercommunity.visualstudio.com/t/Clang-cl---coverage-option-create-gcno-w/10253777
		set_property(TARGET test_core PROPERTY VS_NO_COMPILE_BATCHING ON)
		set_property(TARGET core PROPERTY VS_NO_COMPILE_BATCHING ON)

		target_compile_options(${project_name} PRIVATE --coverage)
		target_compile_options(${lib_name} PRIVATE --coverage)

		# Add clang lib path to libraries paths
		get_filename_component(CMAKE_CXX_COMPILER_PATH ${CMAKE_CXX_COMPILER} DIRECTORY)
		target_link_directories(${project_name} PRIVATE "${CMAKE_CXX_COMPILER_PATH}\\..\\lib\\clang\\${CMAKE_CXX_COMPILER_PATH}\\lib\\windows\\")
		message("${CMAKE_CXX_COMPILER_PATH}\\..\\lib\\clang\\${CMAKE_CXX_COMPILER_PATH}\\lib\\windows\\")
		# Need to link manually LLVM Bug 40877
		# See: https://bugs.llvm.org/show_bug.cgi?id=40877
		target_link_libraries(test_core PRIVATE "clang_rt.profile-x86_64.lib")


		add_custom_command( 
		 	TARGET ${project_name} POST_BUILD
			COMMAND echo Download Grcov...
			COMMAND Powershell.exe Invoke-WebRequest -Uri https://github.com/mozilla/grcov/releases/download/v0.8.13/grcov-x86_64-pc-windows-msvc.zip -OutFile ./grcov-x86_64-pc-windows-msvc.zip
			COMMAND Powershell.exe Expand-Archive -Path ./grcov-x86_64-pc-windows-msvc.zip -DestinationPath . -F
		)

		add_custom_command( 
		 	TARGET ${project_name} POST_BUILD
			COMMAND echo Start coverage...
			COMMAND ./${VS_CONFIG}/${project_name}.exe
		)

		add_custom_command( 
		 	TARGET ${project_name} POST_BUILD
			COMMAND echo Delete old coverage...
			COMMAND if exist coverage.windows.clang.lcov.info del /s /q coverage.windows.clang.lcov.info
		)

		add_custom_command( 
			TARGET ${project_name} POST_BUILD
			COMMAND echo Generate HTML report...
			COMMAND ./grcov.exe --llvm -t html -b ./${VS_CONFIG}/ -s ./../../
					--llvm-path ${CMAKE_CXX_COMPILER_PATH}
					#--branch
					--keep-only "src/*" 
					--keep-only "interface/*"
					--excl-start "^.*LCOV_EXCL_START.*" 
					--excl-stop "^.*LCOV_EXCL_STOP.*" 
					--excl-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_LINE.*)\"" 
					--excl-br-start "^.*LCOV_EXCL_START.*" 
					--excl-br-stop "^.*LCOV_EXCL_STOP.*" 
					--excl-br-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_BR_LINE.*)\"" 
					-o windows
					..
		)

		add_custom_command( 
			TARGET ${project_name} POST_BUILD
			COMMAND echo Generate LCOV report...
			COMMAND ./grcov.exe --llvm -t lcov -b ./${VS_CONFIG}/ -s ./../../
					--llvm-path ${CMAKE_CXX_COMPILER_PATH}
					#--branch
					--keep-only "src/*"
					--keep-only "interface/*"
					--excl-start "^.*LCOV_EXCL_START.*" 
					--excl-stop "^.*LCOV_EXCL_STOP.*" 
					--excl-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_LINE.*)\"" 
					--excl-br-start "^.*LCOV_EXCL_START.*" 
					--excl-br-stop "^.*LCOV_EXCL_STOP.*" 
					--excl-br-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_BR_LINE.*)\"" 
					-o coverage.windows.clang.lcov.info
					..
		)

	endif()

elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
	# Disable compiler batching to fix a clang-cl bug when activate --coverage
	# See: https://developercommunity.visualstudio.com/t/Clang-cl---coverage-option-create-gcno-w/10253777
	set_property(TARGET test_core PROPERTY VS_NO_COMPILE_BATCHING ON)
	set_property(TARGET core PROPERTY VS_NO_COMPILE_BATCHING ON)

	target_compile_options(${project_name} PRIVATE --coverage)
	target_link_options(${project_name} PRIVATE --coverage)
	target_compile_options(${lib_name} PRIVATE --coverage)

	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Download Grcov...
		COMMAND if [ ! -e grcov ];then (curl -L https://github.com/mozilla/grcov/releases/latest/download/grcov-x86_64-unknown-linux-gnu.tar.bz2 | tar jxf -) fi
	)

	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Start coverage...
		COMMAND ./${project_name}
	)

	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Delete old coverage...
		COMMAND if [ -e coverage.linux.clang.lcov.info ];then (rm coverage.linux.clang.lcov.info) fi
	)

	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Generate HTML report...
		COMMAND ./grcov --llvm -t html -b . -s ./../../
				--llvm-path /usr/bin/
				#--branch
				--keep-only "src/*" 
				--keep-only "interface/*"
				--excl-start "^.*LCOV_EXCL_START.*" 
				--excl-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_LINE.*)\"" 
				--excl-br-start "^.*LCOV_EXCL_START.*" 
				--excl-br-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-br-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_BR_LINE.*)\"" 
				-o linux.clang
				..
	)

	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Generate LCOV report...
		COMMAND ./grcov --llvm -t lcov -b . -s ./../../
				--llvm-path /usr/bin/
				#--branch
				--keep-only "src/*"
				--keep-only "interface/*"
				--excl-start "^.*LCOV_EXCL_START.*" 
				--excl-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_LINE.*)\"" 
				--excl-br-start "^.*LCOV_EXCL_START.*" 
				--excl-br-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-br-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_BR_LINE.*)\"" 
				-o coverage.linux.clang.lcov.info
				..
	)
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
	# # Disable compiler batching to fix a clang-cl bug when activate --coverage
	# # See: https://developercommunity.visualstudio.com/t/Clang-cl---coverage-option-create-gcno-w/10253777
	# set_property(TARGET test_core PROPERTY VS_NO_COMPILE_BATCHING ON)
	# set_property(TARGET core PROPERTY VS_NO_COMPILE_BATCHING ON)

	target_compile_options(${project_name} PRIVATE --coverage)
	target_link_options(${project_name} PRIVATE --coverage)
	target_compile_options(${lib_name} PRIVATE --coverage)
	
	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Download Grcov...
		COMMAND if [ ! -e grcov ];then (curl -L https://github.com/mozilla/grcov/releases/latest/download/grcov-x86_64-unknown-linux-gnu.tar.bz2 | tar jxf -) fi
	)
	
	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Start coverage...
		COMMAND ./${project_name}
	)

	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Generate HTML report...
		COMMAND ./grcov -t html -b . -s ./../../
				--llvm-path /usr/bin/
				#--branch
				--keep-only "src/*" 
				--keep-only "interface/*"
				--excl-start "^.*LCOV_EXCL_START.*" 
				--excl-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_LINE.*)\"" 
				--excl-br-start "^.*LCOV_EXCL_START.*" 
				--excl-br-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-br-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_BR_LINE.*)\"" 
				-o linux.gcc
				..
	)
	add_custom_command( 
		TARGET ${project_name} POST_BUILD
		COMMAND echo Generate LCOV report...
		COMMAND ./grcov -t lcov -b . -s ./../../
				--llvm-path /usr/bin/
				#--branch
				--keep-only "src/*"
				--keep-only "interface/*"
				--excl-start "^.*LCOV_EXCL_START.*" 
				--excl-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_LINE.*)\"" 
				--excl-br-start "^.*LCOV_EXCL_START.*" 
				--excl-br-stop "^.*LCOV_EXCL_STOP.*" 
				--excl-br-line "\"(\\s*^.*GTEST_TEST\\.*)|(^.*LCOV_EXCL_BR_LINE.*)\"" 
				-o coverage.linux.gcc.lcov.info
				..
	)

	# set(GCOV_FILEPATH "/usr/bin/gcov-12")
    # add_custom_command( 
	# 	TARGET ${project_name} POST_BUILD
	# 	COMMAND echo Generate HTML report...
	# 	COMMAND lcov --capture --directory . --output-file coverage.linux.clang.lcov.info
	# )

	

endif()
endfunction()
