import 'package:flutter/material.dart';
export '../widgets/app_swipe_back.dart';

/// Centralized UI design tokens for consistent spacing, radii, and sizing.
abstract class AppUiTokens {
  // Spacing & Padding
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(12, 6, 12, 12);
  static const EdgeInsets cardMargin = EdgeInsets.symmetric(vertical: 2.5);
  static const EdgeInsets tilePadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 2);

  // Corner radii
  static const double radiusSm = 4.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;

  static final BorderRadius borderRadiusSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(radiusLg);

  // Icon & container sizes
  static const double iconSm = 16.0;
  static const double iconMd = 18.0;
  static const double iconLg = 20.0;
  static const double avatarSize = 30.0;
  static const double buttonTargetSize = 30.0;

  // Font sizes
  static const double fontCaption = 10.0;
  static const double fontSubtitle = 11.0;
  static const double fontBody = 13.0;
  static const double fontTitle = 15.0;
}

/// Unified leading avatar badge for list tiles and cards.
class AppCircleBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  const AppCircleBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = AppUiTokens.avatarSize,
    this.iconSize = AppUiTokens.iconSm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

/// Unified compact icon button for list tiles, toolbar chips, and table actions.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final double iconSize;

  const AppIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onPressed,
    this.color,
    this.size = AppUiTokens.buttonTargetSize,
    this.iconSize = AppUiTokens.iconSm,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: iconSize, color: color),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      onPressed: onPressed,
    );
  }
}
