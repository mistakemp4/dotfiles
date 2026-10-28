#!/usr/bin/env bash
# velvetroom headphones
MAC="58:36:53:CB:E2:EC"

connected() {
    bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"
}

# ~2 min of tries, headphones may be off
for _ in $(seq 12); do
    connected && exit 0
    if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
        bluetoothctl connect "$MAC" >/dev/null 2>&1
    fi
    sleep 10
done

connected
