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
