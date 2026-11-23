import 'dart:io';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/browser_file_ops.dart';
import '../services/platform_capabilities.dart';
import '../services/platform_paths.dart';
import 'browser_page.dart';

/// Descriptor for one open directory tab in [BrowserWorkspacePage].
class BrowserTabSpec {
  final String id;
  final String root;
  final String initialRelPath;
  final String rootLabel;
  String title;
  String locationTooltip;
  final GlobalKey<BrowserPageState> key;

  BrowserTabSpec({
    required this.id,
    required this.root,
    required this.initialRelPath,
    required this.title,
    String? rootLabel,
  })  : rootLabel = rootLabel ?? title,
        locationTooltip = initialRelPath.isEmpty ? root : '$root/$initialRelPath',
        key = GlobalKey<BrowserPageState>();
}

/// Multi-Tab + Dual-Pane Split View workspace host.
///
/// Supports:
/// - Multiple independent directory tabs (local, remote, archive, vault)
/// - Keyboard shortcuts: `Cmd/Ctrl+T` new tab, `Cmd/Ctrl+W` close tab,
///   `Cmd/Ctrl+Tab` / `Cmd/Ctrl+Shift+Tab` cycle tabs
/// - One-click toggle between Single-Pane and Dual-Pane split view
/// - Cross-pane Copy (`F5`) / Move (`F6`) and drag-and-drop between panes
class BrowserWorkspacePage extends StatefulWidget {
  final String initialRoot;
  final String initialRelPath;
  final String initialTitle;
  final bool embedded;
  final bool initialDualPane;

  static String deriveTabTitle(
    String root,
    String relPath,
    String fallbackTitle,
  ) {
    final cleanRel =
        relPath.split('/').where((s) => s.isNotEmpty).toList();
    if (cleanRel.isNotEmpty) {
      return cleanRel.last;
    }
    if (root == '/') return '/';
    if (root.startsWith('remote://') || root.startsWith('vault://')) {
      return fallbackTitle;
    }
    final cleanRoot =
        root.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
    if (cleanRoot.isNotEmpty) {
      return cleanRoot.last;
    }
    return fallbackTitle;
  }

  const BrowserWorkspacePage({
    super.key,
    required this.initialRoot,
    this.initialRelPath = '',
    required this.initialTitle,
    this.embedded = false,
    this.initialDualPane = false,
  });

  @override
  State<BrowserWorkspacePage> createState() => BrowserWorkspacePageState();
}

class BrowserWorkspacePageState extends State<BrowserWorkspacePage> {
  final List<BrowserTabSpec> _tabs = [];
  int _activeTabIndex = 0;
  int _tabSeq = 0;

  bool _dualPane = false;
  BrowserTabSpec? _rightPane;
  bool _rightPaneActive = false;

  @override
  void initState() {
    super.initState();
    _dualPane = widget.initialDualPane;
    _tabs.add(_createTab(
      root: widget.initialRoot,
      relPath: widget.initialRelPath,
      title: widget.initialTitle,
    ));
    if (_dualPane) {
      _rightPane = _createTab(
        root: widget.initialRoot,
        relPath: widget.initialRelPath,
        title: widget.initialTitle,
      );
    }
  }

  BrowserTabSpec _createTab({
    required String root,
    required String relPath,
    required String title,
  }) {
    _tabSeq++;
    return BrowserTabSpec(
      id: 'tab_$_tabSeq',
      root: root,
      initialRelPath: relPath,
      title: title,
    );
  }

  /// Open a new directory tab (callable from sidebar, context menu, or `Cmd/Ctrl+T`).
  void openTab({
    required String root,
    String relPath = '',
    required String title,
    bool switchTo = true,
  }) {
    setState(() {
      _tabs.add(_createTab(root: root, relPath: relPath, title: title));
      if (switchTo) {
        _activeTabIndex = _tabs.length - 1;
        _rightPaneActive = false;
      }
    });
  }

