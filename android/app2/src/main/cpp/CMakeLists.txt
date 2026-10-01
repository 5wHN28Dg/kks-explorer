# libjxl (built from the pinned source the Gradle task fetchLibjxl unpacks) + a small JNI wrapper (jxl_jni.cpp).
cmake_minimum_required(VERSION 3.22)
project(kksjxl C CXX)

set(LIBJXL_SRC "" CACHE PATH "libjxl source tree with third_party/{highway,brotli,skcms} filled in")
if(NOT EXISTS "${LIBJXL_SRC}/CMakeLists.txt")
  message(FATAL_ERROR "LIBJXL_SRC=${LIBJXL_SRC} has no libjxl (run the Gradle task fetchLibjxl)")
endif()

# only the codec library: no tools, tests, docs, plugins, JPEG/PNG/EXR helpers
foreach(opt BUILD_TESTING BUILD_SHARED_LIBS JPEGXL_ENABLE_TOOLS JPEGXL_ENABLE_DOXYGEN JPEGXL_ENABLE_MANPAGES
            JPEGXL_ENABLE_BENCHMARK JPEGXL_ENABLE_EXAMPLES JPEGXL_ENABLE_JNI JPEGXL_ENABLE_SJPEG JPEGXL_ENABLE_OPENEXR
            JPEGXL_ENABLE_JPEGLI JPEGXL_ENABLE_PLUGINS JPEGXL_ENABLE_VIEWERS JPEGXL_ENABLE_DEVTOOLS JPEGXL_ENABLE_FUZZERS
            JPEGXL_BUNDLE_LIBPNG JPEGXL_FORCE_SYSTEM_BROTLI JPEGXL_FORCE_SYSTEM_HWY JPEGXL_ENABLE_TRANSCODE_JPEG)
  set(${opt} OFF CACHE BOOL "" FORCE)
endforeach()
set(JPEGXL_ENABLE_SKCMS ON CACHE BOOL "" FORCE)
set(HWY_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(HWY_ENABLE_EXAMPLES OFF CACHE BOOL "" FORCE)
set(HWY_ENABLE_CONTRIB OFF CACHE BOOL "" FORCE)
set(HWY_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(BROTLI_DISABLE_TESTS ON CACHE BOOL "" FORCE)

add_subdirectory(${LIBJXL_SRC} libjxl EXCLUDE_FROM_ALL)

add_library(kksjxl SHARED jxl_jni.cpp)
target_link_libraries(kksjxl PRIVATE jxl jxl_threads log)
target_link_options(kksjxl PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL)

# zxing-cpp (decision 0019; pinned source from the Gradle task fetchZxing): reader + the built-in writer,
# C API, static, nothing fetched at build time (no examples: they would download stb)
set(ZXING_SRC "" CACHE PATH "zxing-cpp source tree")
if(NOT EXISTS "${ZXING_SRC}/core/CMakeLists.txt")
  message(FATAL_ERROR "ZXING_SRC=${ZXING_SRC} has no zxing-cpp (run the Gradle task fetchZxing)")
endif()
set(ZXING_READERS ON CACHE BOOL "" FORCE)
set(ZXING_WRITERS OLD CACHE STRING "" FORCE)   # the built-in writer: NEW needs the zint submodule, not in the tarball
set(ZXING_C_API ON CACHE BOOL "" FORCE)
set(ZXING_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ZXING_UNIT_TESTS OFF CACHE BOOL "" FORCE)
set(ZXING_BLACKBOX_TESTS OFF CACHE BOOL "" FORCE)
set(ZXING_DEPENDENCIES LOCAL CACHE STRING "" FORCE)
set(BUILD_SHARED_LIBS OFF)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# only the library (the top level also adds the C example, which needs stb)
add_subdirectory(${ZXING_SRC}/core zxing EXCLUDE_FROM_ALL)

add_library(kksqr SHARED qr_jni.cpp)
target_link_libraries(kksqr PRIVATE ZXing::ZXing log)
target_link_options(kksqr PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL)
