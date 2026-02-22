# BatteryBar

A lightweight macOS menu bar app that shows battery levels for connected Bluetooth devices (keyboards, mice, trackpads, headphones).

![BatteryBar](screenshot.png)

## Install

1. Download `BatteryBar.zip` from the [latest release](../../releases/latest)
2. Unzip and move `BatteryBar.app` to `/Applications`
3. On first launch: right-click the app > Open (required for unsigned apps)

**Requirements:** Apple Silicon Mac (M1/M2/M3+) running macOS 13.0 or later.

> The app is not code-signed or notarized. macOS will block it on first launch —
> right-click the app and select "Open" to bypass Gatekeeper.

## Features

- Individual status bar icons with battery percentage for each connected Bluetooth device
- Per-device visibility toggles — hide/show devices directly from the dropdown menu
- Low battery warning (icon turns red at 10% or below)
- Launch at Login support
- Reads from both IOKit (classic Bluetooth) and CoreBluetooth (BLE) devices

## Building

```bash
./build.sh
```

Requires Xcode Command Line Tools. Targets macOS 13.0+ (arm64).

## Running

```bash
open BatteryBar.app
```

## Nice-to-have

- Settings window (refresh interval, low battery threshold, icon style, show/hide percentage text)
