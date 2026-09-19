#!/usr/bin/env bash
MAC="58:36:53:CB:E2:EC"

sleep 3

if bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; then
    bluetoothctl disconnect "$MAC" >/dev/null 2>&1
    sleep 1
    bluetoothctl connect "$MAC" >/dev/null 2>&1
fi
