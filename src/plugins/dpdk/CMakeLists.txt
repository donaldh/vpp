# Copyright (c) 2016 Cisco and/or its affiliates.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

vpp_find_path(XDP_INCLUDE_DIR NAMES xdp/xsk.h)
if (NOT XDP_INCLUDE_DIR)
  message(WARNING "libxdp headers not found - af_xdp plugin disabled")
  return()
endif()

set_property(GLOBAL PROPERTY FIND_LIBRARY_USE_LIB64_PATHS TRUE)
vpp_plugin_find_library(af_xdp XDP_LIB libxdp.a)
vpp_plugin_find_library(af_xdp BPF_LIB libbpf.a)
vpp_plugin_find_library(af_xdp ELF_LIB elf)
vpp_plugin_find_library(af_xdp Z_LIB z)
if (NOT XDP_LIB OR NOT BPF_LIB OR NOT ELF_LIB OR NOT Z_LIB)
  message(WARNING "dpdk plugin - missing libraries")
endif()

set(CMAKE_REQUIRED_INCLUDES "${XDP_INCLUDE_DIR}")
set(CMAKE_REQUIRED_LIBRARIES "${XDP_LIB}" "${BPF_LIB}" "${ELF_LIB}" "${Z_LIB}")
CHECK_C_SOURCE_COMPILES("
#include <xdp/xsk.h>
int main(void)
{
    return xsk_socket__create (0, 0, 0, 0, 0, 0, 0);
}" XDP_COMPILES_CHECK)
if (NOT XDP_COMPILES_CHECK)
message(WARNING "af_xdp plugins - no working libxdp found - af_xdp plugin disabled")
  return()
endif()

include_directories(${XDP_INCLUDE_DIR})

##############################################################################
# Check if we want to use the system DPDK
##############################################################################
option(VPP_USE_SYSTEM_DPDK "Use the system installation of DPDK." OFF)
if(VPP_USE_SYSTEM_DPDK)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(DPDK REQUIRED libdpdk)
    message(WARNING "-- linking dpdk plugin against system libdpdk, version ${DPDK_VERSION}")
    set(DPDK_LINK_FLAGS ${DPDK_LDFLAGS})
    include_directories (${DPDK_INCLUDE_DIRS})
else()
    ##############################################################################
    # Find lib and include files
    ##############################################################################
    vpp_find_path(DPDK_INCLUDE_DIR PATH_SUFFIXES dpdk NAMES rte_config.h)
    vpp_plugin_find_library(dpdk DPDK_LIB "libdpdk.a")

    if (NOT DPDK_INCLUDE_DIR)
      message(WARNING "-- DPDK headers not found - dpdk plugin disabled")
      return()
    endif()

    if (NOT DPDK_LIB)
      vpp_plugin_find_library(dpdk DPDK_SHLIB "libdpdk.so")
      set(DPDK_IS_SHARED_LIB 1)
      message(WARNING "-- linking dpdk plugin against DPDK shared libs")
    endif()

    ##############################################################################
    # Parse DPDK config and version header files
    ##############################################################################
    file(STRINGS ${DPDK_INCLUDE_DIR}/rte_config.h rte_config)
    file(STRINGS ${DPDK_INCLUDE_DIR}/rte_version.h rte_version)
    file(STRINGS ${DPDK_INCLUDE_DIR}/rte_build_config.h rte_build_config)

    foreach(l ${rte_config} ${rte_build_config} ${rte_version}})
      if (l MATCHES "^#define[\t ]*RTE_")
        STRING(REGEX REPLACE "^#define[\t ]*([A-Z1-9_]+)[\t ]*(.+)" "\\1;\\2" v "${l}")
        list(GET v 0 name)
        list(GET v 1 value)
        set(DPDK_${name} ${value})
      endif()
    endforeach()

    set(DPDK_VERSION
        "${DPDK_RTE_VER_YEAR}.${DPDK_RTE_VER_MONTH}.${DPDK_RTE_VER_MINOR}")

    ##############################################################################
    # verify headroom size
    ##############################################################################
    if(NOT ${DPDK_RTE_PKTMBUF_HEADROOM} EQUAL ${PRE_DATA_SIZE})
      message(
        FATAL_ERROR
        "DPDK RTE_PKTMBUF_HEADROOM (${DPDK_RTE_PKTMBUF_HEADROOM}) "
         "must be equal to PRE_DATA_SIZE (${PRE_DATA_SIZE})"
      )
    endif()

    ##############################################################################
    # static or dynamic linking
    ##############################################################################
    unset(DPDK_LINK_LIBRARIES)
    unset(DPDK_LINK_FLAGS)
    message(STATUS "Found DPDK ${DPDK_VERSION} in ${DPDK_INCLUDE_DIR}")
    include_directories (${DPDK_INCLUDE_DIR})

    if(DPDK_IS_SHARED_LIB)
      get_filename_component(DPDK_LIB_DIR ${DPDK_SHLIB} DIRECTORY)
      string_append(DPDK_LINK_FLAGS "-L${DPDK_LIB_DIR}")
      list(APPEND DPDK_LINK_LIBRARIES ${DPDK_SHLIB})
    else()
      get_filename_component(DPDK_LIB_DIR ${DPDK_LIB} DIRECTORY)
      string_append(DPDK_LINK_FLAGS "-L${DPDK_LIB_DIR}")
      string_append(DPDK_LINK_FLAGS "-Wl,--whole-archive,${DPDK_LIB},--no-whole-archive")
    endif()

    ##############################################################################
    # libnuma
    ##############################################################################
    vpp_plugin_find_library(dpdk NUMA_LIB "numa")
    list(APPEND DPDK_LINK_LIBRARIES ${NUMA_LIB})

    ##############################################################################
    # Mellanox libraries
    ##############################################################################
    if(DPDK_RTE_NET_MLX4 OR DPDK_RTE_NET_MLX5)
      if (DPDK_RTE_IBVERBS_LINK_DLOPEN)
        message(STATUS "DPDK depends on libmnl (Mellanox PMD requirement)")
        vpp_plugin_find_library(dpdk MNL_LIB "mnl")
        list(APPEND DPDK_LINK_LIBRARIES "${MNL_LIB}")
      else()
        message(WARNING "EXPERIMENTAL: DPDK plugin without dlopen mode")
	vpp_plugin_find_library(dpdk IBVERBS_LIB "libibverbs.a")
	vpp_plugin_find_library(dpdk MLX5_LIB "libmlx5.a")
	vpp_plugin_find_library(dpdk MLX4_LIB "libmlx4.a")
	string_append(DPDK_LINK_FLAGS "-Wl,--whole-archive,${IBVERBS_LIB},${MLX5_LIB},${MLX4_LIB} -Wl,--no-whole-archive,--exclude-libs,ALL")
      endif()
    endif()
