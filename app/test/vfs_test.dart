import 'dart:io';
import 'package:filemanager/src/rust/api/file_manager.dart';
import 'package:filemanager/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final dylibPath = '${Directory.current.path}/build/linux/x64/debug/bundle/lib/libfm_ffi.so';
    if (File(dylibPath).existsSync()) {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(dylibPath),
      );
    } else {
      await RustLib.init();
    }
  });

  test('VFS getCapabilities for local root', () {
    final caps = getCapabilities(root: '/tmp');
    expect(caps.read, isTrue);
    expect(caps.write, isTrue);
  });

  test('VFS listDir lists real filesystem entries', () async {
    final entries = await listDir(root: '/tmp', path: '');
    expect(entries, isNotNull);
  });
}
