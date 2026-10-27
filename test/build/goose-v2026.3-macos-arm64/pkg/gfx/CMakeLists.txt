# The gfx package's native part: SDL3, and the C layers that gfx.goose (over
# SDL_GPU), audio.goose (SDL's audio) and ui.goose (Nuklear, drawn through
# gfx) declare their extern fns against, under src/. One package, since the
# three share SDL and ui draws through gfx. Built by the Goose compiler
# through its wrapper project when a program needs the package
# (docs/design/packages.md §5.2), or into the compiler itself as a builtin
# package (§7.1). What a user of the package links is goose_gfx_package,
# which carries all three layers and SDL.

cmake_minimum_required(VERSION 3.20)
project(goose_gfx_package C)

# SDL3 and Nuklear: the submodules beside this file, or the Goose tree's own
# while the package lives in that tree. Without either the package builds
# nothing, and says so.
foreach(dep IN ITEMS SDL nuklear)
    set(GOOSE_GFX_${dep} "" CACHE PATH "The ${dep} source tree")
    if(NOT GOOSE_GFX_${dep})
        foreach(cand "${CMAKE_CURRENT_SOURCE_DIR}/third_party/${dep}"
                     "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/${dep}")
            if(EXISTS "${cand}/CMakeLists.txt" OR EXISTS "${cand}/nuklear.h")
                set(GOOSE_GFX_${dep} "${cand}")
                break()
            endif()
        endforeach()
    endif()
    if(NOT GOOSE_GFX_${dep})
        message(STATUS "gfx: ${dep} not found (the third_party/${dep} submodule); building nothing")
        return()
    endif()
endforeach()

# --- a video backend on Linux ------------------------------------------------
# SDL's configure does not fail without the X11 and Wayland development
# headers: it quietly builds an SDL that cannot open a window. Build nothing
# instead, saying what to install.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    find_package(X11 QUIET)
    find_package(PkgConfig QUIET)
    if(PKG_CONFIG_FOUND)
        pkg_check_modules(GFX_WAYLAND QUIET wayland-client)
    endif()
    if(NOT X11_FOUND AND NOT GFX_WAYLAND_FOUND)
        message(STATUS "gfx: neither the X11 nor the Wayland development files were found, "
                       "so SDL could not open a window; building nothing. "
                       "Install the packages in SDL's docs/README-linux.md "
                       "(at least libx11-dev libxext-dev, or libwayland-dev libxkbcommon-dev "
                       "wayland-protocols) and reconfigure.")
        return()
    endif()
endif()

# --- SDL ---------------------------------------------------------------------
# Static only. SDL_DEPS_SHARED stays on: on Linux SDL then links only the C
# library and loads X11, Wayland, audio and udev at runtime, so a program
# gains no hard GUI dependencies. SDL_GPU draws through neither the 2D
# renderer nor OpenGL, and nothing uses the camera, so those are left out.
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_CAMERA OFF CACHE BOOL "" FORCE)
set(SDL_RENDER OFF CACHE BOOL "" FORCE)
set(SDL_OPENGL OFF CACHE BOOL "" FORCE)
set(SDL_OPENGLES OFF CACHE BOOL "" FORCE)
add_subdirectory("${GOOSE_GFX_SDL}" SDL EXCLUDE_FROM_ALL)

# --- the gfx layer -----------------------------------------------------------
add_library(goose_gfx STATIC
    src/gfx/gfx_api.h
    src/gfx/gfx_blob.h
    src/gfx/gfx_internal.h
    src/gfx/gfx_device.c
    src/gfx/gfx_resources.c
    src/gfx/gfx_pipeline.c
    src/gfx/gfx_draw.c
)
target_link_libraries(goose_gfx PUBLIC SDL3::SDL3-static)

# --- the audio layer: the PCM mixer, no window ---------------------------------
add_library(goose_audio STATIC src/audio/audio.c src/audio/audio_api.h)
target_link_libraries(goose_audio PUBLIC SDL3::SDL3-static)

# --- the ui layer: Nuklear, one header, compiled once in ui_nuklear.c ----------
set(ui_layer_sources
    src/ui/ui_core.c
    src/ui/ui_font.c
    src/ui/ui_window.c
    src/ui/ui_widget.c
    src/ui/ui_style.c
    src/ui/ui_draw.c
)
add_library(goose_ui STATIC src/ui/ui_api.h src/ui/ui_internal.h src/ui/ui_nuklear.c ${ui_layer_sources})
target_include_directories(goose_ui PRIVATE "${GOOSE_GFX_nuklear}")
if(NOT WIN32)
    target_link_libraries(goose_ui PUBLIC m)
endif()

foreach(t IN ITEMS goose_gfx goose_audio goose_ui)
    set_target_properties(${t} PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON
                          INTERPROCEDURAL_OPTIMIZATION OFF)
endforeach()
# Warnings for the layers, none for Nuklear's implementation: third-party
# code is not ours to act on.
if(MSVC)
    foreach(t IN ITEMS goose_gfx goose_audio)
        target_compile_options(${t} PRIVATE /W4 /utf-8)
    endforeach()
    set_source_files_properties(${ui_layer_sources} PROPERTIES COMPILE_OPTIONS "/W4;/utf-8")
    set_source_files_properties(src/ui/ui_nuklear.c PROPERTIES COMPILE_OPTIONS "/W0;/utf-8")
    foreach(t IN ITEMS goose_gfx goose_audio goose_ui)
        target_compile_definitions(${t} PRIVATE _CRT_SECURE_NO_WARNINGS)
    endforeach()
else()
    foreach(t IN ITEMS goose_gfx goose_audio)
        target_compile_options(${t} PRIVATE -Wall -Wextra -Wno-missing-field-initializers)
    endforeach()
    set_source_files_properties(${ui_layer_sources} PROPERTIES COMPILE_OPTIONS
                                "-Wall;-Wextra;-Wno-missing-field-initializers")
    set_source_files_properties(src/ui/ui_nuklear.c PROPERTIES COMPILE_OPTIONS "-w")
endif()

# --- the package -------------------------------------------------------------
add_library(goose_gfx_package INTERFACE)
target_link_libraries(goose_gfx_package INTERFACE goose_gfx goose_audio goose_ui)

# The audio layer's own test, never part of a normal build: SDL's dummy
# driver, no device.
add_executable(goose_audio_test EXCLUDE_FROM_ALL test/audio_device.c)
target_link_libraries(goose_audio_test PRIVATE goose_audio)
set_target_properties(goose_audio_test PROPERTIES C_STANDARD 11)

file(STRINGS "${GOOSE_GFX_SDL}/include/SDL3/SDL_version.h" gfx_sdl_version
     REGEX "^#define SDL_(MAJOR|MINOR|MICRO)_VERSION +[0-9]+")
string(REGEX REPLACE "[^;]* ([0-9]+);[^;]* ([0-9]+);[^;]* ([0-9]+)" "\\1.\\2.\\3"
       gfx_sdl_version "${gfx_sdl_version}")
file(READ "${GOOSE_GFX_nuklear}/clib.json" ui_clib)
string(REGEX MATCH "\"version\": *\"([0-9.]+)\"" ui_version_match "${ui_clib}")
message(STATUS "gfx: SDL ${gfx_sdl_version} and Nuklear ${CMAKE_MATCH_1}, static")