  /// Active pane or tab location `(root, relPath)` for context-aware actions.
  ({String root, String relPath}) get activeLocation {
    final spec = (_dualPane && _rightPaneActive && _rightPane != null)
        ? _rightPane!
        : _tabs[_activeTabIndex];
    final state = spec.key.currentState;
    return (
      root: state?.currentRoot ?? spec.root,
      relPath: state?.currentRelPath ?? spec.initialRelPath,
    );
  }

  /// Navigate the currently active pane (or left tab) to a new location.
  void navigateActivePane({
    required String root,
    String relPath = '',
    required String title,
  }) {
    if (_dualPane && _rightPaneActive && _rightPane != null) {
      setState(() {
        _rightPane = _createTab(root: root, relPath: relPath, title: title);
      });
    } else {
      setState(() {
        _tabs[_activeTabIndex] = _createTab(root: root, relPath: relPath, title: title);
      });
    }
  }

  void _newTabFromCurrent() {
    final active = _tabs[_activeTabIndex];
    final state = active.key.currentState;
    openTab(
      root: state?.currentRoot ?? active.root,
      relPath: state?.currentRelPath ?? active.initialRelPath,
      title: active.title,
    );
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      if (!widget.embedded) Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
  }

  void _cycleTab(int delta) {
    if (_tabs.length <= 1) return;
    setState(() {
      _activeTabIndex = (_activeTabIndex + delta) % _tabs.length;
      if (_activeTabIndex < 0) _activeTabIndex += _tabs.length;
    });
  }

  void _toggleDualPane() {
    setState(() {
      _dualPane = !_dualPane;
      if (_dualPane && _rightPane == null) {
        final active = _tabs[_activeTabIndex];
        final state = active.key.currentState;
        _rightPane = _createTab(
          root: state?.currentRoot ?? PlatformPaths.defaultRoot(),
          relPath: state?.currentRelPath ?? '',
          title: active.title,
        );
      }
      if (!_dualPane) {
        _rightPaneActive = false;
      }
    });
  }

