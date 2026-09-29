cmake_minimum_required(VERSION 3.22.1)

project(notes_needle_jni LANGUAGES C CXX)

add_library(
    notes_needle_jni
    SHARED
    needle_jni.cpp
)

target_compile_features(notes_needle_jni PRIVATE cxx_std_17)

find_library(log-lib log)
find_library(android-lib android)

if(ANDROID_ABI STREQUAL "arm64-v8a")
    add_library(needle_engine STATIC IMPORTED)
    set_target_properties(
        needle_engine
        PROPERTIES
        IMPORTED_LOCATION
        "${CMAKE_CURRENT_SOURCE_DIR}/needle_vendor/arm64-v8a/libneedle.a"
    )
    target_compile_definitions(notes_needle_jni PRIVATE NOTES_NEEDLE_ARM64=1)
    target_link_libraries(
        notes_needle_jni
        needle_engine
        ${log-lib}
        ${android-lib}
    )
else()
    target_compile_definitions(notes_needle_jni PRIVATE NOTES_NEEDLE_ARM64=0)
    target_link_libraries(
        notes_needle_jni
        ${log-lib}
        ${android-lib}
    )
endif()
