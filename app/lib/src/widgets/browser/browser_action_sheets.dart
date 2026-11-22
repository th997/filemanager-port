import 'package:flutter/material.dart';

import 'package:filemanager/l10n/app_localizations.dart';
import '../../models/entry_item.dart';

/// Shows mobile action sheet for a single file or folder entry.
Future<String?> showBrowserEntryModalBottomSheet({
  required BuildContext context,
  required EntryItem item,
  required bool isRemoteOrArchive,
  required bool canWrite,
  required bool canArchive,
  bool canBookmark = true,
}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
      ),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            ListTile(
              leading: Icon(item.icon, color: item.iconColor(ctx)),
              title: Text(item.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(item.isDir ? l10n.folderLabel : item.formattedSize),
            ),
            const Divider(height: 1),
            if (!item.isDir) ...[
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text(l10n.openWith),
                onTap: () => Navigator.of(ctx).pop('open_with'),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(l10n.openAsText),
                onTap: () => Navigator.of(ctx).pop('open_as_text'),
              ),
            ],
            if (isRemoteOrArchive)
              ListTile(
                leading: const Icon(Icons.download_outlined, color: Colors.blue),
                title: Text(l10n.downloadToLocal),
                onTap: () => Navigator.of(ctx).pop('download'),
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(l10n.copy),
              onTap: () => Navigator.of(ctx).pop('copy'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(l10n.copyPath),
              onTap: () => Navigator.of(ctx).pop('copy_path'),
            ),
            if (canWrite)
              ListTile(
                leading: const Icon(Icons.cut),
                title: Text(l10n.cut),
                onTap: () => Navigator.of(ctx).pop('cut'),
              ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(l10n.selectItems),
              onTap: () => Navigator.of(ctx).pop('select'),
            ),
            if (item.isArchive && canWrite && canArchive)
              ListTile(
                leading: const Icon(Icons.unarchive),
                title: Text(l10n.extractHere),
                onTap: () => Navigator.of(ctx).pop('extract'),
              )
            else if (canWrite && canArchive)
              ListTile(
                leading: const Icon(Icons.archive),
                title: Text(l10n.compressToZip),
                onTap: () => Navigator.of(ctx).pop('compress'),
              ),
            if (item.isDir && canBookmark)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: Text(l10n.bookmarkThisFolder),
                onTap: () => Navigator.of(ctx).pop('bookmark'),
              ),
            if (!item.isDir)
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: Text(l10n.share),
                onTap: () => Navigator.of(ctx).pop('share'),
              ),
            if (canWrite)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: Text(l10n.rename),
                onTap: () => Navigator.of(ctx).pop('rename'),
              ),
            if (canWrite)
              ListTile(
                leading: const Icon(Icons.control_point_duplicate),
                title: Text(l10n.duplicate),
                onTap: () => Navigator.of(ctx).pop('duplicate'),
              ),
            if (canWrite)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.properties),
              onTap: () => Navigator.of(ctx).pop('info'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows desktop right-click context menu on a file/folder.
Future<String?> showBrowserContextMenu({
  required BuildContext context,
  required Offset position,
  required EntryItem item,
  required bool isRemoteOrArchive,
  required bool canWrite,
  required bool canArchive,
  bool canBookmark = true,
}) {
  final l10n = AppLocalizations.of(context);
  return showMenu<String>(
    context: context,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      minWidth: 200,
    ),
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    ),
    items: [
      PopupMenuItem(
        value: 'open',
        child: Row(
          children: [
            Icon(item.isDir ? Icons.folder_open : Icons.open_in_new, size: 18),
            const SizedBox(width: 8),
            Text(l10n.open),
          ],
        ),
      ),
      if (!item.isDir) ...[
        PopupMenuItem(
          value: 'open_with',
          child: Row(
            children: [
              const Icon(Icons.open_in_browser, size: 18),
              const SizedBox(width: 8),
              Text(l10n.openWith),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open_as_text',
          child: Row(
            children: [
              const Icon(Icons.description_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.openAsText),
            ],
          ),
        ),
      ],
      if (isRemoteOrArchive)
        PopupMenuItem(
          value: 'download',
          child: Row(
            children: [
              const Icon(Icons.download, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Text(l10n.downloadToLocal),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'copy',
        child: Row(
          children: [
            const Icon(Icons.copy, size: 18),
            const SizedBox(width: 8),
            Text(l10n.copy),
          ],
        ),
      ),
      if (canWrite)
        PopupMenuItem(
          value: 'cut',
          child: Row(
            children: [
              const Icon(Icons.cut, size: 18),
              const SizedBox(width: 8),
              Text(l10n.cut),
            ],
          ),
        ),
      if (canWrite)
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              const Icon(Icons.drive_file_rename_outline, size: 18),
              const SizedBox(width: 8),
              Text(l10n.rename),
            ],
          ),
        ),
      if (canWrite)
        PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              const Icon(Icons.control_point_duplicate, size: 18),
              const SizedBox(width: 8),
              Text(l10n.duplicate),
            ],
          ),
        ),
      if (canWrite)
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete, size: 18, color: Colors.red),
              const SizedBox(width: 8),
              Text(l10n.delete, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'copy_path',
        child: Row(
          children: [
            const Icon(Icons.link, size: 18),
            const SizedBox(width: 8),
            Text(l10n.copyPath),
          ],
        ),
      ),
      if (item.isArchive && canWrite && canArchive)
        PopupMenuItem(
          value: 'extract',
          child: Row(
            children: [
              const Icon(Icons.unarchive, size: 18),
              const SizedBox(width: 8),
              Text(l10n.extractHere),
            ],
          ),
        )
      else if (canWrite && canArchive)
        PopupMenuItem(
          value: 'compress',
          child: Row(
            children: [
              const Icon(Icons.archive, size: 18),
              const SizedBox(width: 8),
              Text(l10n.compressToZip),
            ],
          ),
        ),
      if (item.isDir && canBookmark)
        PopupMenuItem(
          value: 'bookmark',
          child: Row(
            children: [
              const Icon(Icons.bookmark_add_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.bookmarkThisFolder),
            ],
          ),
        ),
      PopupMenuItem(
        value: 'info',
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Text(l10n.properties),
          ],
        ),
      ),
    ],
  );
}

