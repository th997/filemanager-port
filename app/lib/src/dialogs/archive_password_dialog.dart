import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Prompts the user for an archive password (for encrypted `.zip` or `.7z`).
Future<String?> showArchivePasswordDialog(
  BuildContext context, {
  required String archiveName,
  bool wrongPassword = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  bool obscure = true;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(l10n.archivePasswordRequired),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(archiveName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            if (wrongPassword) ...[
              const SizedBox(height: 6),
              Text(
                l10n.archiveWrongPassword,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: obscure,
              decoration: InputDecoration(
                hintText: l10n.archivePasswordHint,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => obscure = !obscure),
                ),
              ),
              onSubmitted: (v) {
                if (v.isNotEmpty) Navigator.of(ctx).pop(v);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final pw = controller.text;
              if (pw.isNotEmpty) Navigator.of(ctx).pop(pw);
            },
            child: Text(l10n.ok),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}
