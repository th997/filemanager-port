import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../dialogs/vault_dialogs.dart';
import '../rust/api/vault.dart';
import '../services/vault_service.dart';
import '../theme/app_ui_tokens.dart';
import 'browser_page.dart';

typedef PrivacySpacePage = UtilitiesPage;

class UtilitiesPage extends StatefulWidget {
  final ValueChanged<UnlockedVaultDto>? onOpenVault;

  const UtilitiesPage({super.key, this.onOpenVault});

  @override
  State<UtilitiesPage> createState() => _UtilitiesPageState();
}

class _UtilitiesPageState extends State<UtilitiesPage> {
  @override
  void initState() {
    super.initState();
    VaultService.instance.addListener(_onVaultChanged);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSwipeBack(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            l10n.privacyFolders,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPad =
                constraints.maxWidth > 884 ? (constraints.maxWidth - 860) / 2 : 12.0;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(horizontalPad, 6, horizontalPad, 12),
              children: [
                _buildPrivacyFoldersSection(l10n),
              ],
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