/// Shows desktop right-click context menu on empty space.
Future<String?> showBrowserBackgroundContextMenu({
  required BuildContext context,
  required Offset position,
  required bool canWrite,
  required bool isAtMultiBucketRoot,
  required bool hasClipboard,
  required int? clipboardCount,
  bool isZh = false,
  bool canBookmark = true,
}) {
  final l10n = AppLocalizations.of(context);
  return showMenu<String>(
    context: context,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      minWidth: 200,
    ),
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    ),
    items: [
      if (canWrite)
        PopupMenuItem(
          value: 'new_folder',
          child: Row(
            children: [
              Icon(
                isAtMultiBucketRoot
                    ? Icons.create_new_folder_outlined
                    : Icons.create_new_folder,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isAtMultiBucketRoot
                    ? l10n.newBucket
                    : l10n.newFolder,
              ),
            ],
          ),
        ),
      if (canWrite && !isAtMultiBucketRoot)
        PopupMenuItem(
          value: 'new_file',
          child: Row(
            children: [
              const Icon(Icons.note_add_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.newTextFile),
            ],
          ),
        ),
      if (canWrite) ...[
        PopupMenuItem(
          value: 'upload',
          child: Row(
            children: [
              const Icon(Icons.cloud_upload_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.uploadFiles),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'upload_folder',
          child: Row(
            children: [
              const Icon(Icons.drive_folder_upload_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.uploadFolder),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'upload_inapp',
          child: Row(
            children: [
              const Icon(Icons.folder_shared_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.browseInAppUpload),
            ],
          ),
        ),
      ],
      if (hasClipboard && canWrite)
        PopupMenuItem(
          value: 'paste',
          child: Row(
            children: [
              const Icon(Icons.paste, size: 18),
              const SizedBox(width: 8),
              Text(l10n.pasteCount(clipboardCount ?? 0)),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'refresh',
        child: Row(
          children: [
            const Icon(Icons.refresh, size: 18),
            const SizedBox(width: 8),
            Text(l10n.refresh),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'select_all',
        child: Row(
          children: [
            const Icon(Icons.select_all, size: 18),
            const SizedBox(width: 8),
            Text(l10n.selectAll),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'invert_selection',
        child: Row(
          children: [
            const Icon(Icons.swap_horiz, size: 18),
            const SizedBox(width: 8),
            Text(l10n.invertSelection),
          ],
        ),
      ),
      if (canBookmark)
        PopupMenuItem(
          value: 'bookmark',
          child: Row(
            children: [
              const Icon(Icons.bookmark_add_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.bookmarkThisFolder),
            ],
          ),
        ),
      PopupMenuItem(
        value: 'copy_path',
        child: Row(
          children: [
            const Icon(Icons.copy, size: 18),
            const SizedBox(width: 8),
            Text(l10n.copyFolderPath),
          ],
        ),
      ),
    ],
  );
}

/// Shows an "Open with" chooser bottom sheet or dialog for unrecognized or arbitrary files.
/// Returns the chosen action: 'text', 'system', 'media', 'image', or null if dismissed.
Future<String?> showBrowserOpenWithDialog({
  required BuildContext context,
  required EntryItem item,
}) {
  final l10n = AppLocalizations.of(context);
  final isMobile = MediaQuery.sizeOf(context).width < 600;

  Widget buildContent(BuildContext ctx) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        ListTile(
          leading: Icon(item.icon, color: item.iconColor(ctx), size: 36),
          title: Text(
            item.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            item.formattedSize.isNotEmpty
                ? '${item.formattedSize} • ${l10n.openWith}'
                : l10n.openWith,
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.description_outlined, color: Colors.blue),
          ),
          title: Text(
            l10n.openAsText,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(l10n.openAsTextSubtitle),
          onTap: () => Navigator.of(ctx).pop('text'),
        ),
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.open_in_new, color: Colors.teal),
          ),
          title: Text(
            l10n.openWithOtherApp,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(l10n.openWithOtherAppSubtitle),
          onTap: () => Navigator.of(ctx).pop('system'),
        ),
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_circle_outline, color: Colors.purple),
          ),
          title: Text(l10n.openAsMedia),
          subtitle: Text(l10n.openAsMediaSubtitle),
          onTap: () => Navigator.of(ctx).pop('media'),
        ),
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.image_outlined, color: Colors.orange),
          ),
          title: Text(l10n.openAsImage),
          subtitle: Text(l10n.openAsImageSubtitle),
          onTap: () => Navigator.of(ctx).pop('image'),
        ),
      ],
    ),
  );
  }

  if (isMobile) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: buildContent(ctx),
        ),
      ),
    );
  }

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.openWith),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 420,
        child: buildContent(ctx),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}
