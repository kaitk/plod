# The physics package's native part: Box3D, and goose_physics, the C layer
# over it that physics.goose declares its extern fns against (src/). Built by
# the Goose compiler through its wrapper project when a program needs the
# package (docs/design/packages.md §5.2), or into the compiler itself as a
# builtin package (§7.1).

cmake_minimum_required(VERSION 3.22)
project(goose_physics_package C)

# Box3D: the submodule beside this file, or the Goose tree's own while the
# package lives in that tree.
set(GOOSE_PHYSICS_BOX3D "" CACHE PATH "The Box3D source tree")
if(NOT GOOSE_PHYSICS_BOX3D)
    foreach(cand "${CMAKE_CURRENT_SOURCE_DIR}/third_party/box3d"
                 "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/box3d")
        if(EXISTS "${cand}/CMakeLists.txt")
            set(GOOSE_PHYSICS_BOX3D "${cand}")
            break()
        endif()
    endforeach()
endif()
if(NOT GOOSE_PHYSICS_BOX3D)
    message(STATUS "physics: Box3D not found (the third_party/box3d submodule); building nothing")
    return()
endif()

# --- Box3D -------------------------------------------------------------------
# Only the library: its samples, tests and documentation are options of a
# top-level build alone. Single precision, which the layer's structs are, and
# static whatever BUILD_SHARED_LIBS says elsewhere.
set(BOX3D_DOUBLE_PRECISION OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF)
add_subdirectory("${GOOSE_PHYSICS_BOX3D}" box3d EXCLUDE_FROM_ALL)
# Box3D asks for the debug C runtime in a debug build; everything of Goose's
# links the release one.
set_target_properties(box3d PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded")

# --- the physics layer ---------------------------------------------------------
add_library(goose_physics STATIC
    src/physics_api.h
    src/physics_internal.h
    src/physics_core.c
    src/physics_world.c
    src/physics_body.c
    src/physics_shape.c
    src/physics_joint.c
    src/physics_geometry.c
)
# Box3D starts worker threads of its own inside a step.
find_package(Threads REQUIRED)
target_link_libraries(goose_physics PUBLIC box3d::box3d Threads::Threads)
# C17, as Box3D's headers are.
set_target_properties(goose_physics PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON
                      INTERPROCEDURAL_OPTIMIZATION OFF)
if(MSVC)
    target_compile_options(goose_physics PRIVATE /W4 /utf-8)
    target_compile_definitions(goose_physics PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(goose_physics PRIVATE -Wall -Wextra -Wno-missing-field-initializers)
endif()

get_directory_property(physics_box3d_version DIRECTORY "${GOOSE_PHYSICS_BOX3D}" DEFINITION box3d_VERSION)
message(STATUS "physics: Box3D ${physics_box3d_version}, static")
