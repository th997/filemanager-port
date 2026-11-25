import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../rust/api/remotes.dart';
import '../services/platform_capabilities.dart';
import '../services/remote_transfer_service.dart';
import '../services/semantic_colors.dart';

enum RemoteBatchExportMethod { saveFile, shareFile, copyClipboard }

class RemoteBatchExportOutcome {
  final int count;
  final RemoteBatchExportMethod method;
  final String? savedPath;

  const RemoteBatchExportOutcome({
    required this.count,
    required this.method,
    this.savedPath,
  });
}

class _ImportFileTooLargeException implements Exception {
  const _ImportFileTooLargeException();
}

String _formatRemoteSubtitle(RemoteConfigDto r) {
  final kind = r.kind.toUpperCase();
  if (r.endpoint != null && r.endpoint!.isNotEmpty) {
    final base = r.endpoint!;
    return r.bucket != null && r.bucket!.isNotEmpty
        ? '$kind • $base (${r.bucket})'
        : '$kind • $base';
  }
  if (r.bucket != null && r.bucket!.isNotEmpty) {
    return '$kind • ${r.bucket}';
  }
  final portSuffix = r.port != null ? ':${r.port}' : '';
  final host = r.host ?? r.rootPath ?? '';
  return host.isEmpty ? kind : '$kind • $host$portSuffix';
}

String _translateBundleError(AppLocalizations l10n, RemoteBundleException e) {
  switch (e.code) {
    case RemoteBundleErrorCode.emptyPassword:
      return l10n.remoteBatchImportPasswordHint;
    case RemoteBundleErrorCode.passwordTooShort:
      return l10n.remoteBatchPasswordTooShort(
        RemoteTransferService.minExportPasswordLength,
      );
    case RemoteBundleErrorCode.noRemotesSelected:
      return l10n.remoteBatchNoReadableToExport;
    case RemoteBundleErrorCode.invalidFormat:
      return l10n.remoteBatchErrorInvalidFormat;
    case RemoteBundleErrorCode.notEncrypted:
      return l10n.remoteBatchErrorNotEncrypted;
    case RemoteBundleErrorCode.wrongPasswordOrCorrupted:
      return l10n.remoteBatchErrorWrongPassword;
    case RemoteBundleErrorCode.emptyBundle:
      return l10n.remoteBatchErrorEmptyBundle;
  }
}

Rect? _dialogShareOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox &&
      renderObject.hasSize &&
      !renderObject.size.isEmpty) {
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
  return null;
}

class RemoteBatchExportDialog extends StatefulWidget {
  final List<RemoteConfigDto> remotes;
  final BundleEncryptFn? encryptFn;
  final Future<String?> Function(String suggestedName, String encryptedContent)?
      saveFileFn;
  final Future<void> Function(
    String fileName,
    String encryptedContent,
    Rect? shareOrigin,
  )? shareFileFn;
  final Future<void> Function(String encryptedContent)? copyClipboardFn;

  const RemoteBatchExportDialog({
    super.key,
    required this.remotes,
    this.encryptFn,
    this.saveFileFn,
    this.shareFileFn,
    this.copyClipboardFn,
  });

  static Future<RemoteBatchExportOutcome?> show(
    BuildContext context, {
    required List<RemoteConfigDto> remotes,
  }) {
    return showDialog<RemoteBatchExportOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RemoteBatchExportDialog(remotes: remotes),
    );
  }

  @override
  State<RemoteBatchExportDialog> createState() =>
      _RemoteBatchExportDialogState();
}

class _RemoteBatchExportDialogState extends State<RemoteBatchExportDialog> {
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  late final Set<String> _selectedIds;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedIds = {
      for (final r in widget.remotes)
        if (RemoteTransferService.isReadableRemote(r)) r.id,
    };
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  List<RemoteConfigDto> get _readableRemotes =>
      widget.remotes.where(RemoteTransferService.isReadableRemote).toList();

