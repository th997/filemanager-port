import 'package:flutter/material.dart';

/// Semantic status colors the stock [ColorScheme] does not carry.
///
/// Until now every error/success/warning surface picked its own red or
/// green (four different reds across snackbars alone), and
/// `colorScheme.error` was used nowhere. New code should take status
/// colors from here so light and dark themes stay consistent.
extension SemanticColors on ColorScheme {
  Color get success => brightness == Brightness.light
      ? const Color(0xFF2E7D32)
      : const Color(0xFF66BB6A);

  Color get onSuccess => Colors.white;

  Color get warning => brightness == Brightness.light
      ? const Color(0xFFEF6C00)
      : const Color(0xFFFFA726);

  Color get onWarning => Colors.white;
}
