# wdp_voice (decision 0069): the GDExtension, libopus and SpeexDSP's resampler, linked into one shared library per
# platform. Run by build.sh, which fetches and checks the pinned sources and passes WDP_SRC (where they are unpacked)
# and the platform's toolchain; not meant to be configured by hand.
cmake_minimum_required(VERSION 3.22)
project(wdp_voice LANGUAGES C CXX)

option(WDP_NATIVE_TEST "build tests/native_test.cpp with the sanitizers instead of the extension (build.sh native-test)" OFF)
if(WDP_NATIVE_TEST)
  set(WDP_OUT "${CMAKE_BINARY_DIR}" CACHE PATH "" FORCE)
  set(WDP_SUFFIX native-test CACHE STRING "" FORCE)
  add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
  add_link_options(-fsanitize=address,undefined)
endif()
set(WDP_SRC "" CACHE PATH "the unpacked, checked sources: godot-cpp, opus, speexdsp (build.sh)")
set(WDP_OUT "" CACHE PATH "where the library goes")
set(WDP_SUFFIX "" CACHE STRING "the library's platform suffix, e.g. linux.x86_64")
if(NOT WDP_SRC OR NOT WDP_OUT OR NOT WDP_SUFFIX)
  message(FATAL_ERROR "WDP_SRC, WDP_OUT and WDP_SUFFIX must be given (build.sh)")
endif()

# reproducible: no build paths in the objects, no build-time dates
set(WDP_REPRO "-ffile-prefix-map=${WDP_SRC}=/src" "-ffile-prefix-map=${CMAKE_BINARY_DIR}=/build"
              "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=/wdp_voice")
add_compile_options(${WDP_REPRO} -ffunction-sections -fdata-sections)

# libopus 1.5.2: the float codec, no deep-learning extras (DRED, OSCE: off, their models would be megabytes)
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_CUSTOM_MODES OFF CACHE BOOL "" FORCE)
set(OPUS_DRED OFF CACHE BOOL "" FORCE)
set(OPUS_OSCE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
if(WIN32 AND CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
  # every ARM64 Windows CPU has NEON, and libopus has no run-time CPU check there: its NEON code without the check
  set(OPUS_MAY_HAVE_NEON OFF CACHE BOOL "" FORCE)
endif()
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
add_subdirectory("${WDP_SRC}/opus" opus EXCLUDE_FROM_ALL)
if(WIN32 AND CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
  # (as libopus's own configure does with NEON presumed and no run-time check: both macros, no RTCD sources)
  target_compile_definitions(opus PRIVATE OPUS_ARM_MAY_HAVE_NEON OPUS_ARM_MAY_HAVE_NEON_INTR)
endif()

# SpeexDSP 1.2.1: its resampler only, outside Speex (its symbols prefixed wdp_), in float
add_library(wdp_resampler STATIC "${WDP_SRC}/speexdsp/libspeexdsp/resample.c")
target_compile_definitions(wdp_resampler PUBLIC OUTSIDE_SPEEX RANDOM_PREFIX=wdp FLOATING_POINT)
target_include_directories(wdp_resampler PUBLIC "${WDP_SRC}/speexdsp/include/speex"
                                         PRIVATE "${WDP_SRC}/speexdsp/libspeexdsp")

if(WDP_NATIVE_TEST)
  add_executable(wdp_native_test tests/native_test.cpp)
  target_link_libraries(wdp_native_test PRIVATE opus wdp_resampler)
  set_target_properties(wdp_native_test PROPERTIES CXX_STANDARD 17 CXX_EXTENSIONS OFF)
  return()
endif()

# godot-cpp 10.0.0 against Godot 4.7's API, only the classes wdp_voice uses (build_profile.json)
set(GODOTCPP_TARGET template_release CACHE STRING "" FORCE)
set(GODOTCPP_API_VERSION 4.7 CACHE STRING "" FORCE)
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/build_profile.json" CACHE PATH "" FORCE)
add_subdirectory("${WDP_SRC}/godot-cpp" godot-cpp EXCLUDE_FROM_ALL)

add_library(wdp_voice SHARED src/wdp_voice.cpp)
target_link_libraries(wdp_voice PRIVATE godot-cpp opus wdp_resampler)
set_target_properties(wdp_voice PROPERTIES
  CXX_STANDARD 17
  CXX_EXTENSIONS OFF
  CXX_VISIBILITY_PRESET hidden
  C_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
  PREFIX "lib"
  OUTPUT_NAME "wdp_voice.${WDP_SUFFIX}"
  LIBRARY_OUTPUT_DIRECTORY "${WDP_OUT}"
  RUNTIME_OUTPUT_DIRECTORY "${WDP_OUT}")
if(WIN32)
  # one DLL with no dependency beyond Windows' own: libc++ and the unwinder linked in
  target_link_options(wdp_voice PRIVATE -static -Wl,--gc-sections -Wl,--no-insert-timestamp -s)
elseif(ANDROID)
  target_link_options(wdp_voice PRIVATE -Wl,--gc-sections -Wl,--build-id=none -Wl,-z,max-page-size=16384 -s
                      -Wl,--exclude-libs,ALL "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/wdp_voice.map")
else()
  target_link_options(wdp_voice PRIVATE -static-libstdc++ -static-libgcc -Wl,--gc-sections -Wl,--build-id=none
                      -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -s -Wl,--exclude-libs,ALL
                      "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/wdp_voice.map")
endif()
