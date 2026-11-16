import 'dart:io';
import 'package:filemanager/src/rust/api/file_manager.dart';
import 'package:filemanager/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Bridge integration tests: they need the compiled Rust library. CI builds
  // it and stages it at this path; a checkout without that build should
  // report a clear skip instead of failing setUpAll for the whole suite.
  final dylibPath =
      '${Directory.current.path}/build/linux/x64/debug/bundle/lib/libfm_ffi.so';
  final bridgeAvailable = File(dylibPath).existsSync();
  final skipReason =
      bridgeAvailable ? null : 'Rust bridge library not built (run cargo build -p fm_ffi)';

  setUpAll(() async {
    if (!bridgeAvailable) return;
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(dylibPath),
    );
  });

  test('VFS getCapabilities for local root', () async {
    final caps = await getCapabilities(root: '/tmp');
    expect(caps.read, isTrue);
    expect(caps.write, isTrue);
  }, skip: skipReason);

  test('VFS listDir lists real filesystem entries', () async {
    final entries = await listDir(root: '/tmp', path: '');
    expect(entries, isNotNull);
  }, skip: skipReason);
}
