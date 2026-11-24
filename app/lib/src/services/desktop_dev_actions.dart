import 'dart:io';

/// Desktop developer workflow actions: open folder in terminal, open folder/file
/// in an external code editor, and path resolvers.
class DesktopDevActions {
  DesktopDevActions._();

  static ({String executable, List<String> arguments})? resolveTerminalCommand(
    String directoryPath, {
    String? operatingSystem,
    bool Function(String)? commandExists,
  }) {
    final dir = directoryPath.trim();
    if (dir.isEmpty) return null;
    final os = (operatingSystem ?? Platform.operatingSystem).toLowerCase();
    final exists = commandExists ?? _commandExistsSync;

    if (os == 'macos') {
      return (executable: 'open', arguments: ['-a', 'Terminal', dir]);
    }
    if (os == 'windows') {
      if (exists('wt')) {
        return (executable: 'wt', arguments: ['-d', dir]);
      }
      return (
        executable: 'cmd',
        arguments: ['/c', 'start', 'cmd.exe', '/K', 'cd', '/d', dir],
      );
    }
    if (os == 'linux') {
      const candidates = [
        'x-terminal-emulator',
        'gnome-terminal',
        'konsole',
        'xfce4-terminal',
        'alacritty',
        'kitty',
        'wezterm',
        'xterm',
      ];
      for (final bin in candidates) {
        if (!exists(bin)) continue;
        if (bin == 'gnome-terminal' ||
            bin == 'xfce4-terminal' ||
            bin == 'alacritty') {
          return (executable: bin, arguments: ['--working-directory', dir]);
        }
        if (bin == 'konsole') {
          return (executable: bin, arguments: ['--workdir', dir]);
        }
        if (bin == 'wezterm') {
          return (executable: bin, arguments: ['start', '--cwd', dir]);
        }
        if (bin == 'kitty') {
          return (executable: bin, arguments: ['--directory', dir]);
        }
        return (executable: bin, arguments: const []);
      }
      return (
        executable: 'x-terminal-emulator',
        arguments: const [],
      );
    }
    return null;
  }

  static ({String executable, List<String> arguments})? resolveEditorCommand(
    String targetPath, {
    String? operatingSystem,
    bool Function(String)? commandExists,
  }) {
    final target = targetPath.trim();
    if (target.isEmpty) return null;
    final os = (operatingSystem ?? Platform.operatingSystem).toLowerCase();
    final exists = commandExists ?? _commandExistsSync;

    for (final bin in const ['code', 'cursor', 'codium', 'zed', 'subl']) {
      if (exists(bin)) {
        return (executable: bin, arguments: [target]);
      }
    }

    if (os == 'macos') {
      return (
        executable: 'open',
        arguments: ['-a', 'Visual Studio Code', target],
      );
    }
    if (os == 'windows') {
      return (executable: 'cmd', arguments: ['/c', 'start', '', 'code', target]);
    }
    if (os == 'linux') {
      return (executable: 'xdg-open', arguments: [target]);
    }
    return null;
  }

  static bool _commandExistsSync(String executable) {
    try {
      final finder = Platform.isWindows ? 'where' : 'which';
      final res = Process.runSync(finder, [executable]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openTerminalAt(String dirPath) async {
    final cmd = resolveTerminalCommand(dirPath);
    if (cmd == null) return false;
    if (!Directory(dirPath).existsSync()) return false;
    try {
      await Process.start(
        cmd.executable,
        cmd.arguments,
        workingDirectory: dirPath,
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openInCodeEditor(String targetPath) async {
    final cmd = resolveEditorCommand(targetPath);
    if (cmd == null) return false;
    if (FileSystemEntity.typeSync(targetPath) == FileSystemEntityType.notFound) {
      return false;
    }
    try {
      await Process.start(
        cmd.executable,
        cmd.arguments,
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
