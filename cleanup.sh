#!/bin/bash

echo "=== Kill vpp1 ==="
docker kill vpp1

echo "=== Remove vpp1 ==="
docker rm vpp1

echo "=== Cleanup /var/run/netns/*"
sudo rm -rf /var/run/netns/*

echo "=== Cleanup /run/vpp/*"
sudo rm -rf /run/vpp/*
