import 'package:flutter/material.dart';

/// Wraps secondary pages to support effortless swipe-to-back gesture
/// with a comfortable detection edge (up to 140px) or quick right swipe fling.
class AppSwipeBack extends StatefulWidget {
  final Widget child;
  final VoidCallback? onBack;

  const AppSwipeBack({
    super.key,
    required this.child,
    this.onBack,
  });

  @override
  State<AppSwipeBack> createState() => _AppSwipeBackState();
}

class _AppSwipeBackState extends State<AppSwipeBack> {
  double _startX = 0;
  double _deltaX = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        _startX = details.globalPosition.dx;
        _deltaX = 0;
      },
      onHorizontalDragUpdate: (details) {
        _deltaX = details.globalPosition.dx - _startX;
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final fromLeftEdge = _startX < 140;
        if (fromLeftEdge && (_deltaX > 35 || (velocity > 260 && _deltaX > 20))) {
          if (widget.onBack != null) {
            widget.onBack!();
          } else if (Navigator.of(context).canPop()) {
            Navigator.of(context).maybePop();
          }
        }
        _startX = 0;
        _deltaX = 0;
      },
      onHorizontalDragCancel: () {
        _startX = 0;
        _deltaX = 0;
      },
      child: widget.child,
    );
  }
}
