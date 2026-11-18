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
}) {
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
              subtitle: Text(item.isDir ? 'Folder' : item.formattedSize),
            ),
            const Divider(height: 1),
            if (!item.isDir)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open with'),
                onTap: () => Navigator.of(ctx).pop('open_with'),
              ),
            if (isRemoteOrArchive)
              ListTile(
                leading: const Icon(Icons.download_outlined, color: Colors.blue),
                title: const Text('Download to local'),
                onTap: () => Navigator.of(ctx).pop('download'),
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () => Navigator.of(ctx).pop('copy'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy Path'),
              onTap: () => Navigator.of(ctx).pop('copy_path'),
            ),
            if (canWrite)
              ListTile(
                leading: const Icon(Icons.cut),
                title: const Text('Cut'),
                onTap: () => Navigator.of(ctx).pop('cut'),
              ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Select items'),
              onTap: () => Navigator.of(ctx).pop('select'),
            ),
            if (item.isArchive && canArchive)
              ListTile(
                leading: const Icon(Icons.unarchive),
                title: const Text('Extract Here'),
                onTap: () => Navigator.of(ctx).pop('extract'),
              )
            else if (canWrite && canArchive)
              ListTile(
                leading: const Icon(Icons.archive),
                title: const Text('Compress to ZIP'),
                onTap: () => Navigator.of(ctx).pop('compress'),
              ),
            if (item.isDir)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Bookmark This Folder'),
                onTap: () => Navigator.of(ctx).pop('bookmark'),
              ),
            if (!item.isDir)
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share'),
                onTap: () => Navigator.of(ctx).pop('share'),
              ),
            if (canWrite)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename'),
                onTap: () => Navigator.of(ctx).pop('rename'),
              ),
            if (canWrite)
              ListTile(
                leading: const Icon(Icons.control_point_duplicate),
                title: const Text('Duplicate'),
                onTap: () => Navigator.of(ctx).pop('duplicate'),
              ),
            if (canWrite)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Properties'),
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
}) {
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
            Text(item.isDir ? 'Open' : 'Open'),
          ],
        ),
      ),
      if (!item.isDir)
        const PopupMenuItem(
          value: 'open_with',
          child: Row(
            children: [
              Icon(Icons.open_in_browser, size: 18),
              SizedBox(width: 8),
              Text('Open with'),
            ],
          ),
        ),
      if (isRemoteOrArchive)
        const PopupMenuItem(
          value: 'download',
          child: Row(
            children: [
              Icon(Icons.download, size: 18, color: Colors.blue),
              SizedBox(width: 8),
              Text('Download to local'),
            ],
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'copy',
        child: Row(
          children: [
            Icon(Icons.copy, size: 18),
            SizedBox(width: 8),
            Text('Copy'),
          ],
        ),
      ),
      if (canWrite)
        const PopupMenuItem(
          value: 'cut',
          child: Row(
            children: [
              Icon(Icons.cut, size: 18),
              SizedBox(width: 8),
              Text('Cut'),
            ],
          ),
        ),
      if (canWrite)
        const PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline, size: 18),
              SizedBox(width: 8),
              Text('Rename'),
            ],
          ),
        ),
      if (canWrite)
        const PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.control_point_duplicate, size: 18),
              SizedBox(width: 8),
              Text('Duplicate'),
            ],
          ),
        ),
      if (canWrite)
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'copy_path',
        child: Row(
          children: [
            Icon(Icons.link, size: 18),
            SizedBox(width: 8),
            Text('Copy Path'),
          ],
        ),
      ),
      if (item.isArchive && canArchive)
        const PopupMenuItem(
          value: 'extract',
          child: Row(
            children: [
              Icon(Icons.unarchive, size: 18),
              SizedBox(width: 8),
              Text('Extract Here'),
            ],
          ),
        )
      else if (canWrite && canArchive)
        const PopupMenuItem(
          value: 'compress',
          child: Row(
            children: [
              Icon(Icons.archive, size: 18),
              SizedBox(width: 8),
              Text('Compress to ZIP'),
            ],
          ),
        ),
      if (item.isDir)
        const PopupMenuItem(
          value: 'bookmark',
          child: Row(
            children: [
              Icon(Icons.bookmark_add_outlined, size: 18),
              SizedBox(width: 8),
              Text('Bookmark This Folder'),
            ],
          ),
        ),
      const PopupMenuItem(
        value: 'info',
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18),
            SizedBox(width: 8),
            Text('Properties'),
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
              Text('Paste (${clipboardCount ?? 0})'),
            ],
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'refresh',
        child: Row(
          children: [
            Icon(Icons.refresh, size: 18),
            SizedBox(width: 8),
            Text('Refresh'),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'select_all',
        child: Row(
          children: [
            Icon(Icons.select_all, size: 18),
            SizedBox(width: 8),
            Text('Select All'),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'invert_selection',
        child: Row(
          children: [
            Icon(Icons.swap_horiz, size: 18),
            SizedBox(width: 8),
            Text('Invert Selection'),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'bookmark',
        child: Row(
          children: [
            Icon(Icons.bookmark_add_outlined, size: 18),
            SizedBox(width: 8),
            Text('Bookmark This Folder'),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'copy_path',
        child: Row(
          children: [
            Icon(Icons.copy, size: 18),
            SizedBox(width: 8),
            Text('Copy Folder Path'),
          ],
        ),
      ),
    ],
  );
}
