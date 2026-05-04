cmake_minimum_required(VERSION 3.10)
project(identity_hub C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra -O2")
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(MHD REQUIRED libmicrohttpd)
pkg_check_modules(JANSSON REQUIRED jansson)
pkg_check_modules(OPENSSL REQUIRED openssl)

set(COMMON_INCLUDES
    ${MHD_INCLUDE_DIRS}
    ${JANSSON_INCLUDE_DIRS}
    ${OPENSSL_INCLUDE_DIRS}
    src
)

add_library(hub_core STATIC
    src/identity.c
    src/storage.c
    src/cache.c
    src/crypto.c
    src/webfinger.c
)
target_include_directories(hub_core PUBLIC ${COMMON_INCLUDES})
target_link_libraries(hub_core ${JANSSON_LIBRARIES} ${OPENSSL_LIBRARIES})

add_library(hub_auth SHARED src/hub_auth.c)
target_include_directories(hub_auth PUBLIC ${COMMON_INCLUDES})
target_link_libraries(hub_auth hub_core)

add_library(hub_search SHARED src/hub_search.c)
target_include_directories(hub_search PUBLIC ${COMMON_INCLUDES})
target_link_libraries(hub_search hub_core)

add_library(hub_resolve SHARED src/hub_resolve.c)
target_include_directories(hub_resolve PUBLIC ${COMMON_INCLUDES})
target_link_libraries(hub_resolve hub_core)

add_library(hub_protocol SHARED src/hub_protocol.c)
target_include_directories(hub_protocol PUBLIC ${COMMON_INCLUDES})
target_link_libraries(hub_protocol hub_core)

add_library(hub_export SHARED src/hub_export.c)
target_include_directories(hub_export PUBLIC ${COMMON_INCLUDES})
target_link_libraries(hub_export hub_core)

add_executable(identity_hub
    src/main.c
    src/handlers.c
)

target_include_directories(identity_hub PRIVATE ${COMMON_INCLUDES})

target_link_libraries(identity_hub
    hub_core
    hub_auth
    hub_search
    hub_resolve
    hub_protocol
    hub_export
    ${MHD_LIBRARIES}
    ${JANSSON_LIBRARIES}
    ${OPENSSL_LIBRARIES}
)
