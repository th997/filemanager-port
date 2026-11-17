import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps secondary pages to support effortless swipe-to-back gesture
/// with a comfortable detection edge or quick right swipe fling.
class AppSwipeBack extends StatefulWidget {
  final Widget child;
  final VoidCallback? onBack;
  final double? edgeThreshold;

  const AppSwipeBack({
    super.key,
    required this.child,
    this.onBack,
    this.edgeThreshold,
  });

  @override
  State<AppSwipeBack> createState() => _AppSwipeBackState();
}

class _AppSwipeBackState extends State<AppSwipeBack> {
  double? _downX;
  double _startX = 0;
  double _deltaX = 0;

  @override
  Widget build(BuildContext context) {
    final edge = widget.edgeThreshold ??
        (MediaQuery.sizeOf(context).width * 0.45).clamp(140.0, 220.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragDown: (details) {
        _downX = details.globalPosition.dx;
      },
      onHorizontalDragStart: (details) {
        _startX = _downX ?? details.globalPosition.dx;
        _deltaX = 0;
      },
      onHorizontalDragUpdate: (details) {
        _deltaX = details.globalPosition.dx - _startX;
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final fromLeftEdge = _startX < edge;
        if (fromLeftEdge && (_deltaX > 35 || (velocity > 220 && _deltaX > 15))) {
          HapticFeedback.lightImpact();
          if (widget.onBack != null) {
            widget.onBack!();
          } else {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.maybePop();
            }
          }
        }
        _downX = null;
        _startX = 0;
        _deltaX = 0;
      },
      onHorizontalDragCancel: () {
        _downX = null;
        _startX = 0;
        _deltaX = 0;
      },
      child: widget.child,
    );
  }
}