endif()

##############################################################################
# DPDK plugin
##############################################################################

if(OPENSSL_FOUND)
  include_directories(${OPENSSL_INCLUDE_DIR})

  set(DPDK_CRYPTODEV_OP_SOURCE cryptodev/cryptodev_op_data_path.c)
  set(DPDK_CRYPTODEV_SOURCE cryptodev/cryptodev.c)
  if (${DPDK_VERSION} VERSION_GREATER_EQUAL "20.8.0")
    set(DPDK_CRYPTODEV_RAW_SOURCE cryptodev/cryptodev_raw_data_path.c)
  endif()
endif()

add_vpp_plugin(dpdk
  SOURCES
  buffer.c
  main.c
  device/cli.c
  device/common.c
  device/device.c
  device/driver.c
  device/flow.c
  device/format.c
  device/init.c
  device/node.c
  ${DPDK_CRYPTODEV_OP_SOURCE}
  ${DPDK_CRYPTODEV_SOURCE}
  ${DPDK_CRYPTODEV_RAW_SOURCE}

  MULTIARCH_SOURCES
  buffer.c
  device/device.c
  device/node.c

  INSTALL_HEADERS
  device/dpdk.h

  LINK_FLAGS
  "${DPDK_LINK_FLAGS}"

  LINK_LIBRARIES
  ${DPDK_LINK_LIBRARIES}
  ${XDP_LIB}
  ${BPF_LIB}
  ${ELF_LIB}
  ${Z_LIB}

  LINK_LIBRARIES
  ${OPENSSL_CRYPTO_LIBRARIES}

  COMPONENT
  vpp-plugin-dpdk
)
