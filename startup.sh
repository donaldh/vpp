#!/bin/bash

echo "=========== start vpp containers ==========="
#docker run -dit --name vpp1 --privileged --cpuset-cpus=23,25,27,29 --ulimit memlock=-1 -v /dev/hugepages:/dev/hugepages -v /root/vpp:/vpp  vpp-base:latest
docker run -dit --name vpp1 --privileged --cpuset-cpus=23,25,27,29 --ulimit memlock=-1 -v /dev/hugepages:/dev/hugepages vpp-base:latest
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
echo "=========== Move ens3f0np0 into vpp network namespace ==========="

sudo ip link set ens3f0np0 netns $VPP1NS

echo "=========== configuring ens3f0np0 ==========="

sudo ip netns exec $VPP1NS ip addr add 172.19.0.3/16 dev ens3f0np0
sudo ip netns exec $VPP1NS ip link set ens3f0np0 up

# echo "=========== start vpp on vpp1 ==========="
# docker exec vpp1 make run-release

echo "=========== remove eth0s in containers ==========="
docker exec vpp1 ip link del eth0

echo "=========== Jump into vpp1 ==========="
docker exec -ti vpp1 bash
