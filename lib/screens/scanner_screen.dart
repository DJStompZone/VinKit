import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vinkit_app/screens/vehicle_result_screen.dart';
import 'package:vinkit_app/services/scanner_feedback_service.dart';
import 'package:vinkit_app/services/vin_lookup_controller.dart';
import 'package:vinkit_app/services/vin_ocr_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';
import 'package:vinkit_app/widgets/camera_permission_view.dart';
import 'package:vinkit_app/widgets/desktop_vin_entry_view.dart';
import 'package:vinkit_app/widgets/manual_vin_sheet.dart';
import 'package:vinkit_app/widgets/ocr_camera_view.dart';
import 'package:vinkit_app/widgets/scanner_controls.dart';
import 'package:vinkit_app/widgets/scanner_overlay.dart';

/// Active camera acquisition mode on [ScannerScreen].
enum ScannerCaptureMode {
  /// Continuous barcode scanning (Code 39, Code 128, Code 93, DataMatrix,
  /// PDF417, QR).
  barcode,

  /// On-device plaintext VIN OCR powered by ONNX Runtime Mobile (PaddleOCR v5
  /// on Android) and Apple Vision (on iOS).
  ocr,
}

/// Builder signature allowing tests to supply a lightweight OCR camera view.
typedef OcrViewBuilder = Widget Function(
  BuildContext context, {
  required VinOcrService ocrService,
  required VinValidator validator,
  required VinScanStrictness strictness,
  required Rect scanWindow,
  required bool isPaused,
  required ValueChanged<String> onVinRecognized,
  required ValueChanged<String?> onManualEntryTap,
  required VoidCallback onSwitchStrictnessToNormal,
});

/// Primary live camera VIN scanning screen supporting both barcode scanning and
/// on-device plaintext VIN OCR, with configurable Normal/Strict matching.
///
/// Automatically falls back to [DesktopVinEntryView] on desktop targets
/// (Windows and Linux) where live camera scanning is unavailable.
class ScannerScreen extends StatefulWidget {
  /// Creates a [ScannerScreen].
  const ScannerScreen({
    super.key,
    required this.vinController,
    required this.validator,
    required this.themeMode,
    required this.onCycleThemeMode,
    this.feedbackService = const PlatformScannerFeedbackService(),
    this.ocrService,
    this.initialStrictness = VinScanStrictness.normal,
    this.cameraScannerSupportedOverride,
    this.ocrViewBuilder,
  });

  /// Controller orchestrating VIN lookups and result states.
  final VinLookupController vinController;

  /// Validator used to extract and validate VINs from barcodes, OCR, and input.
  final VinValidator validator;

  /// Active application theme mode shown in the top bar toggle.
  final ThemeMode themeMode;

  /// Callback cycling between system, light, and dark themes.
  final VoidCallback onCycleThemeMode;

  /// Service playing audible beep and haptic confirmation on valid VIN scans.
  final ScannerFeedbackService feedbackService;

  /// Optional on-device OCR service override for tests or custom backends.
  final VinOcrService? ocrService;

  /// Initial VIN matching strictness (`Normal` by default).
  final VinScanStrictness initialStrictness;

  /// Optional platform capability override used by widget tests.
  final bool? cameraScannerSupportedOverride;

  /// Optional OCR view builder override used by widget tests.
  final OcrViewBuilder? ocrViewBuilder;

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
  late final VinOcrService _ocrService;

  ScannerCaptureMode _captureMode = ScannerCaptureMode.barcode;
  late VinScanStrictness _strictness;
  bool _isSwitchingMode = false;

  double _zoomScale = 0.0;
  bool _isScanLocked = false;
  String? _statusMessage;
  String? _statusActionLabel;
  VoidCallback? _statusAction;
  DateTime? _lastInvalidBannerAt;
  Timer? _statusTimer;

  bool get _supportsCameraScanner =>
      widget.cameraScannerSupportedOverride ??
      ScannerScreen.isCameraScannerSupported();

  bool get _supportsOcr => _ocrService.isSupported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _strictness = widget.initialStrictness;
    _ocrService = widget.ocrService ?? createPlatformVinOcrService();
    if (_supportsCameraScanner) {
      _scannerController = MobileScannerController(
        formats: const <BarcodeFormat>[
          BarcodeFormat.code39,
          BarcodeFormat.code128,
          BarcodeFormat.code93,
          BarcodeFormat.dataMatrix,
          BarcodeFormat.pdf417,
          BarcodeFormat.qrCode,
        ],
        detectionSpeed: DetectionSpeed.normal,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_scannerController == null || _captureMode != ScannerCaptureMode.barcode) {
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
    } on UnsupportedError {
      // Camera pause not supported on this browser/platform.
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
    } on UnsupportedError {
      // Camera stop not supported on this browser/platform.
    }
  }