  List<RemoteConfigDto> get _selectedRemotes => widget.remotes
      .where(
        (r) =>
            RemoteTransferService.isReadableRemote(r) &&
            _selectedIds.contains(r.id),
      )
      .toList();

  bool get _allReadableSelected {
    final readable = _readableRemotes;
    return readable.isNotEmpty &&
        readable.every((r) => _selectedIds.contains(r.id));
  }

  bool get _isPasswordValid {
    final pwd = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    return pwd.length >= RemoteTransferService.minExportPasswordLength &&
        pwd == confirm;
  }

  String? _passwordInlineHint(AppLocalizations l10n) {
    final pwd = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pwd.isNotEmpty &&
        pwd.length < RemoteTransferService.minExportPasswordLength) {
      return l10n.remoteBatchPasswordTooShort(
        RemoteTransferService.minExportPasswordLength,
      );
    }
    if (confirm.isNotEmpty && pwd != confirm) {
      return l10n.remoteBatchPasswordMismatch;
    }
    return null;
  }

  bool get _canExport =>
      !_busy && _selectedIds.isNotEmpty && _isPasswordValid;

  void _toggleSelectAll() {
    setState(() {
      _error = null;
      if (_allReadableSelected) {
        _selectedIds.clear();
      } else {
        for (final r in _readableRemotes) {
          _selectedIds.add(r.id);
        }
      }
    });
  }

  Future<String?> _defaultSaveFile(
    String suggestedName,
    String encryptedContent,
  ) async {
    final loc = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Encrypted Remotes Backup',
          extensions: [RemoteTransferService.fileExtension],
        ),
      ],
    );
    if (loc == null) return null;
    await File(loc.path).writeAsString(encryptedContent);
    return loc.path;
  }

  Future<void> _defaultShareFile(
    String fileName,
    String encryptedContent,
    Rect? shareOrigin,
  ) async {
    final tempRoot = await getTemporaryDirectory();
    final exportDir = Directory(p.join(tempRoot.path, 'fm_remote_exports'));
    if (exportDir.existsSync()) {
      try {
        for (final entity in exportDir.listSync()) {
          if (entity is File) {
            entity.deleteSync();
          }
        }
      } catch (_) {}
    } else {
      exportDir.createSync(recursive: true);
    }
    final outFile = File(p.join(exportDir.path, fileName));
    await outFile.writeAsString(encryptedContent);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            outFile.path,
            name: fileName,
            mimeType: 'application/json',
          ),
        ],
        subject: fileName,
        sharePositionOrigin: shareOrigin,
      ),
    );
  }

  Future<void> _runExport(RemoteBatchExportMethod method) async {
    final l10n = AppLocalizations.of(context);
    final selected = _selectedRemotes;
    if (selected.isEmpty) {
      setState(() => _error = l10n.remoteBatchNoReadableToExport);
      return;
    }
    final pwd = _passwordCtrl.text;
    if (pwd.length < RemoteTransferService.minExportPasswordLength) {
      setState(
        () => _error = l10n.remoteBatchPasswordTooShort(
          RemoteTransferService.minExportPasswordLength,
        ),
      );
      return;
    }
    if (pwd != _confirmCtrl.text) {
      setState(() => _error = l10n.remoteBatchPasswordMismatch);
      return;
    }

    final shareOrigin = _dialogShareOrigin(context);
    setState(() {
      _busy = true;
      _error = null;
    });

    // Yield one frame so the loading spinner renders before synchronous KDF.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;

    try {
      final encrypted = RemoteTransferService.encryptRemotesBundle(
        selected,
        password: pwd,
        encryptFn: widget.encryptFn,
      );
      final fileName = RemoteTransferService.suggestedExportFileName();

      switch (method) {
        case RemoteBatchExportMethod.saveFile:
          final save = widget.saveFileFn ?? _defaultSaveFile;
          final savedPath = await save(fileName, encrypted);
          if (!mounted) return;
          if (savedPath == null) {
            setState(() => _busy = false);
            return;
          }
          Navigator.of(context).pop(
            RemoteBatchExportOutcome(
              count: selected.length,
              method: RemoteBatchExportMethod.saveFile,
              savedPath: savedPath,
            ),
          );
        case RemoteBatchExportMethod.shareFile:
          final share = widget.shareFileFn ?? _defaultShareFile;
          await share(fileName, encrypted, shareOrigin);
          if (!mounted) return;
          Navigator.of(context).pop(
            RemoteBatchExportOutcome(
              count: selected.length,
              method: RemoteBatchExportMethod.shareFile,
            ),
          );
        case RemoteBatchExportMethod.copyClipboard:
          if (widget.copyClipboardFn != null) {
            await widget.copyClipboardFn!(encrypted);
          } else {
            await Clipboard.setData(ClipboardData(text: encrypted));
          }
          if (!mounted) return;
          Navigator.of(context).pop(
            RemoteBatchExportOutcome(
              count: selected.length,
              method: RemoteBatchExportMethod.copyClipboard,
            ),
          );
      }
    } on RemoteBundleException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _translateBundleError(l10n, e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.exportFailed('$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final readableCount = _readableRemotes.length;
    final selectedCount = _selectedRemotes.length;
    final inlineWarning = _error ?? _passwordInlineHint(l10n);
    final useDesktopSave = PlatformCapabilities.isDesktop;

    return AlertDialog(
      title: Text(l10n.remoteBatchExportTitle),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.remoteBatchExportSubtitle,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.remoteBatchSelectCount(selectedCount, readableCount),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        _busy || readableCount == 0 ? null : _toggleSelectAll,
                    child: Text(
                      _allReadableSelected
                          ? l10n.remoteBatchDeselectAll
                          : l10n.remoteBatchSelectAll,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final r in widget.remotes)
                          CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: RemoteTransferService.isReadableRemote(r) &&
                                _selectedIds.contains(r.id),
                            onChanged: _busy ||
                                    !RemoteTransferService.isReadableRemote(r)
                                ? null
                                : (checked) {
                                    setState(() {
                                      _error = null;
                                      if (checked == true) {
                                        _selectedIds.add(r.id);
                                      } else {
                                        _selectedIds.remove(r.id);
                                      }
                                    });
                                  },
                            title: Text(
                              r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              RemoteTransferService.isReadableRemote(r)
                                  ? _formatRemoteSubtitle(r)
                                  : l10n.remoteBatchUnreadableSkipped,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('remote_batch_export_password'),
                controller: _passwordCtrl,
                enabled: !_busy,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: l10n.remoteBatchExportPasswordLabel,
                  hintText: l10n.remoteBatchExportPasswordHint(
                    RemoteTransferService.minExportPasswordLength,
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('remote_batch_export_confirm_password'),
                controller: _confirmCtrl,
                enabled: !_busy,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) {
                  if (_canExport) {
                    _runExport(
                      useDesktopSave
                          ? RemoteBatchExportMethod.saveFile
                          : RemoteBatchExportMethod.shareFile,
                    );
                  }
                },
                decoration: InputDecoration(
                  labelText: l10n.remoteBatchExportPasswordConfirmLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.remoteBatchPasswordRequiredNote,
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
              if (inlineWarning != null) ...[
                const SizedBox(height: 8),
                Text(
                  inlineWarning,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: _canExport
              ? () => _runExport(RemoteBatchExportMethod.copyClipboard)
              : null,
          child: Text(l10n.copyEncryptedAction),
        ),
        FilledButton.icon(
          onPressed: _canExport
              ? () => _runExport(
                    useDesktopSave
                        ? RemoteBatchExportMethod.saveFile
                        : RemoteBatchExportMethod.shareFile,
                  )
              : null,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  useDesktopSave ? Icons.save_alt_outlined : Icons.share_outlined,
                  size: 18,
                ),
          label: Text(
            useDesktopSave
                ? l10n.remoteBatchSaveFileAction
                : l10n.remoteBatchShareFileAction,
          ),
        ),
      ],
    );
  }
}

class RemoteBatchImportDialog extends StatefulWidget {
  final List<RemoteConfigDto> existingRemotes;
  final BundleDecryptFn? decryptFn;
  final Future<({String name, String content, int sizeBytes})?> Function()?
      pickFileFn;
  final Future<String?> Function()? readClipboardFn;
  final SaveRemoteBatchFn? saveBatchFn;

  const RemoteBatchImportDialog({
    super.key,
    required this.existingRemotes,
    this.decryptFn,
    this.pickFileFn,
    this.readClipboardFn,
    this.saveBatchFn,
  });

  static Future<RemoteBatchImportResult?> show(
    BuildContext context, {
    required List<RemoteConfigDto> existingRemotes,
  }) {
    return showDialog<RemoteBatchImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RemoteBatchImportDialog(existingRemotes: existingRemotes),
    );
  }

  @override
  State<RemoteBatchImportDialog> createState() =>
      _RemoteBatchImportDialogState();
}

class _RemoteBatchImportDialogState extends State<RemoteBatchImportDialog> {
  final TextEditingController _pasteCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _busy = false;
  bool _clipboardDetected = false;
  String? _selectedFileName;
  String? _selectedFileContent;
  String? _error;

  DecodedRemotesBundle? _decodedBundle;
  final Set<int> _selectedIndices = {};
  RemoteImportConflictStrategy _strategy = RemoteImportConflictStrategy.skip;

  @override
  void initState() {
    super.initState();
    _peekClipboard();
  }

  @override
  void dispose() {
    _pasteCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String get _effectiveRawContent =>
      _selectedFileContent ?? _pasteCtrl.text.trim();

  Future<void> _peekClipboard() async {
    try {
      final text = widget.readClipboardFn != null
          ? await widget.readClipboardFn!()
          : (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted || text == null || text.trim().isEmpty) return;
      if (_selectedFileContent != null || _pasteCtrl.text.trim().isNotEmpty) {
        return;
      }
      if (RemoteTransferService.looksLikeEncryptedEnvelope(text)) {
        setState(() {
          _pasteCtrl.text = text.trim();
          _clipboardDetected = true;
        });
      }
    } catch (_) {}
  }

  Future<({String name, String content, int sizeBytes})?> _defaultPickFile() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Encrypted Remotes Backup',
          extensions: ['fmremotes', 'fmbak', 'json'],
          mimeTypes: [
            'application/json',
            'text/plain',
            'application/octet-stream',
          ],
          uniformTypeIdentifiers: [
            'public.json',
            'public.plain-text',
            'public.data',
            'public.item',
          ],
        ),
        XTypeGroup(label: 'All files'),
      ],
    );
    if (file == null) return null;
    final sizeBytes = await file.length();
    if (sizeBytes > RemoteTransferService.maxImportFileBytes) {
      throw const _ImportFileTooLargeException();
    }
    final content = await file.readAsString();
    final name = file.name.isNotEmpty ? file.name : p.basename(file.path);
    return (name: name, content: content, sizeBytes: sizeBytes);
  }

  Future<void> _chooseFile() async {
    final l10n = AppLocalizations.of(context);
    try {
      final picked =
          await (widget.pickFileFn?.call() ?? _defaultPickFile());
      if (!mounted || picked == null) return;
      if (picked.sizeBytes > RemoteTransferService.maxImportFileBytes) {
        setState(() => _error = l10n.remoteBatchErrorFileTooLarge);
        return;
      }
      setState(() {
        _selectedFileName = picked.name;
        _selectedFileContent = picked.content;
        _clipboardDetected = false;
        _error = null;
      });
    } on _ImportFileTooLargeException {
      if (!mounted) return;
      setState(() => _error = l10n.remoteBatchErrorFileTooLarge);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l10n.importFailed('$e'));
    }
  }

  Future<void> _pasteFromClipboard() async {
    final l10n = AppLocalizations.of(context);
    try {
      final text = widget.readClipboardFn != null
          ? await widget.readClipboardFn!()
          : (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted) return;
      final trimmed = text?.trim() ?? '';
      if (trimmed.isEmpty) {
        setState(() => _error = l10n.remoteBatchClipboardEmpty);
        return;
      }
      setState(() {
        _selectedFileName = null;
        _selectedFileContent = null;
        _pasteCtrl.text = trimmed;
        _clipboardDetected =
            RemoteTransferService.looksLikeEncryptedEnvelope(trimmed);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l10n.importFailed('$e'));
    }
  }

  Future<void> _decryptAndPreview() async {
    final l10n = AppLocalizations.of(context);
    final raw = _effectiveRawContent;
    final pwd = _passwordCtrl.text;
    if (raw.isEmpty || pwd.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;

    try {
      final decoded = RemoteTransferService.decryptRemotesBundle(
        raw,
        password: pwd,
        decryptFn: widget.decryptFn,
      );
      setState(() {
        _busy = false;
        _decodedBundle = decoded;
        _selectedIndices
          ..clear()
          ..addAll(List.generate(decoded.remotes.length, (i) => i));
      });
    } on RemoteBundleException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _translateBundleError(l10n, e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.importFailed('$e');
      });
    }
  }

  Future<void> _confirmImport(List<RemoteImportPlanItem> plan) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await RemoteTransferService.executeImportPlan(
        plan: plan,
        saveBatchFn: widget.saveBatchFn,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.importFailed('$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final decoded = _decodedBundle;
    if (decoded == null) {
      return _buildLoadStep(context, l10n);
    }
    return _buildPreviewStep(context, l10n, decoded);
  }

  Widget _buildLoadStep(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final canDecrypt = !_busy &&
        _effectiveRawContent.isNotEmpty &&
        _passwordCtrl.text.isNotEmpty;

    return AlertDialog(
      title: Text(l10n.remoteBatchImportTitle),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _chooseFile,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: Text(l10n.remoteBatchChooseFile),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_outlined, size: 18),
                    label: Text(l10n.remoteBatchPasteClipboard),
                  ),
                ],
              ),
              if (_clipboardDetected && _selectedFileContent == null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.remoteBatchClipboardDetected,
                          style: TextStyle(fontSize: 12, color: scheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (_selectedFileName != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.remoteBatchSelectedFileLabel(_selectedFileName!),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _selectedFileName = null;
                                  _selectedFileContent = null;
                                  _error = null;
                                }),
                      ),
                    ],
                  ),
                )
              else
                TextField(
                  key: const ValueKey('remote_batch_import_paste'),
                  controller: _pasteCtrl,
                  enabled: !_busy,
                  maxLines: 4,
                  onChanged: (_) => setState(() {
                    _clipboardDetected = false;
                    _error = null;
                  }),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: l10n.remoteBatchPasteFieldHint,
                    isDense: true,
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('remote_batch_import_password'),
                controller: _passwordCtrl,
                enabled: !_busy,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) {
                  if (canDecrypt) _decryptAndPreview();
                },
                decoration: InputDecoration(
                  labelText: l10n.remoteBatchImportPasswordLabel,
                  hintText: l10n.remoteBatchImportPasswordHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: canDecrypt ? _decryptAndPreview : null,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_open_outlined, size: 18),
          label: Text(l10n.remoteBatchDecryptAction),
        ),
      ],
    );
  }

  Widget _buildPreviewStep(
    BuildContext context,
    AppLocalizations l10n,
    DecodedRemotesBundle decoded,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final allRemotes = decoded.remotes;
    final selectedRemotes = <RemoteConfigDto>[
      for (var i = 0; i < allRemotes.length; i++)
        if (_selectedIndices.contains(i)) allRemotes[i],
    ];
    final plan = RemoteTransferService.buildImportPlan(
      incoming: selectedRemotes,
      existing: widget.existingRemotes,
      strategy: _strategy,
    );
    final existingIds = widget.existingRemotes.map((e) => e.id).toSet();
    final hasAnyConflict = allRemotes.any((r) => existingIds.contains(r.id));

    final planByIndex = <int, RemoteImportPlanItem>{};
    var planCursor = 0;
    for (var i = 0; i < allRemotes.length; i++) {
      if (_selectedIndices.contains(i)) {
        planByIndex[i] = plan[planCursor++];
      }
    }

    final actionableCount = plan
        .where((item) => item.action != RemoteImportItemAction.skip)
        .length;
    final allSelected =
        allRemotes.isNotEmpty && _selectedIndices.length == allRemotes.length;

    return AlertDialog(
      title: Text(l10n.remoteBatchImportTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.remoteBatchPreviewSummary(allRemotes.length),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.success,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              if (allSelected) {
                                _selectedIndices.clear();
                              } else {
                                _selectedIndices.addAll(
                                  List.generate(allRemotes.length, (i) => i),
                                );
                              }
                            }),
                    child: Text(
                      allSelected
                          ? l10n.remoteBatchDeselectAll
                          : l10n.remoteBatchSelectAll,
                    ),
                  ),
                ],
              ),
              if (hasAnyConflict) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.remoteBatchConflictSectionLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                SegmentedButton<RemoteImportConflictStrategy>(
                  segments: [
                    ButtonSegment(
                      value: RemoteImportConflictStrategy.skip,
                      label: Text(l10n.remoteBatchConflictSkip),
                    ),
                    ButtonSegment(
                      value: RemoteImportConflictStrategy.overwrite,
                      label: Text(l10n.remoteBatchConflictOverwrite),
                    ),
                    ButtonSegment(
                      value: RemoteImportConflictStrategy.keepBoth,
                      label: Text(l10n.remoteBatchConflictKeepBoth),
                    ),
                  ],
                  selected: {_strategy},
                  onSelectionChanged: _busy
                      ? null
                      : (next) {
                          if (next.isNotEmpty) {
                            setState(() => _strategy = next.first);
                          }
                        },
                ),
              ],
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 230),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < allRemotes.length; i++)
                          _buildPreviewTile(
                            l10n: l10n,
                            scheme: scheme,
                            remote: allRemotes[i],
                            selected: _selectedIndices.contains(i),
                            alreadyExists: existingIds.contains(allRemotes[i].id),
                            planItem: planByIndex[i],
                            onChanged: _busy
                                ? null
                                : (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedIndices.add(i);
                                      } else {
                                        _selectedIndices.remove(i);
                                      }
                                    });
                                  },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_selectedIndices.isNotEmpty && actionableCount == 0) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.remoteBatchAllSkippedHint,
                  style: TextStyle(fontSize: 12, color: scheme.warning),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _decodedBundle = null;
                    _selectedIndices.clear();
                    _error = null;
                  }),
          child: Text(l10n.remoteBatchBackStep),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed:
              !_busy && actionableCount > 0 ? () => _confirmImport(plan) : null,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.remoteBatchImportConfirm(actionableCount)),
        ),
      ],
    );
  }

  Widget _buildPreviewTile({
    required AppLocalizations l10n,
    required ColorScheme scheme,
    required RemoteConfigDto remote,
    required bool selected,
    required bool alreadyExists,
    required RemoteImportPlanItem? planItem,
    required ValueChanged<bool?>? onChanged,
  }) {
    final badgeColor = alreadyExists ? scheme.warning : scheme.primary;
    final badgeLabel =
        alreadyExists ? l10n.remoteBatchBadgeExists : l10n.remoteBatchBadgeNew;
    final isDuplicating =
        planItem?.action == RemoteImportItemAction.duplicate;
    final subtitle = isDuplicating
        ? '${_formatRemoteSubtitle(remote)} → ${planItem!.resolved.name}'
        : _formatRemoteSubtitle(remote);

    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: selected,
      onChanged: onChanged,
      title: Row(
        children: [
          Expanded(
            child: Text(
              remote.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeLabel,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5),
      ),
    );
  }
}
