import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vinkit_app/screens/vehicle_result_screen.dart';
import 'package:vinkit_app/services/camera_permission_service.dart';
import 'package:vinkit_app/services/crash_reporting_service.dart';
import 'package:vinkit_app/services/ocr_image_preprocessor.dart';
import 'package:vinkit_app/services/scanner_feedback_service.dart';
import 'package:vinkit_app/services/vin_lookup_controller.dart';
import 'package:vinkit_app/services/vin_ocr_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';
import 'package:vinkit_app/widgets/camera_fallback_manual_view.dart';
import 'package:vinkit_app/widgets/camera_permission_view.dart';
import 'package:vinkit_app/widgets/desktop_vin_entry_view.dart';
import 'package:vinkit_app/widgets/manual_vin_sheet.dart';
import 'package:vinkit_app/widgets/ocr_camera_view.dart';
import 'package:vinkit_app/widgets/scanner_controls.dart';
import 'package:vinkit_app/widgets/scanner_overlay.dart';
import 'package:vinkit_app/widgets/settings_sheet.dart';

/// Active recognition target on [ScannerScreen].
enum ScannerCaptureMode {
  /// Automotive VIN barcode recognition (Code 39, Code 128, Code 93,
  /// DataMatrix, PDF417, QR).
  barcode,

  /// On-device plaintext VIN OCR powered by ONNX Runtime Mobile (PaddleOCR v5
  /// on Android) and Apple Vision (on iOS).
  ocr,
}

/// Active capture cadence on [ScannerScreen] for both Barcode and OCR modes.
enum ScannerTriggerMode {
  /// Continuously scans live camera frames hands-free.
  live,

  /// Captures a high-resolution snapshot on button tap (with EV/Gamma/HDR).
  snap,
}

/// Builder signature allowing tests to supply a lightweight camera view.
typedef OcrViewBuilder = Widget Function(
  BuildContext context, {
  required VinOcrService ocrService,
  required VinValidator validator,
  required VinScanStrictness strictness,
  required Rect scanWindow,
  required bool isPaused,
  required bool isBarcodeMode,
  required bool isContinuous,
  required ValueChanged<String> onVinRecognized,
  required ValueChanged<String?> onManualEntryTap,
  required VoidCallback onSwitchStrictnessToNormal,
});

