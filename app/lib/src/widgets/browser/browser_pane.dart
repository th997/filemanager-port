import 'dart:async';

import 'package:flutter/material.dart';

/// A [DragTarget] wrapper for folder items that highlights its border on hover
/// and automatically triggers [onHoverExpand] after [expandDelay] so users can
/// drill into nested folders during drag-and-drop without releasing the drag.
class HoverExpandDragTarget<T extends Object> extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHovering) builder;
  final void Function(T data)? onAccept;
  final VoidCallback? onHoverExpand;
  final Duration expandDelay;
  final bool showDefaultDecoration;

  const HoverExpandDragTarget({
    super.key,
    required this.builder,
    this.onAccept,
    this.onHoverExpand,
    this.expandDelay = const Duration(milliseconds: 750),
    this.showDefaultDecoration = true,
  });

  @override
  State<HoverExpandDragTarget<T>> createState() => _HoverExpandDragTargetState<T>();
}

class _HoverExpandDragTargetState<T extends Object> extends State<HoverExpandDragTarget<T>> {
  Timer? _hoverTimer;
  bool _hovering = false;

  void _startTimer() {
    _hoverTimer?.cancel();
    if (widget.onHoverExpand == null) return;
    _hoverTimer = Timer(widget.expandDelay, () {
      if (mounted && _hovering) {
        widget.onHoverExpand?.call();
      }
    });
  }

  void _cancelTimer() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return DragTarget<T>(
      onWillAcceptWithDetails: (_) {
        if (!_hovering) {
          setState(() => _hovering = true);
          _startTimer();
        }
        return true;
      },
      onLeave: (_) {
        _cancelTimer();
        if (_hovering) setState(() => _hovering = false);
      },
      onAcceptWithDetails: (details) {
        _cancelTimer();
        if (_hovering) setState(() => _hovering = false);
        widget.onAccept?.call(details.data);
      },
      builder: (context, candidate, rejected) {
        final active = _hovering || candidate.isNotEmpty;
        final built = widget.builder(context, active);
        if (!widget.showDefaultDecoration) return built;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: active
              ? BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: primary, width: 1.5),
                )
              : null,
          child: built,
        );
      },
    );
  }
}

/// Desktop marquee (rubber-band) selection overlay. Draws a translucent
/// selection rectangle while dragging on empty space and reports the local
/// [Rect] to the parent so intersecting items can be selected.
class MarqueeSelectionArea extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final void Function(Rect selectionRect)? onMarqueeUpdate;
  final VoidCallback? onMarqueeEnd;

  const MarqueeSelectionArea({
    super.key,
    required this.child,
    this.enabled = true,
    this.onMarqueeUpdate,
    this.onMarqueeEnd,
  });

  @override
  State<MarqueeSelectionArea> createState() => _MarqueeSelectionAreaState();
}

class _MarqueeSelectionAreaState extends State<MarqueeSelectionArea> {
  Offset? _start;
  Offset? _current;

  Rect? get _rect {
    if (_start == null || _current == null) return null;
    return Rect.fromPoints(_start!, _current!);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final primary = Theme.of(context).colorScheme.primary;

    return Listener(
      onPointerDown: (e) {
        // Trigger marquee on secondary-drag-free primary mouse drag when user
        // holds Alt or drags with mouse button outside interactive targets.
        if (e.buttons == 1 && e.kind.name == 'mouse') {
          _start = e.localPosition;
          _current = null;
        }
      },
      onPointerMove: (e) {
        if (_start == null) return;
        if ((e.localPosition - _start!).distance > 18) {
          setState(() => _current = e.localPosition);
          final r = _rect;
          if (r != null) widget.onMarqueeUpdate?.call(r);
        }
      },
      onPointerUp: (_) {
        if (_rect != null) {
          widget.onMarqueeEnd?.call();
        }
        if (_start != null || _current != null) {
          setState(() {
            _start = null;
            _current = null;
          });
        }
      },
      onPointerCancel: (_) {
        if (_start != null || _current != null) {
          setState(() {
            _start = null;
            _current = null;
          });
        }
      },
      child: Stack(
        children: [
          widget.child,
          if (_rect != null)
            Positioned.fromRect(
              rect: _rect!,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.14),
                    border: Border.all(color: primary, width: 1.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
