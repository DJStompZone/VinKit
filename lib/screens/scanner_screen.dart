import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vinkit_app/screens/vehicle_result_screen.dart';
import 'package:vinkit_app/services/scanner_feedback_service.dart';
import 'package:vinkit_app/services/vin_lookup_controller.dart';
import 'package:vinkit_app/services/vin_validator.dart';
import 'package:vinkit_app/widgets/camera_permission_view.dart';
import 'package:vinkit_app/widgets/desktop_vin_entry_view.dart';
import 'package:vinkit_app/widgets/manual_vin_sheet.dart';
import 'package:vinkit_app/widgets/scanner_controls.dart';
import 'package:vinkit_app/widgets/scanner_overlay.dart';

/// Primary live camera barcode scanning screen for automotive VIN barcodes.
///
/// Automatically falls back to [DesktopVinEntryView] on desktop targets
/// (Windows and Linux) where `mobile_scanner` has no native camera plugin.
class ScannerScreen extends StatefulWidget {
  /// Creates a [ScannerScreen].
  const ScannerScreen({
    super.key,
    required this.vinController,
    required this.validator,
    required this.themeMode,
    required this.onCycleThemeMode,
    this.feedbackService = const PlatformScannerFeedbackService(),
    this.cameraScannerSupportedOverride,
  });

  /// Controller orchestrating VIN lookups and result states.
  final VinLookupController vinController;

  /// Validator used to extract and validate VINs from barcodes and input.
  final VinValidator validator;

  /// Active application theme mode shown in the top bar toggle.
  final ThemeMode themeMode;

  /// Callback cycling between system, light, and dark themes.
  final VoidCallback onCycleThemeMode;

  /// Service playing audible beep and haptic confirmation on valid VIN scans.
  final ScannerFeedbackService feedbackService;

  /// Optional platform capability override used by widget tests.
  final bool? cameraScannerSupportedOverride;

  /// Whether `mobile_scanner` provides a native implementation on the current
  /// platform (`android`, `ios`, `macos`, `web`).
  static bool isCameraScannerSupported() {
    if (kIsWeb) {
      return true;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS =>
        true,
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia =>
        false,
    };
  }

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  MobileScannerController? _scannerController;

  double _zoomScale = 0.0;
  bool _isScanLocked = false;
  String? _statusMessage;
  DateTime? _lastInvalidBannerAt;
  Timer? _statusTimer;

