import 'package:filemanager/l10n/app_localizations.dart';
/// Turns raw backend/FFI errors into something a person can act on.
/// The original text is kept in parentheses — it is often the only clue
/// when reporting a bug — but the headline is plain language.
String friendlyErrorText(Object error, [AppLocalizations? l10n]) {
  final text = error.toString();
  final lower = text.toLowerCase();
  if (text.startsWith('path not found:')) {
    return l10n?.errorFolderNotFound(text) ??
        'This folder no longer exists. It may have been deleted or renamed.\n($text)';
  }
  if (text.startsWith('permission denied:')) {
    return l10n?.errorPermissionDenied(text) ??
        'Permission denied. Grant storage access or pick another folder.\n($text)';
  }
  if (lower.contains('authentication') ||
      lower.contains('auth failed') ||
      lower.contains('login failed') ||
      lower.contains('invalid credentials') ||
      lower.contains('access denied')) {
    return l10n?.errorSignInFailed(text) ??
        'Sign-in failed. Check the username and password.\n($text)';
  }
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return l10n?.errorServerTimeout(text) ??
        'The server took too long to respond. Check the address and your network.\n($text)';
  }
  if (text.startsWith('connection failed:') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('unreachable') ||
      lower.contains('failed to lookup') ||
      lower.contains('no route to host')) {
    return l10n?.errorCannotReachServer(text) ??
        'Cannot reach the server. Check the address, port and your network.\n($text)';
  }
  return text;
}
