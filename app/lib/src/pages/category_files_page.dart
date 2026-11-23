import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import 'package:filemanager/l10n/app_localizations.dart';
import '../dialogs/browser_info_dialog.dart';
import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../rust/api/search.dart';
import '../services/file_open_service.dart';
import '../services/path_utils.dart';
import '../services/platform_capabilities.dart';
import '../services/task_service.dart';
import '../theme/app_ui_tokens.dart';
import '../widgets/entry_thumbnail.dart';
import 'browser_page.dart';
import 'media_player_page.dart';
import 'pdf_viewer_page.dart';
import 'structured_viewer_page.dart';
import 'text_editor_page.dart';

typedef CategorySearchFn = Future<List<EntryDto>> Function({
  required String root,
  required String path,
  required AdvancedSearchQueryDto options,
});

enum _CategorySortField { date, size, name }

enum _CategoryItemAction { open, locate, share, details, delete }

class _CategoryVisual {
  final String title;
  final IconData icon;
  final Color color;
  final bool defaultGridView;

  const _CategoryVisual({
    required this.title,
    required this.icon,
    required this.color,
    required this.defaultGridView,
  });

  static _CategoryVisual resolve(String category, AppLocalizations l10n) {
    switch (category) {
      case 'document':
        return _CategoryVisual(
          title: l10n.categoryDocuments,
          icon: Icons.description_outlined,
          color: const Color(0xFF1E88E5),
          defaultGridView: false,
        );
      case 'video':
        return _CategoryVisual(
          title: l10n.categoryVideos,
          icon: Icons.movie_outlined,
          color: const Color(0xFFE53935),
          defaultGridView: true,
        );
      case 'audio':
        return _CategoryVisual(
          title: l10n.categoryAudio,
          icon: Icons.audiotrack_outlined,
          color: const Color(0xFF8E24AA),
          defaultGridView: false,
        );
      case 'archive':
        return _CategoryVisual(
          title: l10n.categoryArchives,
          icon: Icons.folder_zip_outlined,
          color: const Color(0xFFFB8C00),
          defaultGridView: false,
        );
      case 'apk':
        return _CategoryVisual(
          title: l10n.categoryApks,
          icon: PlatformCapabilities.installerCategoryIcon,
          color: const Color(0xFF00ACC1),
          defaultGridView: false,
        );
      default:
        return _CategoryVisual(
          title: l10n.searchFilesAndFolders,
          icon: Icons.insert_drive_file_outlined,
          color: const Color(0xFF546E7A),
          defaultGridView: false,
        );
    }
  }
}

/// Dedicated browse-first page for smart file categories
/// (Documents, Videos, Audio, Archives, Installers).
///
/// Replaces opening the raw advanced-search modal so users land directly on a
/// scannable, visually grouped file browser without a forced keyboard popup.
class CategoryFilesPage extends StatefulWidget {
  final String category;
  final String root;
  final CategorySearchFn? searchEntriesFn;
  final Future<void> Function(EntryItem item)? onDeleteFileOverride;

  const CategoryFilesPage({
    super.key,
    required this.category,
    required this.root,
    this.searchEntriesFn,
    this.onDeleteFileOverride,
  });

  @override
  State<CategoryFilesPage> createState() => _CategoryFilesPageState();
}

class _CategoryFilesPageState extends State<CategoryFilesPage> {
  static const Set<String> _installerExtensions = {
    'apk',
    'apks',
    'apkm',
    'xapk',
    'aab',
    'dmg',
    'pkg',
    'deb',
    'rpm',
    'appimage',
    'exe',
    'msi',
  };

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<EntryItem> _allItems = const [];
  bool _loading = true;
  String? _error;

