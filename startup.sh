#!/bin/bash

interface="ens3f0np0"
cpus="3,5,7,9,11,13,15"
irq_cpus="13,15"

echo "=========== start vpp containers ==========="
#docker run -dit --name vpp1 --privileged --cpuset-cpus=3,5,7,9,11 --ulimit memlock=-1 -v /dev/hugepages:/dev/hugepages vpp-base:latest
docker run -dit --name vpp1 --privileged --cpuset-cpus=$cpus --ulimit memlock=-1 -v /dev/hugepages:/dev/hugepages  \
    -v /lib/firmware/intel:/lib/firmware/intel \
	-v /sys/bus/pci/devices:/sys/bus/pci/devices -v /sys/devices/system/node:/sys/devices/system/node -v /lib/modules:/lib/modules -v /dev:/dev \
    vpp-base:latest
docker exec vpp1 hostname vpp1

#######################################################################
# Locate and link up docker namespaces into /var/run/netns/*
#######################################################################

echo "=========== make sure directory /var/run/netns exists ==========="
if [ ! -d /var/run/netns ]; then
    sudo mkdir /var/run/netns
fi

echo "=========== expose container vpp1 netns ==========="
VPP1NS=`docker inspect -f '{{.State.Pid}}' vpp1`

if [ -f /var/run/netns/$VPP1NS ]; then
    sudo rm -rf /var/run/netns/$VPP1NS
fi

sudo ln -s /proc/$VPP1NS/ns/net /var/run/netns/$VPP1NS
echo "=========== done. vpp1 netns: $VPP1NS"

###############################################
# Move interface into vpp network namespace
###############################################
echo "=========== Move $interface into vpp network namespace ==========="

sudo ip link set $interface netns $VPP1NS

echo "=========== configuring $interface ==========="

sudo ip netns exec $VPP1NS ip addr add 172.19.0.3/16 dev $interface
sudo ip netns exec $VPP1NS ip link set $interface up

echo "=========== remove eth0s in containers ==========="
docker exec vpp1 ip link del eth0

echo "=========== Setup HW descriptors ==========="
docker exec vpp1 ethtool -G $interface rx 8160 tx 8160

echo "=========== Setup RSS ==========="
docker exec vpp1 ethtool -X $interface equal 4 start 0

echo "=========== Disable busy polling ==========="
docker exec vpp1 bash -c "echo 0 >> /sys/class/net/$interface/napi_defer_hard_irqs"
docker exec vpp1 bash -c "echo 0 >> /sys/class/net/$interface/gro_flush_timeout"

echo "=========== Setup irq affinity to different cores ==========="
docker exec vpp1 ./set_irq_affinity.sh $irq_cpus $interface

echo "=========== Jump into vpp1 ==========="
docker exec -ti vpp1 ./build-root/install-vpp-native/vpp/bin/vpp -c VPP_STARTUP.conf

# To RUN VPP WITHOUT busy polling AF_XDP SOCKETS
# ./build-root/install-vpp-native/vpp/bin/vpp -c VPP_STARTUP.conf
