import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Displays an actionable fallback UI when camera permission is denied or the
/// camera hardware cannot initialize.
class CameraPermissionView extends StatelessWidget {
  /// Creates a [CameraPermissionView] for the given [error].
  const CameraPermissionView({
    super.key,
    required this.error,
    required this.onRetryCamera,
    required this.onManualEntry,
    this.openSettingsAction,
    this.topPadding = 24.0,
  });

  /// Exception reported by [MobileScannerController].
  final MobileScannerException error;

  /// Callback invoked when the user requests re-initializing the camera.
  final VoidCallback onRetryCamera;

  /// Callback invoked when the user chooses manual VIN entry instead.
  final VoidCallback onManualEntry;

  /// Optional settings launcher override used in tests.
  final Future<bool> Function()? openSettingsAction;

  /// Top padding inside the scrollable container (can be increased when an
  /// overlaid scanner HUD sits above this view).
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPermissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    final isUnsupported = error.errorCode == MobileScannerErrorCode.unsupported;

    final String title;
    final String description;
    final IconData icon;

    if (isPermissionDenied) {
      icon = Icons.no_photography_rounded;
      title = 'Camera Permission Required';
      description = kIsWeb
          ? 'Allow camera access using the camera or site-settings icon in your browser address bar, then tap Retry Camera — or enter a VIN manually.'
          : 'VinKit needs camera access to scan VIN barcodes on windshields and door jambs. Grant access in system settings or enter a VIN manually.';
    } else if (isUnsupported) {
      icon = Icons.videocam_off_rounded;
      title = 'Camera Scanning Unavailable';
      description =
          'Barcode scanning is not supported on this device or configuration. You can still look up vehicles by entering a VIN manually.';
    } else {
      icon = Icons.error_outline_rounded;
      title = 'Camera Unavailable';
      final rawMessage = error.errorDetails?.message?.trim();
      final looksLikeStackOrNativeDump =
          rawMessage == null ||
          rawMessage.isEmpty ||
          rawMessage.length > 140 ||
          rawMessage.contains('Exception') ||
          rawMessage.contains('SurfaceConfig') ||
          rawMessage.contains('java.lang.');
      description = looksLikeStackOrNativeDump
          ? 'Unable to start the camera preview right now. Try again or enter a VIN manually.'
          : rawMessage;
    }

    return ColoredBox(
      color: colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, topPadding, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                    child: Icon(icon, size: 36),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (isPermissionDenied && !kIsWeb) ...<Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          final launcher =
                              openSettingsAction ?? openAppSettings;
                          launcher();
                        },
                        icon: const Icon(Icons.settings_rounded),
                        label: const Text('Open App Settings'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!isUnsupported) ...<Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onRetryCamera,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry Camera'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: onManualEntry,
                      icon: const Icon(Icons.keyboard_alt_outlined),
                      label: const Text('Enter VIN Manually'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
