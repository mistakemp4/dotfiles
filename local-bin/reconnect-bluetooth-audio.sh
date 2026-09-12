#!/usr/bin/env bash
# Restarting wireplumber/pipewire drops the A2DP media transport for already-connected
# Bluetooth audio devices; BlueZ doesn't renegotiate it on its own, only a disconnect+
# reconnect does. This runs after wireplumber starts to auto-heal that.
MAC="58:36:53:CB:E2:EC"

sleep 3

if bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; then
    bluetoothctl disconnect "$MAC" >/dev/null 2>&1
    sleep 1
    bluetoothctl connect "$MAC" >/dev/null 2>&1
fi
