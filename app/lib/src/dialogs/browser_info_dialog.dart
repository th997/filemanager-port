import 'dart:async';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entry_item.dart';
import '../rust/api/inspect.dart';
import '../services/path_utils.dart';
import '../services/platform_capabilities.dart';
import '../services/semantic_colors.dart';
import '../services/task_service.dart';

/// Formats Unix permission bits (e.g. `0755` / `0x1ED`) as `rwxr-xr-x (0755)`.
String formatUnixMode(int mode) {
  final perms = mode & 0x1FF;
  final buf = StringBuffer();
  for (final shift in [6, 3, 0]) {
    final triad = (perms >> shift) & 7;
    buf.write((triad & 4) != 0 ? 'r' : '-');
    buf.write((triad & 2) != 0 ? 'w' : '-');
    buf.write((triad & 1) != 0 ? 'x' : '-');
  }
  final octal = (mode & 0xFFF).toRadixString(8).padLeft(4, '0');
  return '$buf ($octal)';
}

/// Standalone File / Directory Properties dialog supporting:
/// - Recursive VFS directory sizing (local, remote, vault, archive) with
///   cancellation & timeout protection (never permanently stuck on "measuring").
/// - On-demand MD5 / SHA-1 / SHA-256 checksum computation & expected-hash verification.
/// - Unix permission (`chmod`) viewing and editing on Linux/macOS local & SFTP remotes.
Future<void> showBrowserInfoDialog(
  BuildContext context, {
  required String root,
  required EntryItem item,
  required String fullPath,
  required bool canModifyPermissions,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BrowserInfoDialog(
      root: root,
      item: item,
      fullPath: fullPath,
      canModifyPermissions: canModifyPermissions,
    ),
  );
}

class _BrowserInfoDialog extends StatefulWidget {
  final String root;
  final EntryItem item;
  final String fullPath;
  final bool canModifyPermissions;

  const _BrowserInfoDialog({
    required this.root,
    required this.item,
    required this.fullPath,
    required this.canModifyPermissions,
  });

  @override
  State<_BrowserInfoDialog> createState() => _BrowserInfoDialogState();
}

class _BrowserInfoDialogState extends State<_BrowserInfoDialog> {
  // Directory sizing state
  bool _measuringDir = false;
  DirMeasurementDto? _dirMeasurement;
  String? _dirMeasureError;
  String? _measureOpId;

  // Checksums state
  bool _hashing = false;
  FileHashesDto? _hashes;
  String? _hashError;
  String? _hashOpId;
  final TextEditingController _expectedHashController = TextEditingController();

  // Unix permissions state
  int? _unixMode;
  int _editedMode = 0;
  bool _savingMode = false;

  bool get _supportsUnixPerms =>
      (isNativeRoot(widget.root) &&
          PlatformCapabilities.supportsLocalUnixPermissions) ||
      widget.root.startsWith('remote://');

  @override
  void initState() {
    super.initState();
    // Auto-measure local directories; for remote/vault/archive offer instant
    // on-demand VFS measurement (with cancel & timeout protection) or click button.
    if (widget.item.isDir && isNativeRoot(widget.root)) {
      _startMeasureDirectory();
    }
    if (_supportsUnixPerms) {
      _loadPermissions();
    }
  }

  @override
  void dispose() {
    if (_measureOpId != null) cancelInspectOp(opId: _measureOpId!);
    if (_hashOpId != null) cancelInspectOp(opId: _hashOpId!);
    _expectedHashController.dispose();
    super.dispose();
  }

  Future<void> _startMeasureDirectory() async {
    final opId = 'dir_${DateTime.now().microsecondsSinceEpoch}';
    _measureOpId = opId;
    setState(() {
      _measuringDir = true;
      _dirMeasureError = null;
    });
    try {
      final m = await measureVfsDirectory(
        root: widget.root,
        path: widget.item.path,
        opId: opId,
        maxEntries: 50000,
        timeoutMs: 15000,
      );
      if (!mounted || _measureOpId != opId) return;
      setState(() {
        _dirMeasurement = m;
        _measuringDir = false;
      });
    } catch (e) {
      if (!mounted || _measureOpId != opId) return;
      setState(() {
        _dirMeasureError = '$e';
        _measuringDir = false;
      });
    }
  }

  void _cancelMeasure() {
    if (_measureOpId != null) {
      cancelInspectOp(opId: _measureOpId!);
    }
    setState(() => _measuringDir = false);
  }

  Future<void> _computeHashes() async {
    final opId = 'hash_${DateTime.now().microsecondsSinceEpoch}';
    _hashOpId = opId;
    setState(() {
      _hashing = true;
      _hashError = null;
    });
    try {
      final res = await computeFileHashes(
        root: widget.root,
        path: widget.item.path,
        opId: opId,
      );
      if (!mounted || _hashOpId != opId) return;
      setState(() {
        _hashes = res;
        _hashing = false;
      });
    } catch (e) {
      if (!mounted || _hashOpId != opId) return;
      setState(() {
        _hashError = '$e';
        _hashing = false;
      });
    }
  }

  Future<void> _loadPermissions() async {
    try {
      final mode = await getUnixPermissions(
        root: widget.root,
        path: widget.item.path,
      );
      if (!mounted || mode == null) return;
      setState(() {
        _unixMode = mode;
        _editedMode = mode & 0x1FF;
      });
    } catch (_) {
      // Backend doesn't support Unix permissions (e.g. S3/WebDAV/SMB) — hide section.
    }
  }