  String? _selectedExtension;
  bool _searchActive = false;
  String _searchQuery = '';
  _CategorySortField _sortField = _CategorySortField.date;
  bool _sortAscending = false;
  late bool _isGridView = widget.category == 'video';

  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final searchFn = widget.searchEntriesFn ?? searchEntriesAdvanced;
    try {
      final dtos = await searchFn(
        root: widget.root,
        path: '',
        options: AdvancedSearchQueryDto(
          query: '',
          category: widget.category,
          matchMode: 'contains',
          caseSensitive: false,
          includeHidden: false,
          maxResults: 1000,
        ),
      );
      if (!mounted || epoch != _loadEpoch) return;
      final files = dtos
          .where((dto) => !dto.isDir)
          .map(EntryItem.new)
          .toList(growable: false);
      setState(() {
        _allItems = files;
        _loading = false;
        if (_selectedExtension != null &&
            !files.any((e) => e.extension.toUpperCase() == _selectedExtension)) {
          _selectedExtension = null;
        }
      });
    } catch (e) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<({String ext, int count})> _extensionStats() {
    final counts = <String, int>{};
    for (final item in _allItems) {
      final ext = item.extension.toUpperCase();
      if (ext.isEmpty) continue;
      counts[ext] = (counts[ext] ?? 0) + 1;
    }
    final list = counts.entries
        .map((e) => (ext: e.key, count: e.value))
        .toList();
    list.sort((a, b) {
      final cmp = b.count.compareTo(a.count);
      return cmp != 0 ? cmp : a.ext.compareTo(b.ext);
    });
    if (list.length > 12) {
      return list.sublist(0, 12);
    }
    return list;
  }

  List<EntryItem> _visibleItems() {
    final q = _searchQuery.trim().toLowerCase();
    final selectedExt = _selectedExtension;
    final filtered = _allItems.where((item) {
      if (selectedExt != null && item.extension.toUpperCase() != selectedExt) {
        return false;
      }
      if (q.isNotEmpty) {
        final inName = item.nameLower.contains(q);
        final inPath = item.path.toLowerCase().contains(q);
        if (!inName && !inPath) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _CategorySortField.date:
          final am = a.dto.modifiedMillis?.toInt() ?? 0;
          final bm = b.dto.modifiedMillis?.toInt() ?? 0;
          cmp = am.compareTo(bm);
        case _CategorySortField.size:
          final asz = a.size ?? BigInt.zero;
          final bsz = b.size ?? BigInt.zero;
          cmp = asz.compareTo(bsz);
        case _CategorySortField.name:
          cmp = a.nameLower.compareTo(b.nameLower);
      }
      if (cmp != 0) {
        return _sortAscending ? cmp : -cmp;
      }
      return a.nameLower.compareTo(b.nameLower);
    });

    return filtered;
  }

  BigInt _totalSizeOf(List<EntryItem> items) {
    var total = BigInt.zero;
    for (final item in items) {
      if (item.size != null) {
        total += item.size!;
      }
    }
    return total;
  }