  Future<void> _resumeCamera() async {
    final controller = _scannerController;
    if (controller == null ||
        !mounted ||
        _isScanLocked ||
        _captureMode != ScannerCaptureMode.barcode) {
      return;
    }
    final scannerState = controller.value;
    if (scannerState.isRunning || scannerState.isStarting) {
      return;
    }
    try {
      await controller.start();
      if (mounted &&
          !_isScanLocked &&
          _captureMode == ScannerCaptureMode.barcode &&
          !kIsWeb &&
          _zoomScale > 0.0) {
        await controller.setZoomScale(_zoomScale);
      }
    } on MobileScannerException catch (error) {
      debugPrint('Failed to resume camera: ${error.errorCode}');
    } on MissingPluginException {
      // No native scanner plugin on this platform.
    } on UnsupportedError {
      // Zoom or start option unsupported on this platform.
    }
  }

  Future<void> _switchCaptureMode(ScannerCaptureMode targetMode) async {
    if (_captureMode == targetMode || _isSwitchingMode || _isScanLocked) {
      return;
    }
    if (targetMode == ScannerCaptureMode.ocr && !_supportsOcr) {
      return;
    }

    _clearStatusMessage();
    setState(() => _isSwitchingMode = true);

    if (targetMode == ScannerCaptureMode.ocr) {
      // Release the barcode scanner's camera hardware before opening CameraController.
      await _stopScanning();
      if (!mounted) {
        return;
      }
      setState(() {
        _captureMode = ScannerCaptureMode.ocr;
        _isSwitchingMode = false;
      });
      return;
    }

    // Switching back from OCR to Barcode: unmount OcrCameraView first so its
    // CameraController disposes, then start MobileScannerController.
    setState(() {
      _captureMode = ScannerCaptureMode.barcode;
    });
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _resumeCamera();
    if (mounted) {
      setState(() => _isSwitchingMode = false);
    }
  }

  void _setStrictness(VinScanStrictness strictness) {
    if (_strictness == strictness) {
      return;
    }
    _clearStatusMessage();
    setState(() => _strictness = strictness);
  }

