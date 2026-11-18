import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:filemanager/l10n/app_localizations.dart';
import '../services/path_utils.dart';
import '../services/platform_paths.dart';

/// Reusable scaffold for VFS-based picker dialogs (file picker, folder picker).
class VfsPickerScaffold extends StatelessWidget {
  final String title;
  final VoidCallback? onSystemPicker;
  final List<String> recentDirs;
  final ValueChanged<String>? onNavigateTo;
  final List<QuickTarget> quickTargets;
  final ValueChanged<QuickTarget>? onSelectTarget;
  final String currentPath;
  final bool canGoUp;
  final VoidCallback? onUp;
  final bool showHidden;
  final VoidCallback onToggleHidden;
  final String? hiddenTooltip;
  final List<Widget> pathActions;
  final bool showFilter;
  final TextEditingController? filterController;
  final String filterQuery;
  final String filterHintText;
  final ValueChanged<String>? onFilterChanged;
  final VoidCallback? onFilterClear;
  final bool loading;
  final String? error;
  final String? errorPrefix;
  final VoidCallback? onRetry;
  final Widget body;
  final Widget? footer;
  final List<Widget> actions;
  final double maxWidth;
  final double maxHeight;

  const VfsPickerScaffold({
    super.key,
    required this.title,
    this.onSystemPicker,
    this.recentDirs = const [],
    this.onNavigateTo,
    this.quickTargets = const [],
    this.onSelectTarget,
    required this.currentPath,
    required this.canGoUp,
    this.onUp,
    required this.showHidden,
    required this.onToggleHidden,
    this.hiddenTooltip,
    this.pathActions = const [],
    this.showFilter = false,
    this.filterController,
    this.filterQuery = '',
    this.filterHintText = 'Filter...',
    this.onFilterChanged,
    this.onFilterClear,
    required this.loading,
    this.error,
    this.errorPrefix,
    this.onRetry,
    required this.body,
    this.footer,
    required this.actions,
    this.maxWidth = 520,
    this.maxHeight = 500,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(title)),
          if (onSystemPicker != null)
            TextButton.icon(
              icon: const Icon(Icons.open_in_browser, size: 16),
              label: Text(l10n?.systemPicker ?? 'Use System Picker'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: onSystemPicker,
            ),
        ],
      ),
      actionsOverflowButtonSpacing: 6,
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: SizedBox(
          width: double.maxFinite,
          height: maxHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (recentDirs.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.history, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      l10n?.recentDirs ?? 'Recent:',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final dir in recentDirs)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            avatar: const Icon(Icons.folder_outlined, size: 13),
                            label: Text(
                              shortDirectoryName(dir),
                              style: const TextStyle(fontSize: 11),
                            ),
                            tooltip: dir,
                            onPressed: () => onNavigateTo?.call(dir),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (quickTargets.isNotEmpty)
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final target in quickTargets)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(target.name, style: const TextStyle(fontSize: 12)),
                            onPressed: () => onSelectTarget?.call(target),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Parent folder',
                    onPressed: canGoUp ? onUp : null,
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: currentPath));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Path copied to clipboard')),
                        );
                      },
                      child: Tooltip(
                        message: 'Click to copy path',
                        child: Text(
                          currentPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(showHidden ? Icons.visibility : Icons.visibility_off, size: 18),
                    tooltip: hiddenTooltip ?? (showHidden ? 'Hide hidden files' : 'Show hidden files'),
                    onPressed: onToggleHidden,
                  ),
                  ...pathActions,
                ],
              ),
              const Divider(height: 1),
              if (showFilter && filterController != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: TextField(
                    controller: filterController,
                    decoration: InputDecoration(
                      hintText: filterHintText,
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: filterQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: onFilterClear,
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: onFilterChanged,
                  ),
                ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    errorPrefix != null ? '$errorPrefix$error' : error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12, color: Colors.red),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: const Text('Retry'),
                                    onPressed: onRetry,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : body,
              ),
              if (footer != null) ...[
                const Divider(height: 1),
                footer!,
              ],
            ],
          ),
        ),
      ),
      actions: actions,
    );
  }
}

/// Shows a standard "New Folder" input dialog.
Future<String?> showNewFolderDialog(BuildContext context) async {
  final nameController = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New Folder'),
      content: TextField(
        controller: nameController,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Folder name',
          hintText: 'e.g. Documents',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (val) {
          if (val.trim().isNotEmpty) {
            Navigator.of(ctx).pop(val.trim());
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        ListenableBuilder(
          listenable: nameController,
          builder: (ctx, _) => FilledButton(
            onPressed: nameController.text.trim().isEmpty
                ? null
                : () => Navigator.of(ctx).pop(nameController.text.trim()),
            child: const Text('Create'),
          ),
        ),
      ],
    ),
  );
  nameController.dispose();
  return name;
}
