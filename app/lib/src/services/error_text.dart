import 'package:filemanager/l10n/app_localizations.dart';

/// Actionable recovery category derived from backend/FFI errors so UI surfaces
/// can offer targeted fixes (e.g., permission prompt, credential edit, retry).
enum ErrorRecoveryKind {
  none,
  storagePermission,
  remoteCredentials,
  hostKeyTrust,
  archivePassword,
  storageSpace,
  networkRetry,
}

/// Classifies an arbitrary backend/FFI exception into a suggested [ErrorRecoveryKind].
ErrorRecoveryKind detectErrorRecovery(Object error) {
  final text = error.toString();
  final lower = text.toLowerCase();
  if (lower.contains('host key') || lower.contains('fingerprint mismatch')) {
    return ErrorRecoveryKind.hostKeyTrust;
  }
  if (lower.contains('wrong password') ||
      lower.contains('invalid password') ||
      lower.contains('encrypted archive')) {
    return ErrorRecoveryKind.archivePassword;
  }
  if (lower.contains('no space left') || lower.contains('disk full')) {
    return ErrorRecoveryKind.storageSpace;
  }
  final isAuthCancelled = lower.contains('authentication cancelled') ||
      lower.contains('authentication canceled');
  if (lower.contains('signaturedoesnotmatch') ||
      lower.contains('invalidaccesskeyid') ||
      lower.contains('nosuchbucket') ||
      lower.contains('permanentredirect') ||
      lower.contains('status_bad_network_name') ||
      lower.contains('status_logon_failure') ||
      (!isAuthCancelled && lower.contains('authentication')) ||
      lower.contains('auth failed') ||
      lower.contains('login failed') ||
      lower.contains('invalid credentials') ||
      lower.contains('access denied') ||
      lower.contains('permission denied (publickey') ||
      (lower.contains('sftp') && lower.contains('permission denied'))) {
    return ErrorRecoveryKind.remoteCredentials;
  }
  if (text.startsWith('permission denied:') ||
      lower.contains('permission denied') ||
      lower.contains('operation not permitted')) {
    return ErrorRecoveryKind.storagePermission;
  }
  if (lower.contains('timed out') ||
      lower.contains('timeout') ||
      text.startsWith('connection failed:') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('unreachable') ||
      lower.contains('failed to lookup') ||
      lower.contains('no route to host')) {
    return ErrorRecoveryKind.networkRetry;
  }
  return ErrorRecoveryKind.none;
}

/// Turns raw backend/FFI errors into actionable guidance.
/// The original text is kept in parentheses for diagnostics and bug reports.
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
  if (lower.contains('host key') || lower.contains('fingerprint mismatch')) {
    return l10n?.errorSftpHostKey(text) ??
        'SSH host key verification failed. Confirm the server identity or re-save the SFTP connection.\n($text)';
  }
  if (lower.contains('signaturedoesnotmatch') ||
      lower.contains('invalidaccesskeyid') ||
      lower.contains('nosuchbucket') ||
      lower.contains('permanentredirect')) {
    return l10n?.errorObjectStorageConfig(text) ??
        'Object storage configuration error. Check the bucket name, endpoint, region, and access keys.\n($text)';
  }
  if (lower.contains('status_bad_network_name') ||
      lower.contains('status_logon_failure')) {
    return l10n?.errorSmbConnection(text) ??
        'SMB share connection failed. Verify the share name, username/password, and SMB port (445).\n($text)';
  }
  if (lower.contains('wrong password') ||
      lower.contains('invalid password') ||
      lower.contains('encrypted archive')) {
    return l10n?.errorArchivePassword(text) ??
        'Archive password is missing or incorrect. Re-enter the password and try again.\n($text)';
  }
  if (lower.contains('no space left') || lower.contains('disk full')) {
    return l10n?.errorDiskFull(text) ??
        'Not enough free storage space on the destination volume.\n($text)';
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
