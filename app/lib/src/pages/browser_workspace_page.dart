import 'dart:convert';
import 'dart:io';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/browser_pane_controller.dart';
import '../services/browser_file_ops.dart';
import '../services/platform_capabilities.dart';
import '../services/platform_paths.dart';
import '../services/preferences_service.dart';
import '../services/vault_service.dart';
import 'browser_page.dart';

/// Descriptor for one open directory tab in [BrowserWorkspacePage], backed by
/// a [BrowserPaneController] instead of an imperative `GlobalKey<BrowserPageState>`.
class BrowserTabSpec {
  final String id;
  final String root;
  final String initialRelPath;
  final String rootLabel;
  String title;
  String locationTooltip;
  final ValueKey<String> widgetKey;
  final BrowserPaneController controller;

  BrowserTabSpec({
    required this.id,
    required this.root,
    required this.initialRelPath,
    required this.title,
    String? rootLabel,
  })  : rootLabel = rootLabel ?? title,
        locationTooltip = initialRelPath.isEmpty ? root : '$root/$initialRelPath',
        widgetKey = ValueKey<String>('browser_tab_$id'),
        controller = BrowserPaneController(
          root: root,
          initialRelPath: initialRelPath,
          title: title,
        );

  void dispose() {
    controller.dispose();
  }
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

  static const String _prefWorkspaceSession = 'workspace.session_v1';

  static bool _isPersistableRoot(String root) {
    return !root.startsWith('vault://') && !root.startsWith('archive://vault://');
  }

  void _saveWorkspaceSession() {
    if (!widget.embedded) return;
    final serializedTabs = <Map<String, String>>[];
    for (final tab in _tabs) {
      final root = tab.controller.root;
      final relPath = tab.controller.relPath;
      if (!_isPersistableRoot(root)) continue;
      serializedTabs.add({
        'root': root,
        'relPath': relPath,
        'title': tab.title,
      });
    }
    if (serializedTabs.isEmpty) return;

    Map<String, String>? rightData;
    if (_dualPane && _rightPane != null) {
      final rRoot = _rightPane!.controller.root;
      final rRel = _rightPane!.controller.relPath;
      if (_isPersistableRoot(rRoot)) {
        rightData = {
          'root': rRoot,
          'relPath': rRel,
          'title': _rightPane!.title,
        };
      }
    }

    final payload = {
      'activeIndex': _activeTabIndex.clamp(0, serializedTabs.length - 1),
      'dualPane': _dualPane && rightData != null,
      'tabs': serializedTabs,
      'rightPane': ?rightData,
    };
    PreferencesService.instance.setString(
      _prefWorkspaceSession,
      jsonEncode(payload),
    );
  }

