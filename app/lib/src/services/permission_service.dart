import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Android storage permission state.
///
/// On Android 11+ the app needs the "All files access" special permission
/// (`MANAGE_EXTERNAL_STORAGE`) to browse `/storage/emulated/0`. The legacy
/// READ/WRITE_EXTERNAL_STORAGE permissions are capped at SDK 32/29 in the
/// manifest and are therefore useless on current devices.
class PermissionService {
  PermissionService._();

  static final PermissionService instance = PermissionService._();

  bool get _needsStoragePermission => Platform.isAndroid;

  Future<bool> hasStorageAccess() async {
    if (!_needsStoragePermission) return true;
    return Permission.manageExternalStorage.isGranted;
  }

  /// Opens the system "All files access" screen when the permission is not
  /// granted yet. Returns whether the permission is granted afterwards.
  Future<bool> requestStorageAccess() async {
    if (!_needsStoragePermission) return true;
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    // `request()` cannot grant it directly on some OEM builds; fall back to
    // the app settings page so the user can flip the toggle manually.
    await openAppSettings();
    return Permission.manageExternalStorage.isGranted;
  }

  Future<bool> hasInstallPackagesAccess() async {
    if (!_needsStoragePermission) return true;
    return Permission.requestInstallPackages.isGranted;
  }

  Future<bool> requestInstallPackagesAccess() async {
    if (!_needsStoragePermission) return true;
    if (await hasInstallPackagesAccess()) return true;
    await Permission.requestInstallPackages.request();
    return Permission.requestInstallPackages.isGranted;
  }
}