  Future<void> _transferToOppositePane({required bool isMove}) async {
    if (!_dualPane || _rightPane == null) return;
    final leftState = _tabs[_activeTabIndex].key.currentState;
    final rightState = _rightPane!.key.currentState;
    if (leftState == null || rightState == null) return;

    final srcState = _rightPaneActive ? rightState : leftState;
    final dstState = _rightPaneActive ? leftState : rightState;
    final selected = srcState.selectedPathsSnapshot;
    if (selected.isEmpty) return;

    final ok = await BrowserFileOps.transferToOtherPane(
      context,
      srcRoot: srcState.currentRoot,
      srcPaths: selected,
      dstRoot: dstState.currentRoot,
      dstRelPath: dstState.currentRelPath,
      isMove: isMove,
    );
    if (ok && mounted) {
      srcState.refreshEntries();
      dstState.refreshEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isMac = Platform.isMacOS;
    final canSplit = PlatformCapabilities.supportsSideBySideSplit(context);

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyT, control: !isMac, meta: isMac):
            _newTabFromCurrent,
        SingleActivator(LogicalKeyboardKey.keyW, control: !isMac, meta: isMac): () =>
            _closeTab(_activeTabIndex),
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () => _cycleTab(1),
        const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): () =>
            _cycleTab(-1),
        const SingleActivator(LogicalKeyboardKey.f5): () =>
            _transferToOppositePane(isMove: false),
        const SingleActivator(LogicalKeyboardKey.f6): () =>
            _transferToOppositePane(isMove: true),
      },
      child: Focus(
        autofocus: false,
        child: Column(
          children: [
            // Tab strip + Dual-Pane & Cross-Pane actions bar
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tabs.length,
                      itemBuilder: (_, i) {
                        final tab = _tabs[i];
                        final selected = i == _activeTabIndex && !_rightPaneActive;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4, top: 4, bottom: 4),
                          child: Tooltip(
                            message: tab.locationTooltip,
                            waitDuration: const Duration(milliseconds: 500),
                            child: Listener(
                              onPointerDown: (e) {
                                if (e.buttons == kMiddleMouseButton && _tabs.length > 1) {
                                  _closeTab(i);
                                }
                              },
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => setState(() {
                                  _activeTabIndex = i;
                                  _rightPaneActive = false;
                                }),
                                child: Container(
                                  constraints: const BoxConstraints(maxWidth: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? scheme.primaryContainer
                                        : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.folder_outlined,
                                        size: 14,
                                        color: selected
                                            ? scheme.onPrimaryContainer
                                            : scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          tab.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                            color: selected
                                                ? scheme.onPrimaryContainer
                                                : scheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      if (_tabs.length > 1) ...[
                                        const SizedBox(width: 4),
                                        InkWell(
                                          onTap: () => _closeTab(i),
                                          child: const Icon(Icons.close, size: 13),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: '${l10n.newTab} (${isMac ? "⌘T" : "Ctrl+T"})',
                    visualDensity: VisualDensity.compact,
                    onPressed: _newTabFromCurrent,
                  ),
                  if (_dualPane && canSplit) ...[
                    IconButton(
                      icon: const Icon(Icons.file_copy_outlined, size: 16),
                      tooltip: '${l10n.copyToOtherPane} (F5)',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _transferToOppositePane(isMove: false),
                    ),
                    IconButton(
                      icon: const Icon(Icons.drive_file_move_outlined, size: 16),
                      tooltip: '${l10n.moveToOtherPane} (F6)',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _transferToOppositePane(isMove: true),
                    ),
                  ],
                  if (canSplit)
                    IconButton(
                      icon: Icon(
                        _dualPane ? Icons.view_agenda_outlined : Icons.vertical_split_outlined,
                        size: 18,
                        color: _dualPane ? scheme.primary : null,
                      ),
                      tooltip: _dualPane ? l10n.exitSplitView : l10n.splitView,
                      visualDensity: VisualDensity.compact,
                      onPressed: _toggleDualPane,
                    ),
                ],
              ),
            ),
            // Active Tab(s) / Split-Pane body
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Listener(
                      onPointerDown: (_) {
                        if (_rightPaneActive) setState(() => _rightPaneActive = false);
                      },
                      child: DecoratedBox(
                        decoration: _dualPane && !_rightPaneActive
                            ? BoxDecoration(
                                border: Border.all(
                                  color: scheme.primary.withValues(alpha: 0.45),
                                  width: 1.5,
                                ),
                              )
                            : const BoxDecoration(),
                        child: IndexedStack(
                          index: _activeTabIndex,
                          children: _tabs
                              .map(
                                (tab) => BrowserPage(
                                  key: tab.key,
                                  initialRoot: tab.root,
                                  initialPath: tab.initialRelPath,
                                  embedded: true,
                                  onOpenInNewTab: (r, p, t) =>
                                      openTab(root: r, relPath: p, title: t),
                                  onToggleSplitView: _toggleDualPane,
                                  onLocationChanged: (r, p) {
                                    final nextTitle = BrowserWorkspacePage.deriveTabTitle(
                                      r,
                                      p,
                                      tab.rootLabel,
                                    );
                                    final nextTooltip = p.isEmpty ? r : '$r/$p';
                                    if (tab.title != nextTitle ||
                                        tab.locationTooltip != nextTooltip) {
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (!mounted) return;
                                        setState(() {
                                          tab.title = nextTitle;
                                          tab.locationTooltip = nextTooltip;
                                        });
                                      });
                                    }
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                  if (_dualPane && _rightPane != null) ...[
                    VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
                    Expanded(
                      child: Listener(
                        onPointerDown: (_) {
                          if (!_rightPaneActive) setState(() => _rightPaneActive = true);
                        },
                        child: DecoratedBox(
                          decoration: _rightPaneActive
                              ? BoxDecoration(
                                  border: Border.all(
                                    color: scheme.primary.withValues(alpha: 0.45),
                                    width: 1.5,
                                  ),
                                )
                              : const BoxDecoration(),
                          child: BrowserPage(
                            key: _rightPane!.key,
                            initialRoot: _rightPane!.root,
                            initialPath: _rightPane!.initialRelPath,
                            embedded: true,
                            onOpenInNewTab: (r, p, t) =>
                                openTab(root: r, relPath: p, title: t),
                            onToggleSplitView: _toggleDualPane,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