  Future<void> _setZoomScale(double zoom) async {
    if (kIsWeb) {
      return;
    }
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
    } on UnsupportedError {
      // Zoom scale is unsupported on web video tracks.
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
    } on UnsupportedError {
      // Torch control is unsupported on web video tracks.
    }
  }

  Future<void> _switchCamera() async {
    final controller = _scannerController;
    if (controller == null) {
      return;
    }
    final scannerState = controller.value;
    if (!scannerState.isInitialized || !scannerState.isRunning) {
      return;
    }
    try {
      await controller.switchCamera();
    } on MobileScannerException catch (error) {
      debugPrint('Failed to switch camera: ${error.errorCode}');
    } on MissingPluginException {
      // No native scanner plugin on this platform.
    } on UnsupportedError {
      // Switching cameras is unsupported on this device/browser.
    }
  }

  static const Duration _beepTransitionLead = Duration(milliseconds: 55);

  void _triggerValidVinLock(String vin) {
    if (_isScanLocked || !mounted) {
      return;
    }
    // Lock synchronously before any async work to guarantee a single scan.
    _isScanLocked = true;
    _clearStatusMessage();
    unawaited(_handleConfirmedScan(vin));
  }

  Future<void> _handleConfirmedScan(String vin) async {
    // Start audible beep + haptic first so sound leads camera teardown and the
    // screen transition, while kicking off the VIN API lookup in parallel.
    final feedbackFuture = widget.feedbackService.playValidScanFeedback();
    unawaited(widget.vinController.lookupVin(vin));
    if (_captureMode == ScannerCaptureMode.barcode) {
      unawaited(_stopScanning());
    }
    try {
      await feedbackFuture;
    } catch (_) {
      // Never block navigation if audio/haptic playback fails.
    }
    await Future<void>.delayed(_beepTransitionLead);
    if (!mounted) {
      return;
    }
    await _openVehicleResultScreen(vin, startLookup: false);
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isScanLocked ||
        !mounted ||
        _captureMode != ScannerCaptureMode.barcode) {
      return;
    }

    String? normalFallbackCandidate;

    for (final barcode in capture.barcodes) {
      final candidate = widget.validator.extractFromBarcode(
            barcode.rawValue,
            strictness: _strictness,
          ) ??
          widget.validator.extractFromBarcode(
            barcode.displayValue,
            strictness: _strictness,
          );
      if (candidate != null) {
        _triggerValidVinLock(candidate);
        return;
      }

      if (_strictness == VinScanStrictness.strict &&
          normalFallbackCandidate == null) {
        normalFallbackCandidate = widget.validator.extractFromBarcode(
              barcode.rawValue,
              strictness: VinScanStrictness.normal,
            ) ??
            widget.validator.extractFromBarcode(
              barcode.displayValue,
              strictness: VinScanStrictness.normal,
            );
      }
    }

    if (normalFallbackCandidate != null) {
      final recoveredVin = normalFallbackCandidate;
      _showTransientStatus(
        'Extra barcode characters detected ($recoveredVin)',
        actionLabel: 'Use Normal',
        onAction: () {
          _setStrictness(VinScanStrictness.normal);
          _triggerValidVinLock(recoveredVin);
        },
        duration: const Duration(seconds: 4),
      );
      return;
    }

    if (capture.barcodes.isNotEmpty) {
      _showTransientStatus(
        _strictness == VinScanStrictness.strict
            ? 'Barcode is not an exact 17-character VIN'
            : 'Scanned barcode does not contain a valid VIN',
      );
    }
  }

  void _showTransientStatus(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 2),
  }) {
    final now = DateTime.now();
    if (actionLabel == null &&
        _lastInvalidBannerAt != null &&
        now.difference(_lastInvalidBannerAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastInvalidBannerAt = now;
    _statusTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _statusMessage = message;
      _statusActionLabel = actionLabel;
      _statusAction = onAction;
    });
    _statusTimer = Timer(duration, _clearStatusMessage);
  }

  void _clearStatusMessage() {
    _statusTimer?.cancel();
    _statusTimer = null;
    if (mounted && (_statusMessage != null || _statusActionLabel != null)) {
      setState(() {
        _statusMessage = null;
        _statusActionLabel = null;
        _statusAction = null;
      });
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
    if (_captureMode == ScannerCaptureMode.barcode) {
      unawaited(_stopScanning());
    }

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
    if (_captureMode == ScannerCaptureMode.barcode) {
      await _resumeCamera();
    }
  }

  Future<void> _openVehicleResultScreen(
    String vin, {
    bool startLookup = true,
  }) async {
    if (!mounted) {
      return;
    }
    setState(() => _isScanLocked = true);
    if (startLookup) {
      unawaited(widget.vinController.lookupVin(vin));
    }

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
    if (_captureMode == ScannerCaptureMode.barcode) {
      await _resumeCamera();
    }
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
        strictness: _strictness,
        onStrictnessChanged: _setStrictness,
        themeMode: widget.themeMode,
        onCycleThemeMode: widget.onCycleThemeMode,
        onSubmitVin: _triggerValidVinLock,
      );
    }

    final viewportSize = MediaQuery.sizeOf(context);
    final width = viewportSize.width;
    final height = viewportSize.height;
    final scanWidth = math.min(width * 0.88, 420.0);
    const scanHeight = 104.0;
    final scanCenterY = math.max(210.0, height * 0.40);
    final scanWindow = Rect.fromCenter(
      center: Offset(width / 2, scanCenterY),
      width: scanWidth,
      height: scanHeight,
    );

    final isOcrMode = _captureMode == ScannerCaptureMode.ocr;
    final strictnessCaption = _strictness == VinScanStrictness.normal
        ? 'Align VIN barcode (Normal • flexible)'
        : 'Align VIN barcode (Strict • exact 17-char)';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (isOcrMode)
            widget.ocrViewBuilder != null
                ? widget.ocrViewBuilder!(
                    context,
                    ocrService: _ocrService,
                    validator: widget.validator,
                    strictness: _strictness,
                    scanWindow: scanWindow,
                    isPaused: _isScanLocked,
                    onVinRecognized: _triggerValidVinLock,
                    onManualEntryTap: (initial) =>
                        unawaited(_openManualEntrySheet(initialVin: initial)),
                    onSwitchStrictnessToNormal: () =>
                        _setStrictness(VinScanStrictness.normal),
                  )
                : OcrCameraView(
                    ocrService: _ocrService,
                    validator: widget.validator,
                    strictness: _strictness,
                    scanWindow: scanWindow,
                    isPaused: _isScanLocked,
                    onVinRecognized: _triggerValidVinLock,
                    onManualEntryTap: (initial) =>
                        unawaited(_openManualEntrySheet(initialVin: initial)),
                    onSwitchStrictnessToNormal: () =>
                        _setStrictness(VinScanStrictness.normal),
                  )
          else
            // Keep MobileScanner outside ValueListenableBuilder/LayoutBuilder so
            // synchronous controller.start() notifications on web never dirty an
            // ancestor during layout/first-build.
            MobileScanner(
              controller: controller,
              // Scan window cropping is not supported on web; keep visual overlay.
              scanWindow: kIsWeb ? null : scanWindow,
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
              overlayBuilder: (_, _) =>
                  ValueListenableBuilder<MobileScannerState>(
                valueListenable: controller,
                builder: (context, scannerState, _) => ScannerOverlay(
                  scanWindow: scanWindow,
                  isPaused: _isScanLocked || !scannerState.isRunning,
                  promptText: strictnessCaption,
                  statusMessage: _statusMessage,
                  statusActionLabel: _statusActionLabel,
                  onStatusAction: _statusAction,
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: Image.asset(
                                    'assets/images/vinkit_icon.png',
                                    width: 22,
                                    height: 22,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Icon(
                                      isOcrMode
                                          ? Icons.document_scanner_rounded
                                          : Icons.qr_code_scanner_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'VinKit',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (!isOcrMode)
                              ValueListenableBuilder<MobileScannerState>(
                                valueListenable: controller,
                                builder: (context, scannerState, _) {
                                  final canSwitch = scannerState.isInitialized &&
                                      scannerState.isRunning &&
                                      scannerState.error == null;
                                  if (!canSwitch) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: IconButton.filledTonal(
                                      onPressed: () =>
                                          unawaited(_switchCamera()),
                                      tooltip: 'Switch camera',
                                      style: IconButton.styleFrom(
                                        backgroundColor:
                                            Colors.black.withValues(alpha: 0.66),
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: const Icon(
                                        Icons.cameraswitch_rounded,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            IconButton.filledTonal(
                              onPressed: widget.onCycleThemeMode,
                              tooltip: _themeTooltipFor(widget.themeMode),
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    Colors.black.withValues(alpha: 0.66),
                                foregroundColor: Colors.white,
                              ),
                              icon: Icon(_themeIconFor(widget.themeMode)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        if (_supportsOcr)
                          _HudSegmentedPill<ScannerCaptureMode>(
                            selected: _captureMode,
                            enabled: !_isSwitchingMode && !_isScanLocked,
                            options: const <
                                _HudSegmentOption<ScannerCaptureMode>>[
                              _HudSegmentOption<ScannerCaptureMode>(
                                value: ScannerCaptureMode.barcode,
                                label: 'Barcode',
                                icon: Icons.qr_code_scanner_rounded,
                              ),
                              _HudSegmentOption<ScannerCaptureMode>(
                                value: ScannerCaptureMode.ocr,
                                label: 'OCR',
                                icon: Icons.text_fields_rounded,
                              ),
                            ],
                            onChanged: (mode) =>
                                unawaited(_switchCaptureMode(mode)),
                          ),
                        _HudSegmentedPill<VinScanStrictness>(
                          selected: _strictness,
                          enabled: !_isScanLocked,
                          options: const <_HudSegmentOption<VinScanStrictness>>[
                            _HudSegmentOption<VinScanStrictness>(
                              value: VinScanStrictness.normal,
                              label: 'Normal',
                              icon: Icons.tune_rounded,
                            ),
                            _HudSegmentOption<VinScanStrictness>(
                              value: VinScanStrictness.strict,
                              label: 'Strict',
                              icon: Icons.verified_outlined,
                            ),
                          ],
                          onChanged: _setStrictness,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!isOcrMode)
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: controller,
              builder: (context, scannerState, _) {
                if (scannerState.error != null) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: ScannerControls(
                    zoomScale: _zoomScale,
                    torchState: scannerState.torchState,
                    isCameraRunning:
                        scannerState.isInitialized && scannerState.isRunning,
                    supportsZoom: !kIsWeb,
                    onZoomChanged: (value) => unawaited(_setZoomScale(value)),
                    onToggleTorch: () => unawaited(_toggleTorch()),
                    onManualEntryTap: () => unawaited(_openManualEntrySheet()),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _HudSegmentOption<T> {
  const _HudSegmentOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

class _HudSegmentedPill<T> extends StatelessWidget {
  const _HudSegmentedPill({
    required this.selected,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final T selected;
  final List<_HudSegmentOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            final isSelected = option.value == selected;
            return Material(
              color: isSelected ? colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: enabled ? () => onChanged(option.value) : null,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        option.icon,
                        size: 15,
                        color: isSelected
                            ? colorScheme.onPrimary
                            : Colors.white.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        option.label,
                        style: TextStyle(
                          color: isSelected
                              ? colorScheme.onPrimary
                              : Colors.white.withValues(alpha: 0.9),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}