/// Primary live camera VIN scanning screen supporting both Barcode and OCR
/// modes, each with Live (continuous) and Snap (photo capture) triggers,
/// Exposure/Gamma/HDR lighting controls, and Normal/Strict matching.
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
    this.onThemeModeChanged,
    this.feedbackService = const PlatformScannerFeedbackService(),
    this.ocrService,
    this.permissionService,
    this.crashReportingService,
    this.imagePreprocessor = const OcrImagePreprocessor(),
    this.deferCameraPermissionPrompt = false,
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

  /// Optional callback setting a specific [ThemeMode] directly from Settings.
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  /// Service playing audible beep and haptic confirmation on valid VIN scans.
  final ScannerFeedbackService feedbackService;

  /// Optional on-device OCR service override for tests or custom backends.
  final VinOcrService? ocrService;

  /// Optional runtime camera permission service override for tests.
  final CameraPermissionService? permissionService;

  /// Optional opt-in crash and diagnostic reporting service.
  final CrashReportingService? crashReportingService;

  /// Native image preprocessor and cache manager.
  final OcrImagePreprocessor imagePreprocessor;

  /// When `true` (e.g. while the startup splash animation is running), defers
  /// popping up the OS camera permission dialog until the splash finishes.
  /// Already-granted permissions still initialize immediately.
  final bool deferCameraPermissionPrompt;

  /// Initial VIN matching strictness (`Normal` by default).
  final VinScanStrictness initialStrictness;

  /// Optional platform capability override used by widget tests.
  final bool? cameraScannerSupportedOverride;

  /// Optional camera view builder override used by widget tests.
  final OcrViewBuilder? ocrViewBuilder;

  /// Barcode symbologies commonly used on automotive VIN stickers & labels.
  static const List<BarcodeFormat> vinBarcodeFormats = <BarcodeFormat>[
    BarcodeFormat.code39,
    BarcodeFormat.code128,
    BarcodeFormat.code93,
    BarcodeFormat.dataMatrix,
    BarcodeFormat.pdf417,
    BarcodeFormat.qrCode,
  ];

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
  late final CameraPermissionService _permissionService;
  late final CrashReportingService _crashReportingService;
  late final bool _ownsCrashReportingService;
  final ValueNotifier<int> _switchCameraSignal = ValueNotifier<int>(0);
  final ValueNotifier<int> _resetScannerSignal = ValueNotifier<int>(0);

  ScannerCaptureMode _captureMode = ScannerCaptureMode.barcode;
  ScannerTriggerMode _barcodeTriggerMode = ScannerTriggerMode.live;
  ScannerTriggerMode _ocrTriggerMode = ScannerTriggerMode.snap;
  late VinScanStrictness _strictness;
  bool _isSwitchingCameraBackend = false;

  late CameraPermissionState _cameraPermissionState;
  bool _hasPromptedCameraPermission = false;
  bool _isCameraHardwareAvailable = true;

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

  bool get _isCameraGranted =>
      _cameraPermissionState == CameraPermissionState.granted;

  bool get _canUseCameraFeatures =>
      _isCameraGranted && _isCameraHardwareAvailable;

  /// Whether the platform supports Snap capture mode and unified EV/Gamma/HDR
  /// camera controls (Android and iOS).
  bool get _supportsSnapAndLighting =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          widget.ocrViewBuilder != null);

  /// Active trigger mode (`Live` or `Snap`) for the currently selected mode.
  ScannerTriggerMode get _activeTriggerMode =>
      _captureMode == ScannerCaptureMode.barcode
          ? _barcodeTriggerMode
          : _ocrTriggerMode;

  /// On Android, use the unified [OcrCameraView] across all 4 combinations
  /// (`Barcode Live/Snap`, `OCR Live/Snap`) so Exposure/Gamma/HDR work
  /// everywhere and mode switching is instantaneous with zero camera reopen.
  /// On iOS, use [OcrCameraView] for OCR (Live/Snap) and Barcode Snap, keeping
  /// [MobileScanner] for Barcode Live.
  bool get _usesUnifiedCameraView {
    if (!_supportsSnapAndLighting) {
      return false;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return true;
    }
    return _captureMode == ScannerCaptureMode.ocr ||
        _activeTriggerMode == ScannerTriggerMode.snap;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _strictness = widget.initialStrictness;
    _ocrService = widget.ocrService ?? createPlatformVinOcrService();
    _permissionService =
        widget.permissionService ?? const PlatformCameraPermissionService();
    _ownsCrashReportingService = widget.crashReportingService == null;
    _crashReportingService =
        widget.crashReportingService ?? CrashReportingService();

    final skipInitialPermissionGate =
        kIsWeb ||
        (widget.ocrViewBuilder != null && widget.permissionService == null);
    _cameraPermissionState = skipInitialPermissionGate
        ? CameraPermissionState.granted
        : CameraPermissionState.checking;

    if (_supportsCameraScanner) {
      _scannerController = MobileScannerController(
        autoStart: kIsWeb && !_usesUnifiedCameraView,
        formats: ScannerScreen.vinBarcodeFormats,
        detectionSpeed: DetectionSpeed.normal,
      );
      if (!skipInitialPermissionGate) {
        unawaited(_initializeCameraPermission());
      }
    }
  }

  @override
  void didUpdateWidget(covariant ScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deferCameraPermissionPrompt &&
        !widget.deferCameraPermissionPrompt &&
        _supportsCameraScanner &&
        _cameraPermissionState == CameraPermissionState.checking &&
        !_hasPromptedCameraPermission) {
      unawaited(_requestCameraPermission());
    }
  }

  Future<void> _initializeCameraPermission() async {
    final status = await _permissionService.checkStatus();
    if (!mounted) {
      return;
    }
    if (status == CameraPermissionState.granted) {
      setState(() {
        _cameraPermissionState = CameraPermissionState.granted;
        _isCameraHardwareAvailable = true;
      });
      if (!_usesUnifiedCameraView && !_isScanLocked) {
        unawaited(_resumeCamera());
      }
      return;
    }
    if (status == CameraPermissionState.denied &&
        !_hasPromptedCameraPermission) {
      if (widget.deferCameraPermissionPrompt) {
        // Stay calmly in checking/waiting state until startup splash finishes,
        // then didUpdateWidget triggers the OS prompt cleanly.
        return;
      }
      await _requestCameraPermission();
      return;
    }
    setState(() => _cameraPermissionState = status);
  }

  Future<void> _requestCameraPermission() async {
    if (_cameraPermissionState == CameraPermissionState.requesting ||
        !mounted) {
      return;
    }
    _hasPromptedCameraPermission = true;
    setState(() => _cameraPermissionState = CameraPermissionState.requesting);

    final result = await _permissionService.requestPermission();
    if (!mounted) {
      return;
    }
    setState(() {
      _cameraPermissionState = result;
      if (result == CameraPermissionState.granted) {
        _isCameraHardwareAvailable = true;
      }
    });
    if (result == CameraPermissionState.granted &&
        !_usesUnifiedCameraView &&
        !_isScanLocked) {
      unawaited(_resumeCamera());
    }
  }

  Future<void> _recheckCameraPermissionOnResume() async {
    if (_cameraPermissionState == CameraPermissionState.requesting ||
        !_supportsCameraScanner) {
      return;
    }
    final status = await _permissionService.checkStatus();
    if (!mounted ||
        _cameraPermissionState == CameraPermissionState.requesting) {
      return;
    }
    if (status == CameraPermissionState.granted &&
        _cameraPermissionState != CameraPermissionState.granted) {
      setState(() {
        _cameraPermissionState = CameraPermissionState.granted;
        _isCameraHardwareAvailable = true;
      });
      if (!_usesUnifiedCameraView && !_isScanLocked) {
        unawaited(_resumeCamera());
      }
    } else if (status != CameraPermissionState.granted &&
        _cameraPermissionState == CameraPermissionState.granted) {
      unawaited(_stopScanning());
      setState(() => _cameraPermissionState = status);
    }
  }

  Future<void> _openCameraSettings() async {
    await _permissionService.openSettings();
  }

  void _showCameraDisabledHint() {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger.hideCurrentSnackBar();

    final isHardwareIssue = _isCameraGranted && !_isCameraHardwareAvailable;
    final String message;
    final SnackBarAction? action;

    if (isHardwareIssue) {
      message = 'Camera is currently unavailable. Tap Retry Camera or enter a VIN below.';
      action = null;
    } else if (_cameraPermissionState == CameraPermissionState.checking ||
        _cameraPermissionState == CameraPermissionState.requesting) {
      message = 'Allow camera access to enable barcode & OCR scanning.';
      action = null;
    } else if (_cameraPermissionState == CameraPermissionState.denied) {
      message = 'Allow camera access to enable barcode & OCR scanning.';
      action = SnackBarAction(
        label: 'Allow',
        onPressed: () => unawaited(_requestCameraPermission()),
      );
    } else {
      message = 'Allow camera access in Settings to enable scanning.';
      action = SnackBarAction(
        label: 'Settings',
        onPressed: () => unawaited(_openCameraSettings()),
      );
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_recheckCameraPermissionOnResume());
    }
    if (_scannerController == null ||
        _usesUnifiedCameraView ||
        !_isCameraGranted) {
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
        _usesUnifiedCameraView ||
        !_isCameraGranted) {
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
          !_usesUnifiedCameraView &&
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

  Future<BarcodeCapture?> _analyzeBarcodeImage(String imagePath) async {
    final controller = _scannerController;
    if (controller == null) {
      return null;
    }
    try {
      return await controller.analyzeImage(
        imagePath,
        formats: ScannerScreen.vinBarcodeFormats,
      );
    } on MobileScannerException catch (error) {
      debugPrint('Failed to analyze barcode image: ${error.errorCode}');
      return null;
    } on MissingPluginException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  Future<void> _applyModeTransition(VoidCallback mutateMode) async {
    if (_isSwitchingCameraBackend || _isScanLocked) {
      return;
    }
    final wasUnified = _usesUnifiedCameraView;
    _clearStatusMessage();

    // Peek at whether the camera backend actually changes (e.g., iOS switching
    // between MobileScanner and CameraController; on Android it stays unified).
    setState(() {
      _isSwitchingCameraBackend = true;
    });

    var willBeUnified = wasUnified;
    if (!wasUnified) {
      await _stopScanning();
      if (!mounted) {
        return;
      }
    }

    setState(() {
      mutateMode();
      willBeUnified = _usesUnifiedCameraView;
    });

    if (wasUnified && !willBeUnified) {
      // Allow CameraController to finish disposing before starting MobileScanner.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) {
        return;
      }
      await _resumeCamera();
    }

    if (mounted) {
      setState(() => _isSwitchingCameraBackend = false);
    }
  }

  Future<void> _switchCaptureMode(ScannerCaptureMode targetMode) async {
    if (_captureMode == targetMode) {
      return;
    }
    if (targetMode == ScannerCaptureMode.ocr && !_supportsOcr) {
      return;
    }
    await _applyModeTransition(() {
      _captureMode = targetMode;
    });
  }

  Future<void> _switchTriggerMode(ScannerTriggerMode targetTrigger) async {
    if (_activeTriggerMode == targetTrigger || !_supportsSnapAndLighting) {
      return;
    }
    await _applyModeTransition(() {
      if (_captureMode == ScannerCaptureMode.barcode) {
        _barcodeTriggerMode = targetTrigger;
      } else {
        _ocrTriggerMode = targetTrigger;
      }
    });
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
    if (_usesUnifiedCameraView) {
      _switchCameraSignal.value++;
      return;
    }
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
    if (!_usesUnifiedCameraView) {
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
    if (_isScanLocked || !mounted || _usesUnifiedCameraView) {
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
    if (!_usesUnifiedCameraView) {
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
    if (!_usesUnifiedCameraView) {
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
      if (_supportsCameraScanner && _canUseCameraFeatures) {
        await _openManualEntrySheet(initialVin: vin, alreadyLocked: true);
        return;
      }
      setState(() => _isScanLocked = false);
      return;
    }

    setState(() => _isScanLocked = false);
    if (!_usesUnifiedCameraView && _isCameraGranted) {
      await _resumeCamera();
    }
  }

  Map<String, String> _buildScannerDiagnostics() {
    return <String, String>{
      'theme_mode': widget.themeMode.name,
      'capture_mode': _captureMode.name,
      'trigger_mode': _activeTriggerMode.name,
      'strictness': _strictness.name,
      'camera_permission': _cameraPermissionState.name,
      'camera_hardware_available': _isCameraHardwareAvailable.toString(),
      'uses_unified_camera': _usesUnifiedCameraView.toString(),
      'lookup_state': widget.vinController.state.runtimeType.toString(),
    };
  }

  Future<int> _resetScannerStateAndCache() async {
    _clearStatusMessage();
    widget.vinController.reset();
    if (mounted) {
      setState(() {
        _captureMode = ScannerCaptureMode.barcode;
        _barcodeTriggerMode = ScannerTriggerMode.live;
        _ocrTriggerMode = ScannerTriggerMode.snap;
        _strictness = VinScanStrictness.normal;
        _zoomScale = 0.0;
      });
    }
    _resetScannerSignal.value++;
    unawaited(_setZoomScale(0.0));
    final removedFiles = await widget.imagePreprocessor.clearTempImageCache();
    unawaited(
      _crashReportingService.logBreadcrumb(
        'Reset scanner state and cleared $removedFiles temp cache files',
      ),
    );
    return removedFiles;
  }

  Future<bool> _resetOcrModelCache() async {
    final cleared = await widget.imagePreprocessor.clearOcrModelCache();
    _resetScannerSignal.value++;
    unawaited(
      _crashReportingService.logBreadcrumb(
        'Cleared on-device OCR model cache (cleared=$cleared)',
      ),
    );
    return cleared;
  }

  Future<CameraPermissionState> _recheckPermissionFromSettings() async {
    final status = await _permissionService.checkStatus();
    if (mounted) {
      setState(() {
        _cameraPermissionState = status;
        if (status == CameraPermissionState.granted) {
          _isCameraHardwareAvailable = true;
        }
      });
    }
    return status;
  }

  Future<CameraPermissionState> _requestPermissionFromSettings() async {
    await _requestCameraPermission();
    return _cameraPermissionState;
  }

  Future<void> _openSettingsSheet() async {
    if (_isScanLocked || !mounted) {
      return;
    }
    setState(() => _isScanLocked = true);
    if (!_usesUnifiedCameraView) {
      unawaited(_stopScanning());
    }

    unawaited(
      _crashReportingService.updateDiagnosticsContext(_buildScannerDiagnostics()),
    );

    final supportsNativePerms = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final supportsAndroidOcrCache =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SettingsSheet(
        crashReportingService: _crashReportingService,
        themeMode: widget.themeMode,
        onThemeModeChanged: (mode) {
          if (widget.onThemeModeChanged != null) {
            widget.onThemeModeChanged!(mode);
          } else {
            widget.onCycleThemeMode();
          }
        },
        strictness: _strictness,
        onStrictnessChanged: _setStrictness,
        onResetStateAndCache: _resetScannerStateAndCache,
        cameraPermissionState:
            _supportsCameraScanner ? _cameraPermissionState : null,
        supportsNativePermissions: supportsNativePerms,
        onRequestCameraPermission:
            _supportsCameraScanner ? _requestPermissionFromSettings : null,
        onOpenSystemSettings:
            supportsNativePerms ? _permissionService.openSettings : null,
        onRecheckPermissions:
            _supportsCameraScanner ? _recheckPermissionFromSettings : null,
        onResetOcrModelCache:
            supportsAndroidOcrCache ? _resetOcrModelCache : null,
        extraDiagnostics: _buildScannerDiagnostics(),
        initialFeedbackVin: widget.vinController.lastVin,
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() => _isScanLocked = false);
    if (!_usesUnifiedCameraView && _isCameraGranted) {
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
    _switchCameraSignal.dispose();
    _resetScannerSignal.dispose();
    if (_ownsCrashReportingService) {
      _crashReportingService.dispose();
    }
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
        onOpenSettings: () => unawaited(_openSettingsSheet()),
        onSubmitVin: _triggerValidVinLock,
      );
    }

    final viewportSize = MediaQuery.sizeOf(context);
    final width = viewportSize.width;
    final height = viewportSize.height;
    final scanWidth = math.min(width * 0.88, 420.0);
    const scanHeight = 104.0;
    final scanCenterY = math.max(220.0, height * 0.41);
    final scanWindow = Rect.fromCenter(
      center: Offset(width / 2, scanCenterY),
      width: scanWidth,
      height: scanHeight,
    );

    final isBarcodeMode = _captureMode == ScannerCaptureMode.barcode;
    final isContinuous = _activeTriggerMode == ScannerTriggerMode.live;
    final useUnified = _usesUnifiedCameraView;
    final cameraGranted = _isCameraGranted;
    final cameraEnabled = _canUseCameraFeatures;
    final strictnessCaption = _strictness == VinScanStrictness.normal
        ? 'Align VIN barcode (Normal • flexible)'
        : 'Align VIN barcode (Strict • exact 17-char)';
    final cameraDisabledTooltip =
        _cameraPermissionState == CameraPermissionState.permanentlyDenied
            ? 'Allow camera access in Settings to enable scanning'
            : 'Allow camera access to enable scanning';

    return Scaffold(
      backgroundColor:
          cameraGranted ? Colors.black : Theme.of(context).colorScheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (!cameraGranted)
            CameraFallbackManualView(
              validator: widget.validator,
              strictness: _strictness,
              permissionState: _cameraPermissionState,
              onSubmitVin: _triggerValidVinLock,
              onRequestPermission: () => unawaited(_requestCameraPermission()),
              onOpenSettings: () => unawaited(_openCameraSettings()),
            )
          else if (useUnified)
            widget.ocrViewBuilder != null
                ? widget.ocrViewBuilder!(
                    context,
                    ocrService: _ocrService,
                    validator: widget.validator,
                    strictness: _strictness,
                    scanWindow: scanWindow,
                    isPaused: _isScanLocked,
                    isBarcodeMode: isBarcodeMode,
                    isContinuous: isContinuous,
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
                    isBarcodeMode: isBarcodeMode,
                    isContinuous: isContinuous,
                    onAnalyzeBarcodeImage: _analyzeBarcodeImage,
                    switchCameraSignal: _switchCameraSignal,
                    resetSignal: _resetScannerSignal,
                    preprocessor: widget.imagePreprocessor,
                    onVinRecognized: _triggerValidVinLock,
                    onManualEntryTap: (initial) =>
                        unawaited(_openManualEntrySheet(initialVin: initial)),
                    onSwitchStrictnessToNormal: () =>
                        _setStrictness(VinScanStrictness.normal),
                    onCameraAvailabilityChanged: (available) {
                      if (mounted && _isCameraHardwareAvailable != available) {
                        setState(() => _isCameraHardwareAvailable = available);
                      }
                    },
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
                topPadding: 120,
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
                                      isBarcodeMode
                                          ? Icons.qr_code_scanner_rounded
                                          : Icons.document_scanner_rounded,
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
                            if (useUnified)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Tooltip(
                                  message: cameraEnabled
                                      ? 'Switch camera'
                                      : cameraDisabledTooltip,
                                  child: Opacity(
                                    opacity: cameraEnabled ? 1.0 : 0.42,
                                    child: IconButton.filledTonal(
                                      onPressed: cameraEnabled
                                          ? () => unawaited(_switchCamera())
                                          : _showCameraDisabledHint,
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.black
                                            .withValues(alpha: 0.66),
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: const Icon(
                                        Icons.cameraswitch_rounded,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else if (cameraGranted)
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
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              key: const Key('open_settings_button'),
                              onPressed: () => unawaited(_openSettingsSheet()),
                              tooltip: 'Settings & Diagnostics',
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    Colors.black.withValues(alpha: 0.66),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.settings_outlined),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        if (_supportsOcr)
                          _HudSegmentedPill<ScannerCaptureMode>(
                            selected: _captureMode,
                            enabled: cameraEnabled &&
                                !_isSwitchingCameraBackend &&
                                !_isScanLocked,
                            isMuted: !cameraEnabled,
                            disabledTooltip: cameraDisabledTooltip,
                            onDisabledTap: _showCameraDisabledHint,
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
                        if (_supportsSnapAndLighting)
                          _HudSegmentedPill<ScannerTriggerMode>(
                            selected: _activeTriggerMode,
                            enabled: cameraEnabled &&
                                !_isSwitchingCameraBackend &&
                                !_isScanLocked,
                            isMuted: !cameraEnabled,
                            disabledTooltip: cameraDisabledTooltip,
                            onDisabledTap: _showCameraDisabledHint,
                            options: const <
                                _HudSegmentOption<ScannerTriggerMode>>[
                              _HudSegmentOption<ScannerTriggerMode>(
                                value: ScannerTriggerMode.live,
                                label: 'Live',
                                icon: Icons.sensors_rounded,
                              ),
                              _HudSegmentOption<ScannerTriggerMode>(
                                value: ScannerTriggerMode.snap,
                                label: 'Snap',
                                icon: Icons.camera_alt_rounded,
                              ),
                            ],
                            onChanged: (trigger) =>
                                unawaited(_switchTriggerMode(trigger)),
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
          if (cameraGranted && !useUnified)
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
    this.isMuted = false,
    this.disabledTooltip,
    this.onDisabledTap,
  });

  final T selected;
  final List<_HudSegmentOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final bool isMuted;
  final String? disabledTooltip;
  final VoidCallback? onDisabledTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final pill = Opacity(
      opacity: isMuted ? 0.44 : 1.0,
      child: DecoratedBox(
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
              final selectedBg = isMuted
                  ? Colors.white.withValues(alpha: 0.22)
                  : colorScheme.primary;
              final selectedFg = isMuted ? Colors.white70 : colorScheme.onPrimary;
              return Material(
                color: isSelected ? selectedBg : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: enabled
                      ? () => onChanged(option.value)
                      : (isMuted ? onDisabledTap : null),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          option.icon,
                          size: 14,
                          color: isSelected
                              ? selectedFg
                              : Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          option.label,
                          style: TextStyle(
                            color: isSelected
                                ? selectedFg
                                : Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
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
      ),
    );

    if (isMuted && disabledTooltip != null) {
      return Tooltip(
        message: disabledTooltip!,
        child: pill,
      );
    }
    return pill;
  }
}
