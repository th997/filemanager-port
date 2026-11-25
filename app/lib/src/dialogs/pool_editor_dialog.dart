import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../rust/api/pool.dart';
import '../rust/api/remotes.dart';
import 'folder_picker_dialog.dart';

class _EditableNodeEntry {
  final RemoteConfigDto remote;
  bool selected;
  final TextEditingController domainCtrl;
  final TextEditingController quotaGbCtrl;
  final TextEditingController weightCtrl;
  final TextEditingController prefixCtrl;
  String role;
  bool isMetaBackup;

  _EditableNodeEntry({
    required this.remote,
    required this.selected,
    required String domain,
    required double quotaGb,
    required int weight,
    required String prefix,
    required this.role,
    required this.isMetaBackup,
  }) : domainCtrl = TextEditingController(text: domain),
       quotaGbCtrl = TextEditingController(
         text: quotaGb == quotaGb.roundToDouble()
             ? quotaGb.toInt().toString()
             : quotaGb.toStringAsFixed(1),
       ),
       weightCtrl = TextEditingController(text: weight.toString()),
       prefixCtrl = TextEditingController(text: prefix);

  void dispose() {
    domainCtrl.dispose();
    quotaGbCtrl.dispose();
    weightCtrl.dispose();
    prefixCtrl.dispose();
  }
}

class PoolEditorDialog extends StatefulWidget {
  final PoolConfigDto? existing;
  final List<RemoteConfigDto> remotes;
  @visibleForTesting
  final Future<String?> Function(RemoteConfigDto remote, String currentPath)?
      onPickNodeDirectory;

  const PoolEditorDialog({
    super.key,
    this.existing,
    required this.remotes,
    this.onPickNodeDirectory,
  });

  static Future<PoolConfigDto?> show(
    BuildContext context, {
    PoolConfigDto? existing,
    required List<RemoteConfigDto> remotes,
    @visibleForTesting
    Future<String?> Function(RemoteConfigDto remote, String currentPath)?
        onPickNodeDirectory,
  }) {
    return showDialog<PoolConfigDto>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PoolEditorDialog(
        existing: existing,
        remotes: remotes,
        onPickNodeDirectory: onPickNodeDirectory,
      ),
    );
  }

  @override
  State<PoolEditorDialog> createState() => _PoolEditorDialogState();
}

class _PoolEditorDialogState extends State<PoolEditorDialog> {
  static const List<int> _chunkOptionsMb = [4, 8, 16, 32];
  static const int _maxReplicationFactor = 16;
  static const int _bytesPerGb = 1024 * 1024 * 1024;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _passphraseCtrl;
  late final TextEditingController _passphraseConfirmCtrl;
  late int _chunkMb;
  late int _replicationFactor;
  late bool _encrypt;
  bool _obscurePassphrase = true;
  late List<_EditableNodeEntry> _nodeEntries;
  String? _errorText;

