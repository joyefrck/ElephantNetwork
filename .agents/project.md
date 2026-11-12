# Project Context

FlClash is a multi-platform proxy client based on ClashMeta (mihomo), built with Flutter. It supports Android, Windows, macOS, and Linux, using a Material You design with Surfboard-like UI.

## Version Notes

- Release CI pins Flutter 3.44.4. Local SDK may diverge, so trust the CI
  version as the source of truth for release builds.
- Dart SDK constraint: `>=3.8.0 <4.0.0`.

## Build Dependencies

Linux:

```bash
sudo apt-get install libayatana-appindicator3-dev libkeybinder-3.0-dev
```

Windows:

- GCC and Inno Setup.
- `ANDROID_NDK` env var for Android builds.

macOS:

```bash
npm install -g appdmg
```

## Android Core Toolchain

The shared Core module requires Go 1.26.0; validation remains pinned to Go 1.26.4. Android uses the gomobile/gobind revision recorded in `core/go.mod`, not an unpinned global installation. The Core library's API level is 23. The App entry point still inherits Flutter's default, which is API 24 in Flutter 3.44.4; do not infer complete Android 6 support from the library setting or silently raise compatibility requirements in unrelated work.