  Future<void> _applyPermissions() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _savingMode = true);
    try {
      await setUnixPermissions(
        root: widget.root,
        path: widget.item.path,
        mode: _editedMode,
      );
      if (!mounted) return;
      setState(() {
        _unixMode = _editedMode;
        _savingMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.permissionsUpdated(formatUnixMode(_editedMode))),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildHashRow(String label, String digest) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: SelectableText(
              digest,
              style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 14),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: digest));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copied'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  bool? _checkHashMatch() {
    final hashes = _hashes;
    final expected = _expectedHashController.text.trim().toLowerCase();
    if (hashes == null || expected.isEmpty) return null;
    return expected == hashes.md5.toLowerCase() ||
        expected == hashes.sha1.toLowerCase() ||
        expected == hashes.sha256.toLowerCase();
  }

  Widget _buildPermRow(String label, int shift) {
    bool hasBit(int bit) => ((_editedMode >> shift) & bit) != 0;
    void toggleBit(int bit) {
      setState(() {
        _editedMode ^= (bit << shift);
      });
    }

    return Row(
      children: [
        SizedBox(width: 66, child: Text(label, style: const TextStyle(fontSize: 12))),
        for (final entry in const [(4, 'R'), (2, 'W'), (1, 'X')])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                visualDensity: VisualDensity.compact,
                value: hasBit(entry.$1),
                onChanged: widget.canModifyPermissions ? (_) => toggleBit(entry.$1) : null,
              ),
              Text(entry.$2, style: const TextStyle(fontSize: 11.5)),
              const SizedBox(width: 4),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final dot = item.name.lastIndexOf('.');
    final ext = !item.isDir && dot > 0 ? item.name.substring(dot + 1).toUpperCase() : null;
    final hashMatch = _checkHashMatch();

    return AlertDialog(
      title: Text(l10n.properties),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(l10n.nameLabel, item.name),
              _infoRow(l10n.pathLabel, widget.fullPath),
              if (ext != null) _infoRow(l10n.extensionLabel, ext),
              if (item.isDir)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(
                          l10n.sizeLabel,
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(
                        child: _measuringDir
                            ? Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(l10n.measuring, style: const TextStyle(fontSize: 12)),
                                  const SizedBox(width: 6),
                                  TextButton(
                                    onPressed: _cancelMeasure,
                                    child: Text(l10n.cancel, style: const TextStyle(fontSize: 11)),
                                  ),
                                ],
                              )
                            : _dirMeasurement != null
                                ? Text(
                                    '${formatBytes(_dirMeasurement!.totalBytes)} '
                                    '(${_dirMeasurement!.fileCount} files, ${_dirMeasurement!.dirCount} dirs'
                                    '${_dirMeasurement!.truncated ? ", partial" : ""})',
                                    style: const TextStyle(fontSize: 12),
                                  )
                                : Row(
                                    children: [
                                      if (_dirMeasureError != null)
                                        Expanded(
                                          child: Text(
                                            _dirMeasureError!,
                                            style: TextStyle(fontSize: 11, color: scheme.error),
                                          ),
                                        ),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.calculate_outlined, size: 15),
                                        label: Text(l10n.calculateDirSize),
                                        onPressed: _startMeasureDirectory,
                                      ),
                                    ],
                                  ),
                      ),
                    ],
                  ),
                )
              else
                _infoRow(l10n.sizeLabel, item.formattedSize),
              if (item.modified != null)
                _infoRow(l10n.modifiedLabel, item.modified!.toLocal().toString().split('.').first),

              // File Checksums section (MD5 / SHA-1 / SHA-256)
              if (!item.isDir) ...[
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.checksumsTitle,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_hashing)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      TextButton.icon(
                        icon: const Icon(Icons.verified_outlined, size: 16),
                        label: Text(l10n.computeChecksums),
                        onPressed: _computeHashes,
                      ),
                  ],
                ),
                if (_hashError != null)
                  Text(_hashError!, style: TextStyle(fontSize: 11, color: scheme.error)),
                if (_hashes != null) ...[
                  _buildHashRow('MD5', _hashes!.md5),
                  _buildHashRow('SHA-1', _hashes!.sha1),
                  _buildHashRow('SHA-256', _hashes!.sha256),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _expectedHashController,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l10n.expectedHashHint,
                      border: const OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (hashMatch != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          hashMatch ? Icons.check_circle : Icons.error,
                          size: 16,
                          color: hashMatch ? scheme.success : scheme.error,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          hashMatch ? l10n.hashMatches : l10n.hashMismatch,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: hashMatch ? scheme.success : scheme.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],

              // Unix Permissions (chmod) section
              if (_unixMode != null) ...[
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l10n.unixPermissions}: ${formatUnixMode(_editedMode)}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildPermRow(l10n.permOwner, 6),
                _buildPermRow(l10n.permGroup, 3),
                _buildPermRow(l10n.permOther, 0),
                if (widget.canModifyPermissions && _editedMode != (_unixMode! & 0x1FF))
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: _savingMode ? null : _applyPermissions,
                      child: _savingMode
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.applyPermissions),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.fullPath));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.pathCopied)),
            );
          },
          child: Text(l10n.copyPath),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
