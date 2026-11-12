cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "setup")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../buildkit/cmake/buildkit.cmake")
apply_buildkit()

add_dependencies(${BINARY_NAME} setup_buildkit_build)

get_filename_component(PROJECT_ROOT "${CMAKE_SOURCE_DIR}" DIRECTORY)

install(PROGRAMS "${PROJECT_ROOT}/libclash/linux/FlClashCore"
  "${PROJECT_ROOT}/libclash/linux/ElephantNetworkUpdater"
  "${PROJECT_ROOT}/libclash/linux/ElephantNetworkHelperService"
  DESTINATION "${CMAKE_BINARY_DIR}/bundle"
  COMPONENT Runtime
)

install(FILES "${PROJECT_ROOT}/libclash/linux/manifest.json"
  DESTINATION "${CMAKE_BINARY_DIR}/bundle"
  COMPONENT Runtime
)
