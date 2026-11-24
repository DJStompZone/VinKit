import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Current camera permission state tracked by [ScannerScreen].
enum CameraPermissionState {
  /// Checking existing OS permission state on startup.
  checking,

  /// Waiting for the user to respond to the OS camera permission dialog.
  requesting,

  /// Camera permission is granted and live scanning is enabled.
  granted,

  /// Camera permission is denied, but the OS can still be prompted again.
  denied,

  /// Camera permission is permanently denied or restricted; user must enable
  /// it in system app settings.
  permanentlyDenied,
}

/// Abstraction over runtime camera permission checks and requests so UI flows
/// can be deterministically verified in widget tests.
abstract class CameraPermissionService {
  /// Returns the current camera permission state without prompting the user.
  Future<CameraPermissionState> checkStatus();

  /// Requests runtime camera permission from the OS and returns the result.
  Future<CameraPermissionState> requestPermission();

  /// Opens the OS application settings page so the user can grant permission.
  Future<bool> openSettings();
}

/// Default platform implementation backed by `permission_handler`.
class PlatformCameraPermissionService implements CameraPermissionService {
  /// Creates a [PlatformCameraPermissionService].
  const PlatformCameraPermissionService();

  bool get _usesNativePermissionHandler =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  CameraPermissionState _mapStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return CameraPermissionState.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraPermissionState.permanentlyDenied;
    }
    return CameraPermissionState.denied;
  }

  @override
  Future<CameraPermissionState> checkStatus() async {
    if (!_usesNativePermissionHandler) {
      return CameraPermissionState.granted;
    }
    try {
      final status = await Permission.camera.status;
      return _mapStatus(status);
    } on MissingPluginException {
      // Allow widget tests and non-native environments to proceed smoothly.
      return CameraPermissionState.granted;
    } on UnsupportedError {
      return CameraPermissionState.granted;
    }
  }

  @override
  Future<CameraPermissionState> requestPermission() async {
    if (!_usesNativePermissionHandler) {
      return CameraPermissionState.granted;
    }
    try {
      final status = await Permission.camera.request();
      return _mapStatus(status);
    } on MissingPluginException {
      return CameraPermissionState.granted;
    } on UnsupportedError {
      return CameraPermissionState.granted;
    }
  }

  @override
  Future<bool> openSettings() async {
    if (!_usesNativePermissionHandler) {
      return false;
    }
    try {
      return await openAppSettings();
    } on MissingPluginException {
      return false;
    } on UnsupportedError {
      return false;
    }
  }
}
