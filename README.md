<div>

[**简体中文**](README_zh_CN.md)

</div>

## Elephant Network

[![License](https://img.shields.io/github/license/joyefrck/ElephantNetwork?style=flat-square)](LICENSE)

The official multi-platform client for Elephant Network, based on
[FlClash](https://github.com/chen08209/FlClash) and ClashMeta.

This repository keeps the complete upstream feature set while adding Xboard
login, account overview, an account-managed subscription, and transaction and
support entry points. Android, Windows, and macOS are the first-stage release
targets.

Elephant Network is distributed under GPLv3. Binary releases are accompanied by
the corresponding source tag, license, modification notice, build instructions,
and checksums. See [NOTICE](NOTICE), [upstream maintenance](docs/UPSTREAM.md),
and the [privacy contract](docs/PRIVACY.md).

on Desktop:
<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

on Mobile:
<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## Features

✈️ First-stage releases: Android, Windows, and macOS

💻 Adaptive multiple screen sizes, Multiple color themes available

💡 Based on Material You Design, [Surfboard](https://github.com/getsurfboard/surfboard)-like UI

☁️ Supports data sync via WebDAV

✨ Support subscription link, Dark mode

## Use

### Android

Support the following actions

   ```bash
    com.elephantroute.action.START
    
    com.elephantroute.action.STOP
    
    com.elephantroute.action.TOGGLE
   ```

## Releases

Production downloads are published by Elephant Network after the signed
three-platform upgrade gates pass. Upstream FlClash releases are not used as the
in-app update source.

## Build

1. Update submodules
   ```bash
   git submodule update --init --recursive
   ```

2. Install `Flutter` and `Golang` environment

3. Build Application

    - android

        1. Install `Android SDK`, `Android NDK`

        2. Set `ANDROID_NDK` environment variable

        3. Run build script

           ```bash
           dart setup.dart android
           ```

    - windows

        1. Requires a Windows client

        2. Install `GCC`, `Inno Setup`

        3. Run build script

           ```bash
           dart setup.dart windows
           ```

    - macOS

        1. Requires a macOS client

        2. Run build script

           ```bash
           dart setup.dart macos
           ```

## Upstream attribution

FlClash copyright and license notices are retained. Product-specific changes
are documented in this repository and do not imply endorsement by the upstream
authors.

See [release gates](docs/RELEASE_GATES.md) before producing an in-place upgrade.
