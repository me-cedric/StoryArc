# The Android half of the vendored libarchive build.
#
# It compiles the same sources SwiftPM compiles for iOS — one copy under
# third_party/, referenced rather than duplicated. See
# third_party/libarchive/VENDORING.md for the file list and why only 26 of
# libarchive's 132 sources are here.
#
# libarchive's own CMake is not used. It would configure the whole library,
# probe for a dozen optional dependencies, and generate a config.h that differs
# from the iOS one — which is exactly the drift the shared hand-authored
# config.h exists to prevent.

cmake_minimum_required(VERSION 3.22.1)
project(storyarc_rar C)

# cpp -> main -> src -> format -> core -> android -> apps -> repository root
set(LIBARCHIVE_DIR
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../../third_party/libarchive/Sources/CLibarchive)

if(NOT EXISTS ${LIBARCHIVE_DIR}/config.h)
    # A clearer failure than 26 missing-file errors, which is what a moved or
    # partially-cloned tree would otherwise produce.
    message(FATAL_ERROR
        "Vendored libarchive not found at ${LIBARCHIVE_DIR}. "
        "It is committed, not fetched — check the working tree is complete.")
endif()

file(GLOB LIBARCHIVE_SOURCES ${LIBARCHIVE_DIR}/*.c)

add_library(storyarc_rar SHARED rar_decoder.c ${LIBARCHIVE_SOURCES})

target_include_directories(storyarc_rar PRIVATE
    ${LIBARCHIVE_DIR}
    ${LIBARCHIVE_DIR}/include)

target_compile_definitions(storyarc_rar PRIVATE
    # The hand-authored config.h beside the sources, not an autoconf run.
    HAVE_CONFIG_H
    # Gates libarchive's internal-only declarations, including the Android
    # large-file shim archive.h includes unconditionally on this platform.
    __LIBARCHIVE_BUILD)

target_compile_options(storyarc_rar PRIVATE
    -O2
    # Per-function sections so the linker can drop what the two RAR readers do
    # not reach. This is what takes the objects from ~440 kB to ~140 kB.
    -ffunction-sections
    -fdata-sections
    # Upstream code, so its warnings are not ours to fix and must not fail a
    # build. Our own shim is compiled with the project's warnings below.
    -Wno-everything)

set_source_files_properties(rar_decoder.c PROPERTIES
    COMPILE_OPTIONS "-Wall;-Wextra;-Werror")

target_link_options(storyarc_rar PRIVATE -Wl,--gc-sections)

# log is for __android_log_print in the shim's failure paths.
target_link_libraries(storyarc_rar log)
