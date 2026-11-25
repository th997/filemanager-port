import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../dialogs/vault_dialogs.dart';
import '../rust/api/file_manager.dart' as fm_api;
import '../rust/api/vault.dart';
import '../services/file_open_service.dart';
import '../services/vault_service.dart';
import '../theme/app_ui_tokens.dart';
import 'browser_page.dart';

class UtilitiesPage extends StatefulWidget {
  final ValueChanged<UnlockedVaultDto>? onOpenVault;

  const UtilitiesPage({super.key, this.onOpenVault});

  @override
  State<UtilitiesPage> createState() => _UtilitiesPageState();
}

class _UtilitiesPageState extends State<UtilitiesPage> {
  int _cacheSizeBytes = 0;
  int _archiveCacheBytes = 0;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    VaultService.instance.addListener(_onVaultChanged);
    _loadData();
  }

  @override
  void dispose() {
    VaultService.instance.removeListener(_onVaultChanged);
    super.dispose();
  }

  void _onVaultChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openVaultBrowser(UnlockedVaultDto vault) async {
    if (!mounted) return;
    if (widget.onOpenVault != null) {
      widget.onOpenVault!(vault);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserPage(initialRoot: 'vault://${vault.id}'),
      ),
    );
  }

  Future<void> _createPrivacyFolder() async {
    final created = await CreateVaultDialog.show(context);
    if (created != null && mounted) {
      await _openVaultBrowser(created);
    }
  }

  Future<void> _openPrivacyFolder() async {
    final unlocked = await OpenVaultDialog.show(context);
    if (unlocked != null && mounted) {
      await _openVaultBrowser(unlocked);
    }
  }

  Future<void> _backupPrivacyFolder() async {
    final l10n = AppLocalizations.of(context);
    final outPath = await BackupVaultDialog.show(context);
    if (outPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.backupExportSuccess(outPath))),
      );
    }
  }

  Future<void> _importPrivacyFolder() async {
    final l10n = AppLocalizations.of(context);
    final imported = await ImportVaultDialog.show(context);
    if (imported != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.importSuccessNotice(imported.name))),
      );
      await _openVaultBrowser(imported);
    }
  }

  Future<void> _loadData() async {
    final int cacheBytes;
    try {
      cacheBytes = await FileOpenService.instance.getExportCacheSizeBytes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).couldNotReadStorageStats('$e')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    int archiveBytes = 0;
    try {
      archiveBytes = fm_api.archiveCacheSize().toInt();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _cacheSizeBytes = cacheBytes;
        _archiveCacheBytes = archiveBytes;
      });
    }
  }

  Future<void> _clearArchiveCache() async {
    try {
      fm_api.clearArchiveCache();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).couldNotClearArchiveCache('$e'),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    if (mounted) {
      setState(() => _archiveCacheBytes = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).archiveCacheCleared)),
      );
    }
  }

  Future<void> _clearCache() async {
    setState(() => _clearingCache = true);
    try {
      await FileOpenService.instance.clearExports();
      final cacheBytes =
          await FileOpenService.instance.getExportCacheSizeBytes();
      if (mounted) {
        setState(() => _cacheSizeBytes = cacheBytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).tempCacheCleared)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).couldNotClearCache('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSwipeBack(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            l10n.utilities,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: l10n.refresh,
              onPressed: _loadData,
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPad =
                constraints.maxWidth > 884 ? (constraints.maxWidth - 860) / 2 : 12.0;
            return RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(horizontalPad, 6, horizontalPad, 12),
                children: [
              // 0. Privacy Folders Card
              _buildPrivacyFoldersSection(l10n),

              const SizedBox(height: 12),

              // 1. Cache cleaner
              _buildSectionHeader(l10n.storageAndCache),
              Card(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const AppCircleBadge(
                        icon: Icons.cleaning_services,
                        color: Colors.teal,
                      ),
                      title: Text(l10n.exportPreviewCache),
                      subtitle: Text(
                        _formatSize(_cacheSizeBytes),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: _clearingCache
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                              ),
                              onPressed:
                                  _cacheSizeBytes > 0 ? _clearCache : null,
                              child: Text(
                                l10n.clear,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const AppCircleBadge(
                        icon: Icons.archive_outlined,
                        color: Colors.deepPurple,
                      ),
                      title: Text(l10n.remoteArchiveCache),
                      subtitle: Text(
                        _formatSize(_archiveCacheBytes),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed:
                            _archiveCacheBytes > 0 ? _clearArchiveCache : null,
                        child: Text(
                          l10n.clear,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        },
        ),
      ),
    );
  }

  Widget _buildPrivacyFoldersSection(AppLocalizations l10n) {
    final List<UnlockedVaultDto> unlocked = VaultService.instance.unlockedVaults;
    final List<PinnedVaultEntry> lockedPinned =
        VaultService.instance.lockedPinnedVaults;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(l10n.privacyFolders),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const AppCircleBadge(
                  icon: Icons.enhanced_encryption_outlined,
                  color: Colors.indigo,
                ),
                title: Text(l10n.privacyFolders),
                subtitle: Text(
                  l10n.privacyFoldersDesc,
                  style: const TextStyle(fontSize: 10),
                ),
                trailing: unlocked.isNotEmpty
                    ? TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          foregroundColor: colorScheme.error,
                        ),
                        onPressed: () {
                          VaultService.instance.lockAll();
                        },
                        icon: const Icon(Icons.lock_outline, size: 15),
                        label: Text(
                          l10n.lockAllPrivacyFolders(unlocked.length),
                          style: const TextStyle(fontSize: 11),
                        ),
                      )
                    : null,
              ),
              if (unlocked.isNotEmpty || lockedPinned.isNotEmpty) ...[
                const Divider(height: 1),
                for (final vault in unlocked)
                  Builder(
                    builder: (_) {
                      final isPinned =
                          VaultService.instance.isAlwaysVisible(vault.id);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.lock_open_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        title: Text(
                          vault.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          isPinned
                              ? '${l10n.unlockedBadge} · ${l10n.vaultAlwaysVisibleTitle}'
                              : l10n.unlockedBadge,
                          style: const TextStyle(fontSize: 10),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIconButton(
                              icon: isPinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                              size: 28,
                              iconSize: 17,
                              color: isPinned ? colorScheme.primary : null,
                              tooltip: l10n.vaultAlwaysVisibleTitle,
                              onPressed: () {
                                VaultService.instance.setAlwaysVisible(
                                  vaultId: vault.id,
                                  name: vault.name,
                                  alwaysVisible: !isPinned,
                                );
                              },
                            ),
                            AppIconButton(
                              icon: Icons.drive_file_rename_outline,
                              size: 28,
                              iconSize: 17,
                              tooltip: l10n.renamePrivacyFolder,
                              onPressed: () async {
                                final updated =
                                    await RenameVaultDialog.show(context, vault);
                                if (updated != null &&
                                    updated.name != vault.name &&
                                    mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        l10n.privacyFolderRenamedNotice(
                                          updated.name,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                            AppIconButton(
                              icon: Icons.lock_outline,
                              size: 28,
                              iconSize: 17,
                              color: colorScheme.error,
                              tooltip: l10n.lockAndHide,
                              onPressed: () {
                                final keepVisible = VaultService.instance
                                    .isAlwaysVisible(vault.id);
                                VaultService.instance.lockVault(vault.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      keepVisible
                                          ? l10n.vaultLockedKeepVisibleNotice(
                                              vault.name,
                                            )
                                          : l10n.vaultLockedNotice(vault.name),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const Icon(Icons.chevron_right, size: 16),
                          ],
                        ),
                        onTap: () => _openVaultBrowser(vault),
                      );
                    },
                  ),
                for (final pinned in lockedPinned)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      pinned.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${l10n.lockedBadge} · ${l10n.vaultAlwaysVisibleTitle}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIconButton(
                          icon: Icons.push_pin,
                          size: 28,
                          iconSize: 17,
                          color: colorScheme.primary,
                          tooltip: l10n.vaultUnpinAlwaysVisible,
                          onPressed: () {
                            VaultService.instance.unpinVault(pinned.id);
                          },
                        ),
                        const Icon(Icons.chevron_right, size: 16),
                      ],
                    ),
                    onTap: () async {
                      final unlockedVault = await OpenVaultDialog.show(
                        context,
                        initialName: pinned.name,
                      );
                      if (unlockedVault != null && mounted) {
                        await _openVaultBrowser(unlockedVault);
                      }
                    },
                  ),
              ],
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.create_new_folder_outlined, size: 19),
                title: Text(
                  l10n.createPrivacyFolder,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: const Icon(Icons.chevron_right, size: 16),
                onTap: _createPrivacyFolder,
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder_open_outlined, size: 19),
                title: Text(
                  l10n.openPrivacyFolder,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: const Icon(Icons.chevron_right, size: 16),
                onTap: _openPrivacyFolder,
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.archive_outlined, size: 19),
                title: Text(
                  l10n.backupPrivacyFolder,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: const Icon(Icons.chevron_right, size: 16),
                onTap: _backupPrivacyFolder,
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.unarchive_outlined, size: 19),
                title: Text(
                  l10n.importPrivacyFolder,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: const Icon(Icons.chevron_right, size: 16),
                onTap: _importPrivacyFolder,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
