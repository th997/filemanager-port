import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../dialogs/vault_dialogs.dart';
import '../rust/api/vault.dart';
import '../services/vault_service.dart';

/// Extracted Privacy Vault management actions for browser pages and panes.
class BrowserVaultActions {
  static Future<bool> lockCurrentVault(
    BuildContext context,
    UnlockedVaultDto vault,
  ) async {
    final keepVisible = VaultService.instance.isAlwaysVisible(vault.id);
    VaultService.instance.lockVault(vault.id);
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            keepVisible
                ? l10n.vaultLockedKeepVisibleNotice(vault.name)
                : l10n.vaultLockedNotice(vault.name),
          ),
        ),
      );
    }
    return true;
  }

  static Future<UnlockedVaultDto?> renameVault(
    BuildContext context,
    UnlockedVaultDto vault,
  ) {
    return RenameVaultDialog.show(context, vault);
  }

  static Future<void> showVaultInfo(
    BuildContext context,
    UnlockedVaultDto vault,
  ) {
    return VaultInfoDialog.show(context, vault);
  }

  static Future<UnlockedVaultDto?> showVaultSecurity(
    BuildContext context,
    UnlockedVaultDto vault,
  ) {
    return ChangeVaultSecurityDialog.show(context, vault);
  }

  static Future<bool> deleteVault(
    BuildContext context,
    UnlockedVaultDto vault,
  ) {
    return DeleteVaultDialog.show(context, vault);
  }
}
