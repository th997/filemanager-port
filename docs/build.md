# Building

## Toolchain

| Tool | Version |
|---|---|
| Flutter | 3.47.7 (Dart 3.13.5) |
| Rust | stable (rustup) |
| Android SDK | API 36 platform, build-tools 35+, NDK 29 |
| JDK | 21 |

## Linux desktop

```bash
sudo apt-get install -y clang ninja-build libgtk-3-dev libmpv-dev \
  libdbus-1-dev libsecret-1-dev
cd rust && cargo test --workspace
cd ../app && flutter run -d linux
```

## Android

```bash
cd app
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Rust is compiled by cargokit as part of the Gradle build; no separate NDK
invocation is needed.

## Windows

```powershell
cd app
flutter build windows
```

Requires Visual Studio with the C++ desktop workload. The Rust target
`x86_64-pc-windows-msvc` is installed by cargokit on first build.

## macOS

```bash
cd app
flutter build macos
```

Requires Xcode and CocoaPods. The app sandbox entitlements are in
`app/macos/Runner/*.entitlements`.

## iOS

```bash
cd app
flutter build ios --no-codesign   # CI
flutter build ipa                 # with signing
```

iOS builds require macOS; they cannot be produced on Linux or Windows.

## Regenerating the bridge

After changing `rust/crates/fm-ffi/src/lib.rs`:

```bash
cd rust/crates/fm-ffi && flutter_rust_bridge_codegen generate
```

Generated Dart lands in `app/lib/src/rust/`.
