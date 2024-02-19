#!/bin/bash

interface="ens3f0np0"

echo "=== Reset RSS ==="
docker exec vpp1 ethtool -X $interface default

echo "=== Kill vpp1 ==="
docker kill vpp1

echo "=== Remove vpp1 ==="
docker rm vpp1

echo "=== Cleanup /var/run/netns/*"
sudo rm -rf /var/run/netns/*

echo "=== Cleanup /run/vpp/*"
sudo rm -rf /run/vpp/*

rmmod irdma; rmmod ice; modprobe ice

echo "=== Reset irq affinity ==="
./set_irq_affinity.sh local $interface
