cmake_minimum_required(VERSION 3.20)
project(wawbf LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(WAWBF_BUILD_TESTS "Build the platform-neutral protocol tests" ON)

# Header-only, platform-neutral pieces shared by everything.
add_library(wawbf_protocol INTERFACE)
target_include_directories(wawbf_protocol INTERFACE protocol common)

if(WIN32)
  # Both games are 32-bit, so the bridges must be too.
  if(NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
    message(FATAL_ERROR "Configure a 32-bit build: cmake -B build -A Win32")
  endif()

  # Static runtime so players don't need a VC++ redistributable.
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

  add_library(wawbf_common STATIC
    common/callhook.cpp
    common/config.cpp
    common/crashlog.cpp
    common/frameprobe.cpp
    common/log.cpp
    common/memory.cpp
    common/overlay.cpp
    common/pad.cpp
    common/shm.cpp)
  target_link_libraries(wawbf_common PUBLIC wawbf_protocol)
  target_compile_definitions(wawbf_common PUBLIC WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
  if(MINGW)
    target_link_options(wawbf_common INTERFACE -static -Wl,--enable-stdcall-fixup)
  endif()

  # One d3d9.dll proxy per game, each in its own output folder. The $<1:...>
  # wrapper stops Visual Studio generators appending a per-config subfolder,
  # so outputs land where docs/PHASE0.md says for every generator.
  function(wawbf_bridge target game_dir)
    add_library(${target} SHARED
      ${game_dir}/src/main.cpp
      common/proxy_d3d9.cpp
      common/d3d9.def)
    target_link_libraries(${target} PRIVATE wawbf_common)
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME d3d9
      PREFIX ""
      RUNTIME_OUTPUT_DIRECTORY $<1:${CMAKE_BINARY_DIR}/out/${game_dir}>
      LIBRARY_OUTPUT_DIRECTORY $<1:${CMAKE_BINARY_DIR}/out/${game_dir}>)
  endfunction()

  wawbf_bridge(wawbf_waw waw)
  wawbf_bridge(wawbf_swbf2 swbf2)
  target_sources(wawbf_swbf2 PRIVATE swbf2/src/focus.cpp swbf2/src/input.cpp swbf2/src/sound.cpp swbf2/src/devices.cpp)

  add_executable(wawbf_monitor tools/monitor/main.cpp)
  target_link_libraries(wawbf_monitor PRIVATE wawbf_protocol)
  target_compile_definitions(wawbf_monitor PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  if(MINGW)
    target_link_options(wawbf_monitor PRIVATE -static)
  endif()
  set_target_properties(wawbf_monitor PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY $<1:${CMAKE_BINARY_DIR}/out/tools>)
endif()

if(WAWBF_BUILD_TESTS)
  enable_testing()
  find_package(Threads REQUIRED)
  add_executable(wawbf_tests tests/test_protocol.cpp)
  target_link_libraries(wawbf_tests PRIVATE wawbf_protocol Threads::Threads)
  add_test(NAME protocol COMMAND wawbf_tests)
endif()