  void _activateSearch() {
    setState(() => _searchActive = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchActive) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() {
      _searchActive = false;
      _searchQuery = '';
    });
  }

  void _clearAllFilters() {
    if (_searchActive) {
      _searchFocusNode.unfocus();
    }
    _searchController.clear();
    setState(() {
      _selectedExtension = null;
      _searchQuery = '';
      _searchActive = false;
    });
  }

  void _selectSort(_CategorySortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = field == _CategorySortField.name;
      }
    });
  }

  static String _normalizedParentRel(String itemPath) {
    final clean = itemPath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    final slash = clean.lastIndexOf('/');
    if (slash <= 0) return '';
    return clean.substring(0, slash);
  }

  Future<void> _openItem(EntryItem item, List<EntryItem> visibleItems) async {
    final isInstaller = widget.category == 'apk' ||
        _installerExtensions.contains(item.extension);

    if (isInstaller) {
      final result = await FileOpenService.instance.openWith(widget.root, item.path);
      if (!mounted) return;
      if (result.type != ResultType.done && result.message.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
      return;
    }

    if (item.isPdf) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PdfViewerPage(
            root: widget.root,
            path: item.path,
            fileName: item.name,
          ),
        ),
      );
      return;
    }

    if (item.isVideo || item.isAudio) {
      final mediaItems = visibleItems
          .where((e) => e.isVideo || e.isAudio)
          .toList(growable: false);
      final playlist = mediaItems
          .map(
            (e) => MediaTrack(
              path: e.path,
              fileName: e.name,
              isAudio: e.isAudio,
            ),
          )
          .toList(growable: false);
      final idx = mediaItems.indexWhere((e) => e.path == item.path);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MediaPlayerPage(
            root: widget.root,
            path: item.path,
            fileName: item.name,
            isAudio: item.isAudio,
            playlist: playlist,
            startIndex: idx >= 0 ? idx : 0,
          ),
        ),
      );
      return;
    }

    if (StructuredViewerPage.supports(item.name)) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => StructuredViewerPage(
            root: widget.root,
            path: item.path,
            fileName: item.name,
          ),
        ),
      );
      return;
    }

    if (item.isText) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => TextEditorPage(
            root: widget.root,
            path: item.path,
            fileName: item.name,
            fileSizeBytes: item.size?.toInt(),
          ),
        ),
      );
      return;
    }

    if (item.isArchive) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => BrowserPage(
            initialRoot: 'archive://${joinNative(widget.root, item.path)}',
            initialPath: '',
          ),
        ),
      );
      return;
    }

    final result = await FileOpenService.instance.openWith(widget.root, item.path);
    if (!mounted) return;
    if (result.type != ResultType.done && result.message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _locateInFolder(EntryItem item) async {
    final parentRel = _normalizedParentRel(item.path);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: widget.root,
          initialPath: parentRel,
        ),
      ),
    );
  }

  Future<void> _shareItem(EntryItem item) async {
    try {
      await FileOpenService.instance.share(widget.root, item.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _showDetails(EntryItem item) {
    return showBrowserInfoDialog(
      context,
      root: widget.root,
      item: item,
      fullPath: joinNative(widget.root, item.path),
      canModifyPermissions:
          !Platform.isWindows && !Platform.isAndroid && !Platform.isIOS,
    );
  }

  Future<void> _deleteLocalFile(EntryItem item) async {
    final nativePath = joinNative(widget.root, item.path);
    final file = File(nativePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _confirmAndDelete(EntryItem item) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(l10n.deleteSingleConfirmTitle(item.name)),
          content: Text(l10n.deletePermanentWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      if (widget.onDeleteFileOverride != null) {
        await widget.onDeleteFileOverride!(item);
      } else {
        await _deleteLocalFile(item);
      }
      if (!mounted) return;
      setState(() {
        _allItems = _allItems.where((e) => e.path != item.path).toList(growable: false);
        if (_selectedExtension != null &&
            !_allItems.any((e) => e.extension.toUpperCase() == _selectedExtension)) {
          _selectedExtension = null;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.deletedItem(item.name))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.deleteFailed('$e'))),
      );
    }
  }

  Future<void> _showItemContextMenu(
    EntryItem item,
    List<EntryItem> visibleItems,
    Offset? globalPosition,
  ) async {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final size = overlay?.size ?? MediaQuery.sizeOf(context);
    final anchor = globalPosition ?? Offset(size.width / 2, size.height / 2);

    final position = RelativeRect.fromRect(
      Rect.fromLTWH(anchor.dx, anchor.dy, 1, 1),
      Offset.zero & size,
    );

    final action = await showMenu<_CategoryItemAction>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: _CategoryItemAction.open,
          child: Row(
            children: [
              const Icon(Icons.open_in_new_rounded, size: 18),
              const SizedBox(width: 10),
              Text(l10n.open),
            ],
          ),
        ),
        PopupMenuItem(
          value: _CategoryItemAction.locate,
          child: Row(
            children: [
              const Icon(Icons.folder_open_rounded, size: 18),
              const SizedBox(width: 10),
              Text(l10n.locateInFolder),
            ],
          ),
        ),
        if (PlatformCapabilities.supportsNativeShareSheet)
          PopupMenuItem(
            value: _CategoryItemAction.share,
            child: Row(
              children: [
                const Icon(Icons.share_outlined, size: 18),
                const SizedBox(width: 10),
                Text(l10n.share),
              ],
            ),
          ),
        PopupMenuItem(
          value: _CategoryItemAction.details,
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 18),
              const SizedBox(width: 10),
              Text(l10n.details),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _CategoryItemAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error),
              const SizedBox(width: 10),
              Text(
                l10n.delete,
                style: TextStyle(color: scheme.error),
              ),
            ],
          ),
        ),
      ],
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _CategoryItemAction.open:
        await _openItem(item, visibleItems);
      case _CategoryItemAction.locate:
        await _locateInFolder(item);
      case _CategoryItemAction.share:
        await _shareItem(item);
      case _CategoryItemAction.details:
        await _showDetails(item);
      case _CategoryItemAction.delete:
        await _confirmAndDelete(item);
    }
  }

  Color _itemAccentColor(BuildContext context, EntryItem item) {
    if (widget.category == 'apk' || _installerExtensions.contains(item.extension)) {
      return const Color(0xFF00ACC1);
    }
    return item.iconColor(context);
  }

  IconData _itemIcon(EntryItem item) {
    if (widget.category == 'apk' || _installerExtensions.contains(item.extension)) {
      return PlatformCapabilities.installerCategoryIcon;
    }
    return item.icon;
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    _CategoryVisual visual,
    AppLocalizations l10n,
  ) {
    return AppBar(
      titleSpacing: _searchActive ? 4 : null,
      title: _searchActive
          ? TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.filterCategoryHint(visual.title),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            )
          : Text(
              visual.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
      actions: [
        if (_searchActive)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: l10n.close,
            onPressed: _closeSearch,
          )
        else
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: l10n.searchAction,
            onPressed: _activateSearch,
          ),
        PopupMenuButton<_CategorySortField>(
          icon: const Icon(Icons.sort_rounded),
          tooltip: l10n.sortBy,
          onSelected: _selectSort,
          itemBuilder: (ctx) => [
            _buildSortMenuItem(_CategorySortField.date, l10n.sortByDate),
            _buildSortMenuItem(_CategorySortField.size, l10n.sortBySize),
            _buildSortMenuItem(_CategorySortField.name, l10n.sortByName),
          ],
        ),
        IconButton(
          icon: Icon(
            _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
          ),
          tooltip: _isGridView ? l10n.listView : l10n.gridView,
          onPressed: () => setState(() => _isGridView = !_isGridView),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: l10n.refresh,
          onPressed: _load,
        ),
      ],
    );
  }

  PopupMenuItem<_CategorySortField> _buildSortMenuItem(
    _CategorySortField field,
    String label,
  ) {
    final active = _sortField == field;
    final dirIcon = _sortAscending
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;
    return PopupMenuItem(
      value: field,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: active
                ? Icon(dirIcon, size: 16, color: Theme.of(context).colorScheme.primary)
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: active ? const TextStyle(fontWeight: FontWeight.w600) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    _CategoryVisual visual,
    AppLocalizations l10n,
    List<EntryItem> visible,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final totalBytes = _totalSizeOf(visible);
    final hasFilters = _selectedExtension != null || _searchQuery.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            visual.color.withValues(alpha: dark ? 0.18 : 0.10),
            scheme.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: visual.color.withValues(alpha: dark ? 0.30 : 0.18),
        ),
      ),
      child: Row(
        children: [
          AppCircleBadge(
            icon: visual.icon,
            color: visual.color,
            size: 44,
            iconSize: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visual.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.categorySummary(visible.length, formatBytes(totalBytes)),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (hasFilters)
            TextButton(
              onPressed: _clearAllFilters,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              child: Text(l10n.clearFilters),
            ),
        ],
      ),
    );
  }

  Widget _buildExtensionChips(
    BuildContext context,
    _CategoryVisual visual,
    AppLocalizations l10n,
    List<({String ext, int count})> stats,
  ) {
    if (stats.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final selectedBg = visual.color.withValues(alpha: dark ? 0.25 : 0.14);
    final selectedBorder = visual.color.withValues(alpha: dark ? 0.55 : 0.45);

    Widget buildChip({
      required String label,
      required bool selected,
      required VoidCallback onSelected,
    }) {
      return ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? visual.color : scheme.onSurfaceVariant,
          ),
        ),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: selectedBg,
        side: BorderSide(
          color: selected
              ? selectedBorder
              : scheme.outlineVariant.withValues(alpha: 0.5),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onSelected: (_) => onSelected(),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            buildChip(
              label: '${l10n.categoryAllFilter} (${_allItems.length})',
              selected: _selectedExtension == null,
              onSelected: () => setState(() => _selectedExtension = null),
            ),
            for (final stat in stats) ...[
              const SizedBox(width: 8),
              buildChip(
                label: '${stat.ext} (${stat.count})',
                selected: _selectedExtension == stat.ext,
                onSelected: () => setState(() {
                  _selectedExtension =
                      _selectedExtension == stat.ext ? null : stat.ext;
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExtensionBadge(
    BuildContext context,
    String ext,
    Color accentColor, {
    bool overlayStyle = false,
  }) {
    if (ext.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: overlayStyle
            ? Colors.black.withValues(alpha: 0.62)
            : accentColor.withValues(alpha: dark ? 0.20 : 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        ext.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: overlayStyle ? Colors.white : accentColor,
        ),
      ),
    );
  }

  Widget _buildMoreButton(
    BuildContext context,
    EntryItem item,
    List<EntryItem> visibleItems, {
    double size = AppUiTokens.buttonTargetSize,
    double iconSize = 18,
  }) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Builder(
      builder: (btnCtx) => AppIconButton(
        icon: Icons.more_vert_rounded,
        size: size,
        iconSize: iconSize,
        color: color,
        onPressed: () {
          final box = btnCtx.findRenderObject() as RenderBox?;
          final pos =
              box?.localToGlobal(Offset(box.size.width / 2, box.size.height));
          _showItemContextMenu(item, visibleItems, pos);
        },
      ),
    );
  }

  Widget _buildListCard(
    BuildContext context,
    EntryItem item,
    List<EntryItem> visibleItems,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final accent = _itemAccentColor(context, item);
    final parentRel = _normalizedParentRel(item.path);

    Widget leading;
    if (item.isVideo) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 44,
          color: accent.withValues(alpha: dark ? 0.18 : 0.10),
          child: EntryThumbnail(
            root: widget.root,
            relPath: item.path,
            item: item,
            size: 44,
          ),
        ),
      );
    } else {
      leading = Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: dark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(_itemIcon(item), size: 22, color: accent),
      );
    }

    return GestureDetector(
      onLongPressStart: (details) =>
          _showItemContextMenu(item, visibleItems, details.globalPosition),
      onSecondaryTapUp: (details) =>
          _showItemContextMenu(item, visibleItems, details.globalPosition),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openItem(item, visibleItems),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (item.extension.isNotEmpty) ...[
                            _buildExtensionBadge(context, item.extension, accent),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              '${item.formattedSize} · ${item.formattedModified}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (parentRel.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.folder_outlined,
                              size: 12,
                              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                shortDirectoryName(parentRel),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                _buildMoreButton(context, item, visibleItems),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    EntryItem item,
    List<EntryItem> visibleItems,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final accent = _itemAccentColor(context, item);

    return GestureDetector(
      onLongPressStart: (details) =>
          _showItemContextMenu(item, visibleItems, details.globalPosition),
      onSecondaryTapUp: (details) =>
          _showItemContextMenu(item, visibleItems, details.globalPosition),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openItem(item, visibleItems),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final thumbSize = math.max(
                      40.0,
                      math.min(constraints.maxWidth, constraints.maxHeight),
                    );
                    return Container(
                      color: accent.withValues(alpha: dark ? 0.16 : 0.08),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: item.isVideo
                                ? EntryThumbnail(
                                    root: widget.root,
                                    relPath: item.path,
                                    item: item,
                                    size: thumbSize,
                                  )
                                : Icon(
                                    _itemIcon(item),
                                    size: 40,
                                    color: accent,
                                  ),
                          ),
                          if (item.extension.isNotEmpty)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: _buildExtensionBadge(
                                context,
                                item.extension,
                                accent,
                                overlayStyle: item.isVideo,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.formattedSize} · ${item.formattedModified}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildMoreButton(
                      context,
                      item,
                      visibleItems,
                      size: 28,
                      iconSize: 16,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    _CategoryVisual visual,
    AppLocalizations l10n,
  ) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 12),
            Text(
              l10n.categoryScanning(visual.title),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return AppEmptyState(
        icon: Icons.error_outline_rounded,
        title: l10n.refreshFailed(_error!),
        action: FilledButton.tonal(
          onPressed: _load,
          child: Text(l10n.retry),
        ),
      );
    }

    final visible = _visibleItems();
    final stats = _extensionStats();

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderCard(context, visual, l10n, visible),
                if (_allItems.isNotEmpty)
                  _buildExtensionChips(context, visual, l10n, stats),
              ],
            ),
          ),
          if (_allItems.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyState(
                icon: visual.icon,
                title: l10n.categoryEmptyTitle(visual.title),
                subtitle: l10n.categoryEmptySubtitle,
              ),
            )
          else if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyState(
                icon: Icons.filter_list_off_rounded,
                title: l10n.noFilesMatching(
                  _searchQuery.trim().isNotEmpty
                      ? _searchQuery.trim()
                      : (_selectedExtension ?? ''),
                ),
                action: FilledButton.tonal(
                  onPressed: _clearAllFilters,
                  child: Text(l10n.clearFilters),
                ),
              ),
            )
          else if (_isGridView)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 210,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.86,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, idx) => _buildGridCard(ctx, visible[idx], visible),
                  childCount: visible.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (ctx, idx) => _buildListCard(ctx, visible[idx], visible),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visual = _CategoryVisual.resolve(widget.category, l10n);

    return AppSwipeBack(
      child: Scaffold(
        appBar: _buildAppBar(context, visual, l10n),
        body: _buildBody(context, visual, l10n),
      ),
    );
  }
}
