# Architecture

The app is a Flutter UI over a Rust core. All platform-independent logic lives
in Rust; Flutter owns presentation and platform integration only.

```
app/ (Flutter)
  features/  →  core/ (generated bridge)  →  fm-ffi  →  fm-vfs  →  fm-local
                                                        ├─ fm-archive
                                                        ├─ fm-remote
                                                        ├─ fm-server
                                                        ├─ fm-index
                                                        ├─ fm-ops
                                                        └─ fm-vault
```

## Layering rules

- `fm-core` holds domain types and has no dependencies beyond serde/thiserror.
- `fm-vfs` defines the `Vfs` trait and the granted-root model. It knows no
  concrete backend.
- Backend crates (`fm-local`, `fm-archive`, `fm-remote`) implement `Vfs`.
- `fm-server` and `fm-ops` are application services over backends.
- `fm-ffi` is the only crate that exports to Flutter. Its surface is plain
  types: no trait objects, no `SystemTime`, no platform handles.

## Identity and paths

- `LocationId` is a stable identity. Display names are never parsed to recover
  identity.
- `VfsPath` stores decoded path components, so names containing `/`, `\` or
  `:` survive a round trip. `to_slash_string()` is for display and native
  conversion only.
- Local paths are resolved by joining components under the root. `..` and `.`
  components are rejected rather than normalised, so a backend path can never
  escape its root.

## Platform roots & sandboxing

Platform storage roots are resolved cleanly at the boundary:
- **Linux / Windows / macOS / Android all-files / iOS sandbox**: `VfsRegistry` instantiates `LocalFs` directly from the platform path.
- **Android SAF exposure**: `fm-ffi/src/saf_jni.rs` bridges content-provider queries for `FileManagerDocumentsProvider.kt`.
- The UI queries `capabilities()` on each `Vfs` backend and hides actions that the backend cannot perform.

## Unknowns

Metadata that is not available stays `None`. A remote backend that does not
report a size does not report `0`; the UI renders "unknown".
