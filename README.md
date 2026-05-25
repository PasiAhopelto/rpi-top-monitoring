# RPi Top Monitor

A high-performance, lightweight terminal system monitor (`top`-like TUI) designed specifically for the **Raspberry Pi 4**, built entirely in **Zig 0.16.0**.

This project was built and refined in partnership with **Google Antigravity**.

## Features

- **Real-Time CPU Metrics**: Displays CPU temperature (°C), current scaling frequency (MHz), load percentage (%), and the active frequency governor mode.
- **Real-Time GPU Metrics**: Displays GPU temperature (°C) and core clock speed (MHz) using `/usr/bin/vcgencmd`.
- **Tabular Historical UI**: Renders a live-updating table using raw ANSI escape codes. Newest entries appear at the top, maintaining a 20-entry history.
- **Configurable Refresh Rates**: Adjust update intervals via command-line arguments (default is 10 seconds).
- **Timezone-Aware**: Automatically displays localized timestamps using the system's active timezone offset.
- **Zero-Dependency Static Binary**: Compiles to a fully static, standalone executable with zero C or library dependencies, making cross-compilation robust and simple.
- **Mock Fallback**: Automatically falls back to a clean mock data generator when run on non-Linux hosts (like macOS) for easy development.

## Prerequisites

- **Zig Compiler**: Version **0.16.0** is required.

## Building the Project

The application is built using standard Zig compilation commands. You can compile natively for your host machine or cross-compile for your Raspberry Pi.

### Target Architecture Options
You can specify the target platform using the `-Dtarget` flag. The syntax is `[arch]-[os]-[abi]`:
- **Raspberry Pi 4 (64-bit Linux OS)**: `-Dtarget=aarch64-linux` *(Recommended)*
- **Raspberry Pi 3/4 (32-bit Linux OS)**: `-Dtarget=arm-linux-gnueabihf`
- **Native Host Build (e.g. macOS)**: Omit the target option to compile for your development machine.

### Commands

#### Standard Build (For Host OS / Development)
```bash
zig build
```
The compiled binary will be placed at `zig-out/bin/rpi-top` (uses macOS Mach-O format on a Mac).

#### Cross-Compilation (For Raspberry Pi 4 64-bit Target)
```bash
zig build -Dtarget=aarch64-linux
```
The compiled static ELF binary will be placed at `zig-out/bin/rpi-top`.

## Running the Application

### 1. Copying the Binary to your Raspberry Pi
Transfer the cross-compiled binary from your development machine to your Pi:
```bash
scp zig-out/bin/rpi-top <user>@<pi-ip>:~/rpi-top
```

### 2. Execution on the Pi
Connect to your Pi, set execute permissions, and run the binary:
```bash
chmod +x ~/rpi-top
~/rpi-top [refresh_interval_in_seconds]
```
For example, to refresh every 2 seconds:
```bash
~/rpi-top 2
```

---
*Generated and paired with **Google Antigravity**.*