  bool get _supportsCameraScanner =>
      widget.cameraScannerSupportedOverride ??
      ScannerScreen.isCameraScannerSupported();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_supportsCameraScanner) {
      _scannerController = MobileScannerController(
        formats: const <BarcodeFormat>[
          BarcodeFormat.code39,
          BarcodeFormat.code128,
        ],
        detectionSpeed: DetectionSpeed.normal,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_scannerController == null) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_pauseCamera());
    } else if (state == AppLifecycleState.resumed && !_isScanLocked) {
      unawaited(_resumeCamera());
    }
  }

  Future<void> _pauseCamera() async {
    final controller = _scannerController;
    if (controller == null) {
      return;
    }
    final scannerState = controller.value;
    if (!scannerState.isInitialized || !scannerState.isRunning) {
      return;
    }
    try {
      await controller.pause();
    } on MobileScannerException catch (error) {
      debugPrint('Failed to pause camera: ${error.errorCode}');
    } on MissingPluginException {
      // No native scanner plugin on this platform.
    }
  }

  Future<void> _stopScanning() async {
    final controller = _scannerController;
    if (controller == null) {
      return;
    }
    final scannerState = controller.value;
    if (!scannerState.isInitialized && !scannerState.isRunning) {
      return;
    }
    try {
      await controller.stop();
    } on MobileScannerException catch (error) {
      debugPrint('Failed to stop scanner: ${error.errorCode}');
    } on MissingPluginException {
      // No native scanner plugin on this platform.
    }
  }

  Future<void> _resumeCamera() async {
    final controller = _scannerController;
    if (controller == null || !mounted || _isScanLocked) {
      return;
    }
    final scannerState = controller.value;
    if (scannerState.isRunning || scannerState.isStarting) {
      return;
    }
    try {
      await controller.start();
      if (mounted && !_isScanLocked && _zoomScale > 0.0) {
        await controller.setZoomScale(_zoomScale);
      }
    } on MobileScannerException catch (error) {
      debugPrint('Failed to resume camera: ${error.errorCode}');
    } on MissingPluginException {
      // No native scanner plugin on this platform.
    }
  }

  Future<void> _setZoomScale(double zoom) async {
    final clamped = zoom.clamp(0.0, 1.0);
    setState(() => _zoomScale = clamped);
    final controller = _scannerController;
    if (controller == null) {
      return;
    }
    final scannerState = controller.value;
    if (!scannerState.isInitialized || !scannerState.isRunning) {
      return;
    }
    try {
      await controller.setZoomScale(clamped);
    } on MobileScannerException catch (error) {
      debugPrint('Failed to update zoom: ${error.errorCode}');
    } on MissingPluginException {
      // No native scanner plugin on this platform.
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _scannerController;
    if (controller == null) {
      return;
    }
    final scannerState = controller.value;
    if (!scannerState.isInitialized || !scannerState.isRunning) {
      return;
    }
    try {
      await controller.toggleTorch();
    } on MobileScannerException catch (error) {
      debugPrint('Failed to toggle torch: ${error.errorCode}');
    } on MissingPluginException {
      // No native scanner plugin on this platform.
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isScanLocked || !mounted) {
      return;
    }

    for (final barcode in capture.barcodes) {
      final candidate = widget.validator.extractFromBarcode(barcode.rawValue) ??
          widget.validator.extractFromBarcode(barcode.displayValue);
      if (candidate != null) {
        // Lock synchronously before any async work to guarantee a single scan.
        _isScanLocked = true;
        _clearStatusMessage();
        // Immediately BEEP + vibrate and halt the scanner on valid VIN lock.
        unawaited(widget.feedbackService.playValidScanFeedback());
        unawaited(_stopScanning());
        unawaited(_openVehicleResultScreen(candidate));
        return;
      }
    }

    if (capture.barcodes.isNotEmpty) {
      _showTransientStatus('Scanned barcode is not a valid 17-character VIN');
    }
  }

  void _showTransientStatus(String message) {
    final now = DateTime.now();
    if (_lastInvalidBannerAt != null &&
        now.difference(_lastInvalidBannerAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastInvalidBannerAt = now;
    _statusTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _statusMessage = message);
    _statusTimer = Timer(const Duration(seconds: 2), _clearStatusMessage);
  }

  void _clearStatusMessage() {
    _statusTimer?.cancel();
    _statusTimer = null;
    if (mounted && _statusMessage != null) {
      setState(() => _statusMessage = null);
    }
  }

  Future<void> _openManualEntrySheet({
    String? initialVin,
    bool alreadyLocked = false,
  }) async {
    if ((!alreadyLocked && _isScanLocked) || !mounted) {
      return;
    }
    setState(() => _isScanLocked = true);
    unawaited(_stopScanning());

    final enteredVin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ManualVinSheet(
        validator: widget.validator,
        initialVin: initialVin,
      ),
    );

    if (!mounted) {
      return;
    }

    if (enteredVin != null && enteredVin.isNotEmpty) {
      await _openVehicleResultScreen(enteredVin);
      return;
    }

    setState(() => _isScanLocked = false);
    await _resumeCamera();
  }

  Future<void> _openVehicleResultScreen(String vin) async {
    if (!mounted) {
      return;
    }
    setState(() => _isScanLocked = true);
    unawaited(widget.vinController.lookupVin(vin));

    final closeAction = await Navigator.of(context).push<VehicleResultAction>(
      MaterialPageRoute<VehicleResultAction>(
        builder: (_) => VehicleResultScreen(
          controller: widget.vinController,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    widget.vinController.reset();

    if (closeAction == VehicleResultAction.enterDifferentVin) {
      if (_supportsCameraScanner) {
        await _openManualEntrySheet(initialVin: vin, alreadyLocked: true);
        return;
      }
      setState(() => _isScanLocked = false);
      return;
    }

    setState(() => _isScanLocked = false);
    await _resumeCamera();
  }

  IconData _themeIconFor(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
      ThemeMode.system => Icons.brightness_auto_rounded,
    };
  }

  String _themeTooltipFor(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'Theme: Light (tap to switch)',
      ThemeMode.dark => 'Theme: Dark (tap to switch)',
      ThemeMode.system => 'Theme: System (tap to switch)',
    };
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final controller = _scannerController;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _scannerController;
    if (controller == null) {
      return DesktopVinEntryView(
        validator: widget.validator,
        themeMode: widget.themeMode,
        onCycleThemeMode: widget.onCycleThemeMode,
        onSubmitVin: (vin) {
          unawaited(widget.feedbackService.playValidScanFeedback());
          unawaited(_openVehicleResultScreen(vin));
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final scanWidth = math.min(width * 0.88, 420.0);
          final scanHeight = 104.0;
          final scanCenterY = math.max(150.0, height * 0.36);
          final scanWindow = Rect.fromCenter(
            center: Offset(width / 2, scanCenterY),
            width: scanWidth,
            height: scanHeight,
          );

          return ValueListenableBuilder<MobileScannerState>(
            valueListenable: controller,
            builder: (context, scannerState, _) {
              final hasError = scannerState.error != null;

              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  MobileScanner(
                    controller: controller,
                    scanWindow: scanWindow,
                    fit: BoxFit.cover,
                    onDetect: _onBarcodeDetected,
                    placeholderBuilder: (_) => const ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    errorBuilder: (_, error) => CameraPermissionView(
                      error: error,
                      onRetryCamera: () => unawaited(_resumeCamera()),
                      onManualEntry: () => unawaited(_openManualEntrySheet()),
                    ),
                    overlayBuilder: (_, _) => ScannerOverlay(
                      scanWindow: scanWindow,
                      isPaused: _isScanLocked || !scannerState.isRunning,
                      statusMessage: _statusMessage,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.qr_code_scanner_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'VinKit',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton.filledTonal(
                              onPressed: widget.onCycleThemeMode,
                              tooltip: _themeTooltipFor(widget.themeMode),
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    Colors.black.withValues(alpha: 0.62),
                                foregroundColor: Colors.white,
                              ),
                              icon: Icon(_themeIconFor(widget.themeMode)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!hasError)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ScannerControls(
                        zoomScale: _zoomScale,
                        torchState: scannerState.torchState,
                        isCameraRunning:
                            scannerState.isInitialized && scannerState.isRunning,
                        onZoomChanged: (value) =>
                            unawaited(_setZoomScale(value)),
                        onToggleTorch: () => unawaited(_toggleTorch()),
                        onManualEntryTap: () =>
                            unawaited(_openManualEntrySheet()),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