  bool _restoreWorkspaceSession() {
    if (!widget.embedded) return false;
    final raw = PreferencesService.instance.getString(_prefWorkspaceSession);
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      final rawTabs = decoded['tabs'];
      if (rawTabs is! List || rawTabs.isEmpty) return false;
      for (final item in rawTabs) {
        if (item is! Map) continue;
        final root = item['root']?.toString() ?? '';
        final relPath = item['relPath']?.toString() ?? '';
        final title = item['title']?.toString() ?? '';
        if (root.isEmpty || !_isPersistableRoot(root)) continue;
        _tabs.add(_createTab(
          root: root,
          relPath: relPath,
          title: title.isEmpty ? widget.initialTitle : title,
        ));
      }
      if (_tabs.isEmpty) return false;
      final idx = decoded['activeIndex'];
      if (idx is int) {
        _activeTabIndex = idx.clamp(0, _tabs.length - 1);
      }
      final savedDual = decoded['dualPane'] == true;
      final rawRight = decoded['rightPane'];
      if (savedDual && rawRight is Map) {
        final rRoot = rawRight['root']?.toString() ?? '';
        final rRel = rawRight['relPath']?.toString() ?? '';
        final rTitle = rawRight['title']?.toString() ?? widget.initialTitle;
        if (rRoot.isNotEmpty && _isPersistableRoot(rRoot)) {
          _dualPane = true;
          _rightPane = _createTab(
            root: rRoot,
            relPath: rRel,
            title: rTitle,
          );
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    VaultService.instance.registerLockCleanup(_onVaultLocked);
    _dualPane = widget.initialDualPane;
    if (!_restoreWorkspaceSession()) {
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
  }

  @override
  void dispose() {
    VaultService.instance.unregisterLockCleanup(_onVaultLocked);
    for (final tab in _tabs) {
      tab.dispose();
    }
    _rightPane?.dispose();
    super.dispose();
  }

  static bool matchesLockedVault(String root, String? vaultId) {
    if (vaultId == null) {
      return root.startsWith('vault://') || root.startsWith('archive://vault://');
    }
    return root == 'vault://$vaultId' ||
        root.startsWith('vault://$vaultId/') ||
        root == 'archive://vault://$vaultId' ||
        root.startsWith('archive://vault://$vaultId/') ||
        root.startsWith('archive://vault://$vaultId|');
  }

  void _onVaultLocked(String? vaultId) {
    if (!mounted) return;
    var changed = false;
    final remaining = <BrowserTabSpec>[];
    final removed = <BrowserTabSpec>[];
    for (final tab in _tabs) {
      final root = tab.controller.root;
      if (matchesLockedVault(root, vaultId)) {
        changed = true;
        removed.add(tab);
      } else {
        remaining.add(tab);
      }
    }
    var rightChanged = false;
    if (_rightPane != null) {
      final rRoot = _rightPane!.controller.root;
      if (matchesLockedVault(rRoot, vaultId)) {
        rightChanged = true;
        changed = true;
      }
    }
    if (!changed) return;
    final oldRight = rightChanged ? _rightPane : null;
    setState(() {
      _tabs
        ..clear()
        ..addAll(remaining);
      if (_tabs.isEmpty) {
        final fallbackRoot = PlatformPaths.defaultRoot();
        _tabs.add(_createTab(
          root: fallbackRoot,
          relPath: '',
          title: BrowserWorkspacePage.deriveTabTitle(
            fallbackRoot,
            '',
            widget.initialTitle,
          ),
        ));
      }
      _activeTabIndex = _activeTabIndex.clamp(0, _tabs.length - 1);
      if (rightChanged) {
        _rightPane = null;
        _dualPane = false;
        _rightPaneActive = false;
      }
    });
    for (final t in removed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => t.dispose());
    }
    if (oldRight != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => oldRight.dispose());
    }
    _saveWorkspaceSession();
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
    _saveWorkspaceSession();
  }

  /// Active pane or tab location `(root, relPath)` for context-aware actions.
  ({String root, String relPath}) get activeLocation {
    final spec = (_dualPane && _rightPaneActive && _rightPane != null)
        ? _rightPane!
        : _tabs[_activeTabIndex];
    return (
      root: spec.controller.root,
      relPath: spec.controller.relPath,
    );
  }

  /// Navigate the currently active pane (or left tab) to a new location.
  void navigateActivePane({
    required String root,
    String relPath = '',
    required String title,
  }) {
    if (_dualPane && _rightPaneActive && _rightPane != null) {
      final old = _rightPane;
      setState(() {
        _rightPane = _createTab(root: root, relPath: relPath, title: title);
      });
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } else {
      final old = _tabs[_activeTabIndex];
      setState(() {
        _tabs[_activeTabIndex] = _createTab(root: root, relPath: relPath, title: title);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _saveWorkspaceSession();
  }

  void _newTabFromCurrent() {
    final active = _tabs[_activeTabIndex];
    openTab(
      root: active.controller.root,
      relPath: active.controller.relPath,
      title: active.title,
    );
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      if (!widget.embedded) Navigator.of(context).maybePop();
      return;
    }
    final removed = _tabs[index];
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    _saveWorkspaceSession();
  }

  void _cycleTab(int delta) {
    if (_tabs.length <= 1) return;
    setState(() {
      _activeTabIndex = (_activeTabIndex + delta) % _tabs.length;
      if (_activeTabIndex < 0) _activeTabIndex += _tabs.length;
    });
    _saveWorkspaceSession();
  }

  void _toggleDualPane() {
    setState(() {
      _dualPane = !_dualPane;
      if (_dualPane && _rightPane == null) {
        final active = _tabs[_activeTabIndex];
        _rightPane = _createTab(
          root: active.controller.root.isNotEmpty
              ? active.controller.root
              : PlatformPaths.defaultRoot(),
          relPath: active.controller.relPath,
          title: active.title,
        );
      }
      if (!_dualPane) {
        _rightPaneActive = false;
      }
    });
    _saveWorkspaceSession();
  }

  Future<void> _transferToOppositePane({required bool isMove}) async {
    if (!_dualPane || _rightPane == null) return;
    final leftCtrl = _tabs[_activeTabIndex].controller;
    final rightCtrl = _rightPane!.controller;

    final srcCtrl = _rightPaneActive ? rightCtrl : leftCtrl;
    final dstCtrl = _rightPaneActive ? leftCtrl : rightCtrl;
    final selected = srcCtrl.selectedPaths.toList(growable: false);
    if (selected.isEmpty) return;

    final ok = await BrowserFileOps.transferToOtherPane(
      context,
      srcRoot: srcCtrl.root,
      srcPaths: selected,
      dstRoot: dstCtrl.root,
      dstRelPath: dstCtrl.relPath,
      isMove: isMove,
    );
    if (ok && mounted) {
      srcCtrl.requestRefresh();
      dstCtrl.requestRefresh();
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
                                  key: tab.widgetKey,
                                  paneController: tab.controller,
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
                                        _saveWorkspaceSession();
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
                            key: _rightPane!.widgetKey,
                            paneController: _rightPane!.controller,
                            initialRoot: _rightPane!.root,
                            initialPath: _rightPane!.initialRelPath,
                            embedded: true,
                            onOpenInNewTab: (r, p, t) =>
                                openTab(root: r, relPath: p, title: t),
                            onToggleSplitView: _toggleDualPane,
                            onLocationChanged: (r, p) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted || _rightPane == null) return;
                                final nextTitle = BrowserWorkspacePage.deriveTabTitle(
                                  r,
                                  p,
                                  widget.initialTitle,
                                );
                                final nextTooltip = r.startsWith('vault://')
                                    ? ''
                                    : (p.isEmpty ? r : '$r/$p');
                                _rightPane!.title = nextTitle;
                                _rightPane!.locationTooltip = nextTooltip;
                                _saveWorkspaceSession();
                              });
                            },
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
