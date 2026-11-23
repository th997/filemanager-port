part of '../vault_dialogs.dart';

class VaultInfoDialog extends StatefulWidget {
  final UnlockedVaultDto vault;
  final Future<VaultStatsDto> Function(String vaultId)? onGetStatsOverride;
  final Future<VaultGcResultDto> Function(String vaultId)? onGcOverride;

  const VaultInfoDialog({
    super.key,
    required this.vault,
    this.onGetStatsOverride,
    this.onGcOverride,
  });

  static Future<void> show(
    BuildContext context,
    UnlockedVaultDto vault,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => VaultInfoDialog(vault: vault),
    );
  }

  @override
  State<VaultInfoDialog> createState() => _VaultInfoDialogState();
}

class _VaultInfoDialogState extends State<VaultInfoDialog> {
  VaultStatsDto? _stats;
  bool _loading = true;
  bool _cleaning = false;
  String? _statusMessage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final getter =
          widget.onGetStatsOverride ?? VaultService.instance.getStats;
      final stats = await getter(widget.vault.id);
      if (mounted) {
        setState(() {
          _stats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  Future<void> _runGc() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _cleaning = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      final cleaner = widget.onGcOverride ?? VaultService.instance.gcVault;
      final res = await cleaner(widget.vault.id);
      if (!mounted) return;
      setState(() {
        _cleaning = false;
        _statusMessage = l10n.vaultCleanupResultNotice(
          res.removedFiles.toInt(),
          _formatVaultBytes(res.freedBytes.toInt()),
        );
      });
      await _loadStats();
    } catch (e) {
      if (mounted) {
        setState(() {
          _cleaning = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final stats = _stats;

    return AlertDialog(
      title: Text('${widget.vault.name} • ${l10n.vaultFolderInfo}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statRow(
                l10n.encryptionAlgorithm,
                widget.vault.cipher.toUpperCase(),
              ),
              _statRow(
                l10n.credentialMethod,
                widget.vault.authMode == 'system'
                    ? l10n.credentialSystem
                    : l10n.credentialPassword,
              ),
              const Divider(),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (stats != null) ...[
                _statRow(l10n.vaultStatsFiles, '${stats.fileCount}'),
                _statRow(l10n.vaultStatsFolders, '${stats.dirCount}'),
                _statRow(
                  l10n.vaultStatsPlainSize,
                  _formatVaultBytes(stats.totalPlainBytes.toInt()),
                ),
                _statRow(
                  l10n.vaultStatsDiskUsage,
                  _formatVaultBytes(stats.diskBytes.toInt()),
                ),
                _statRow(
                  l10n.vaultStatsOrphaned,
                  l10n.vaultStatsOrphanDetail(
                    stats.orphanCount.toInt(),
                    _formatVaultBytes(stats.orphanBytes.toInt()),
                  ),
                ),
              ],
              const Divider(),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: VaultService.instance.isAlwaysVisible(widget.vault.id),
                title: Text(
                  l10n.vaultAlwaysVisibleTitle,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  l10n.vaultAlwaysVisibleDesc,
                  style: const TextStyle(fontSize: 11),
                ),
                onChanged: (val) {
                  VaultService.instance.setAlwaysVisible(
                    vaultId: widget.vault.id,
                    name: widget.vault.name,
                    alwaysVisible: val,
                  );
                  setState(() {});
                },
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: colors.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (stats != null && stats.orphanCount > BigInt.zero)
          TextButton.icon(
            onPressed: _cleaning ? null : _runGc,
            icon: _cleaning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cleaning_services_outlined, size: 16),
            label: Text(l10n.vaultCleanupOrphansAction),
          ),
        FilledButton(
          onPressed: _cleaning ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
