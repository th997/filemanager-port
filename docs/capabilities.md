# Platform capability matrix

Target platforms and minimum versions follow Flutter 3.47:

| | Android | iOS | Linux | macOS | Windows |
|---|---|---|---|---|---|
| Minimum | API 24 | 15 | Ubuntu 20.04+ | 12 | 10 |

## Feature matrix

| Feature | Android | iOS | Linux | macOS | Windows |
|---|---|---|---|---|---|
| Browse local files | SAF tree or `MANAGE_EXTERNAL_STORAGE` | granted roots only | native | sandbox + bookmark | native |
| Archive browse/extract/compress | Rust | Rust | Rust | Rust | Rust |
| SFTP / FTP / FTPS / SMB / WebDAV | Rust | Rust | Rust | Rust | Rust |
| HTTP share server | foreground service | foreground only | yes | yes | yes |
| FTP share server | foreground service | foreground only | yes | yes | yes |
| Recycle bin | in-app | in-app | in-app | in-app | in-app |
| APK install / backup | yes | no | no | no | no |
| Background tasks | WorkManager / foreground service | BGTaskScheduler | n/a | n/a | n/a |
| Share to other apps | system share | system share | system share | system share | system share |

## Platform notes

### Android

`MANAGE_EXTERNAL_STORAGE` is permitted for file managers under Play policy but
requires the Permissions Declaration Form. SAF always works and is the default;
"full access" is an opt-in mode. `/Android/data` and most of `/sdcard/Android`
remain inaccessible without special grants.

### iOS

The app is sandboxed and cannot browse the filesystem. Folders are added by the
user through `UIDocumentPicker`; access is persisted as security-scoped
bookmarks. The Files app's "On My iPhone" containers of other apps stay
invisible.

### macOS

App Sandbox requires `files.user-selected.read-write` and
`bookmarks.app-scope`. Direct (non-App-Store) distribution may use Full Disk
Access instead, but then the bookmark model is not exercised.

### Linux

A plain native build has full filesystem access. Under Flatpak, only
portal-granted paths are reachable; the granted-root model applies.

### Windows

Paths beyond `MAX_PATH` need both the registry `LongPathsEnabled` value and a
`longPathAware` manifest entry. Drive letters and UNC paths are both supported
by `std::fs`; remote mounting through WinFsp is out of scope.

## Deliberately not ported

- Root / Shizuku privileged mode (`su --mount-master`).
- Cloud provider SDKs (Dropbox, Box, pCloud, OneDrive, Google Drive, Yandex).
- License validation, ads, and telemetry.
- RAR decompression (the pure-Rust archive stack does not claim it).