  List<int> get _replicationOptions {
    final upper = [3, _nodeEntries.length, _replicationFactor]
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, _maxReplicationFactor);
    return [for (int i = 1; i <= upper; i++) i];
  }

  String _normalizePrefixInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed == '/') return '/';
    final cleaned = trimmed.replaceAll(RegExp(r'^/+|/+$'), '');
    return cleaned.isEmpty ? 'fm_pool' : cleaned;
  }

  Future<void> _pickNodeDirectory(_EditableNodeEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final raw = entry.prefixCtrl.text.trim();
    final currentRel =
        raw == '/' ? '' : raw.replaceAll(RegExp(r'^/+|/+$'), '');
    String? pickedRel;
    if (widget.onPickNodeDirectory != null) {
      pickedRel =
          await widget.onPickNodeDirectory!(entry.remote, currentRel);
    } else {
      final picked = await FolderPickerDialog.show(
        context,
        title: '${l10n.poolPickDirectory} · ${entry.remote.name}',
        initialRoot: 'remote://${entry.remote.id}',
        initialPath: currentRel,
        confirmLabel: l10n.selectFolderAction,
        lockRoot: true,
      );
      if (picked != null) {
        pickedRel = picked.relPath;
      }
    }
    if (!mounted || pickedRel == null) return;
    final clean = pickedRel.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    setState(() {
      entry.prefixCtrl.text = clean.isEmpty ? '/' : clean;
    });
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _passphraseCtrl = TextEditingController();
    _passphraseConfirmCtrl = TextEditingController();
    final existingMb = existing == null
        ? 16
        : (existing.chunkSize / (1024 * 1024)).round();
    _chunkMb = _chunkOptionsMb.contains(existingMb) ? existingMb : 16;
    _replicationFactor =
        (existing?.replicationFactor ?? 2).clamp(1, _maxReplicationFactor);
    _encrypt = existing?.encrypt ?? false;

    final existingMap = <String, PoolNodeConfigDto>{
      if (existing != null)
        for (final n in existing.nodes) n.remoteId: n,
    };

    _nodeEntries = widget.remotes
        .where((r) => r.kind != 'crypt')
        .map((r) {
          final match = existingMap[r.id];
          final defaultDomain = '${r.kind}-${r.id.substring(0, r.id.length.clamp(0, 4))}';
          final quotaGb = match == null
              ? 50.0
              : (match.quotaBytes.toDouble() / _bytesPerGb).clamp(0.1, 1000000.0);
          return _EditableNodeEntry(
            remote: r,
            selected: match != null,
            domain: match?.failureDomain ?? defaultDomain,
            quotaGb: quotaGb,
            weight: (match?.weight ?? 100).clamp(1, 1000),
            prefix: match?.basePrefix ?? 'fm_pool',
            role: match?.role ?? 'rw',
            isMetaBackup: match?.isMetaBackup ?? false,
          );
        })
        .toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passphraseCtrl.dispose();
    _passphraseConfirmCtrl.dispose();
    for (final n in _nodeEntries) {
      n.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = l10n.poolName);
      return;
    }

    final selectedNodes = <PoolNodeConfigDto>[];
    final existingByRemote = <String, PoolNodeConfigDto>{
      if (widget.existing != null)
        for (final n in widget.existing!.nodes) n.remoteId: n,
    };

    for (final entry in _nodeEntries) {
      if (!entry.selected) continue;
      final quotaGb = double.tryParse(entry.quotaGbCtrl.text.trim());
      if (quotaGb == null || quotaGb <= 0) {
        setState(() => _errorText = l10n.poolInvalidQuotaError);
        return;
      }
      final weight = int.tryParse(entry.weightCtrl.text.trim());
      if (weight == null || weight < 1 || weight > 1000) {
        setState(() => _errorText = l10n.poolInvalidWeightError);
        return;
      }
      final quotaBytes = BigInt.from(
        (quotaGb.clamp(0.01, 1000000.0) * _bytesPerGb).round(),
      );
      final domain = entry.domainCtrl.text.trim().isEmpty
          ? '${entry.remote.kind}-${entry.remote.id}'
          : entry.domainCtrl.text.trim();
      final prefix = _normalizePrefixInput(entry.prefixCtrl.text);
      final existingNode = existingByRemote[entry.remote.id];

      selectedNodes.add(
        PoolNodeConfigDto(
          nodeId: existingNode?.nodeId ?? entry.remote.id,
          remoteId: entry.remote.id,
          basePrefix: prefix,
          failureDomain: domain,
          quotaBytes: quotaBytes,
          weight: weight,
          role: entry.role,
          isMetaBackup: entry.isMetaBackup,
        ),
      );
    }

    if (selectedNodes.isEmpty) {
      setState(() => _errorText = l10n.poolSelectNodes);
      return;
    }
    if (selectedNodes.length < _replicationFactor) {
      setState(() => _errorText = l10n.poolMinNodesError(_replicationFactor));
      return;
    }

    final pass = _passphraseCtrl.text.trim();
    final needsPassphrase = _encrypt && (widget.existing == null || !widget.existing!.encrypt);
    if (needsPassphrase && pass.isEmpty) {
      setState(() => _errorText = l10n.poolPassphrase);
      return;
    }
    if (needsPassphrase && pass != _passphraseConfirmCtrl.text.trim()) {
      setState(() => _errorText = l10n.poolPassphraseMismatchError);
      return;
    }

    final result = PoolConfigDto(
      id: widget.existing?.id ?? '',
      name: name,
      chunkSize: _chunkMb * 1024 * 1024,
      replicationFactor: _replicationFactor,
      encrypt: _encrypt,
      passphrase: pass.isEmpty ? null : pass,
      kdfSalt: widget.existing?.kdfSalt,
      nodes: selectedNodes,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.existing != null;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(isEdit ? l10n.editStoragePool : l10n.createStoragePool),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.poolName,
                  hintText: l10n.poolNameHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _chunkMb,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.poolChunkSize,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final mb in _chunkOptionsMb)
                          DropdownMenuItem(value: mb, child: Text('$mb MiB')),
                      ],
                      onChanged: isEdit
                          ? null
                          : (v) {
                              if (v != null) setState(() => _chunkMb = v);
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _replicationFactor,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.poolReplicationFactorLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final r in _replicationOptions)
                          DropdownMenuItem(value: r, child: Text('${r}x')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _replicationFactor = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  l10n.poolEncryptEnable,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  isEdit ? l10n.poolEditLockedHint : l10n.poolEncryptSubtitle,
                  style: const TextStyle(fontSize: 11.5),
                ),
                value: _encrypt,
                onChanged: isEdit ? null : (v) => setState(() => _encrypt = v),
              ),
              if (_encrypt) ...[
                TextField(
                  controller: _passphraseCtrl,
                  obscureText: _obscurePassphrase,
                  decoration: InputDecoration(
                    labelText: l10n.poolPassphrase,
                    hintText: isEdit && (widget.existing?.encrypt ?? false)
                        ? l10n.poolPassphraseHint
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassphrase
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      onPressed: () => setState(
                        () => _obscurePassphrase = !_obscurePassphrase,
                      ),
                    ),
                  ),
                ),
                if (!isEdit || !(widget.existing?.encrypt ?? false)) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passphraseConfirmCtrl,
                    obscureText: _obscurePassphrase,
                    decoration: InputDecoration(
                      labelText: l10n.poolPassphraseConfirmLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],
              const Divider(),
              const SizedBox(height: 4),
              Text(
                l10n.poolSelectNodes,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              if (_nodeEntries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.poolNeedRemotesFirst,
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                )
              else
                for (final entry in _nodeEntries)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: entry.selected
                        ? scheme.primaryContainer.withValues(alpha: 0.25)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              '${entry.remote.name} (${entry.remote.kind.toUpperCase()})',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            value: entry.selected,
                            onChanged: (v) =>
                                setState(() => entry.selected = v ?? false),
                          ),
                          if (entry.selected) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: entry.domainCtrl,
                                    decoration: InputDecoration(
                                      labelText: l10n.poolFailureDomain,
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: entry.quotaGbCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: l10n.poolQuotaGb,
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: entry.weightCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: l10n.poolNodeWeightLabel,
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: entry.prefixCtrl,
                                    decoration: InputDecoration(
                                      labelText: l10n.poolStorageDirectory,
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      suffixIcon: IconButton(
                                        icon: const Icon(
                                          Icons.folder_open_outlined,
                                          size: 18,
                                        ),
                                        tooltip: l10n.poolPickDirectory,
                                        onPressed: () =>
                                            _pickNodeDirectory(entry),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: entry.role,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'rw',
                                        child: Text(l10n.poolRoleRw, overflow: TextOverflow.ellipsis),
                                      ),
                                      DropdownMenuItem(
                                        value: 'ro',
                                        child: Text(l10n.poolRoleRo, overflow: TextOverflow.ellipsis),
                                      ),
                                      DropdownMenuItem(
                                        value: 'draining',
                                        child: Text(l10n.poolRoleDraining, overflow: TextOverflow.ellipsis),
                                      ),
                                      DropdownMenuItem(
                                        value: 'offline',
                                        child: Text(l10n.poolRoleOffline, overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => entry.role = v);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                l10n.poolMetaBackup,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              value: entry.isMetaBackup,
                              onChanged: (v) => setState(
                                () => entry.isMetaBackup = v ?? false,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        if (_errorText != null)
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _errorText!,
                style: TextStyle(color: scheme.error, fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _nodeEntries.isEmpty ? null : _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
