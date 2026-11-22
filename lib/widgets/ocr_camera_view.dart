import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart'
    show BarcodeCapture, TorchState;
import 'package:permission_handler/permission_handler.dart';
import 'package:vinkit_app/services/ocr_image_preprocessor.dart';
import 'package:vinkit_app/services/vin_ocr_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';
import 'package:vinkit_app/widgets/scanner_controls.dart';
import 'package:vinkit_app/widgets/scanner_overlay.dart';

/// Unified live/snap mobile camera view supporting both VIN barcode decoding
/// and on-device plaintext VIN OCR with real-time Exposure (EV), Gamma, and
/// HDR local-contrast controls.
class OcrCameraView extends StatefulWidget {
  /// Creates an [OcrCameraView].
  const OcrCameraView({
    super.key,
    required this.ocrService,
    required this.validator,
    required this.strictness,
    required this.scanWindow,
    required this.isPaused,
    required this.onVinRecognized,
    required this.onManualEntryTap,
    this.isBarcodeMode = false,
    this.isContinuous = false,
    this.onAnalyzeBarcodeImage,
    this.switchCameraSignal,
    this.onSwitchStrictnessToNormal,
    this.preprocessor = const OcrImagePreprocessor(),
  });

  /// On-device OCR engine (PaddleOCR v5 ONNX Runtime / Apple Vision).
  final VinOcrService ocrService;

  /// VIN validator and OCR/barcode text extractor.
  final VinValidator validator;

  /// Active VIN matching strictness mode.
  final VinScanStrictness strictness;

  /// Alignment frame rectangle matching the scanner viewfinder.
  final Rect scanWindow;

  /// Whether camera interaction is temporarily paused (e.g. result screen open).
  final bool isPaused;

  /// Whether the active recognition target is barcode (`true`) or OCR (`false`).
  final bool isBarcodeMode;

  /// Whether to continuously scan frames (`true`) or capture on button tap (`false`).
  final bool isContinuous;

  /// Analyzes a prepared image file for automotive VIN barcodes.
  final Future<BarcodeCapture?> Function(String imagePath)? onAnalyzeBarcodeImage;

  /// Optional monotonic counter incremented when the parent requests switching cameras.
  final ValueListenable<int>? switchCameraSignal;

  /// Called immediately when barcode or OCR recognizes a valid 17-character VIN.
  final ValueChanged<String> onVinRecognized;

  /// Called when the user opens manual VIN entry, optionally prefilled with a
  /// partial OCR snippet.
  final ValueChanged<String?> onManualEntryTap;

  /// Optional shortcut to switch strictness from Strict to Normal when a
  /// candidate only matches under Normal mode.
  final VoidCallback? onSwitchStrictnessToNormal;

  /// Native image preprocessor cropping to the viewfinder ROI and applying
  /// user-selected HDR & gamma enhancement before recognition.
  final OcrImagePreprocessor preprocessor;

  @override
  State<OcrCameraView> createState() => _OcrCameraViewState();
}

class _OcrCameraViewState extends State<OcrCameraView>
    with WidgetsBindingObserver {
  static const Duration _liveBarcodeCooldown = Duration(milliseconds: 180);
  static const Duration _liveOcrCooldown = Duration(milliseconds: 750);
  static const Duration _fallbackCaptureInterval = Duration(milliseconds: 1100);

  CameraController? _cameraController;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  int _selectedCameraIndex = 0;
  int _cameraGeneration = 0;

  bool _isInitializingCamera = true;
  bool _isSwitchingCamera = false;
  String? _cameraError;
  bool _isPermissionDenied = false;

  bool _isModelReady = false;
  bool _isPreparingModels = false;
  String? _modelError;

  bool _isProcessingFrame = false;
  bool _isStreamActive = false;
  DateTime? _lastFrameFinishedAt;
  Timer? _fallbackContinuousTimer;
  Timer? _transientStatusTimer;

  double _zoomScale = 0.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  bool _isTorchOn = false;

  bool _supportsExposureOffset = false;
  double _minExposureOffset = -2.0;
  double _maxExposureOffset = 2.0;
  double _exposureStepSize = 0.0;
  double _exposureOffset = 0.0;
  double _gamma = 1.0;
  bool _hdrEnabled = false;
  bool _isLightingPanelExpanded = false;

  Size? _lastViewportSize;

  String? _statusMessage;
  bool _statusIsError = false;
  String? _statusActionLabel;
  VoidCallback? _statusAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.switchCameraSignal?.addListener(_onSwitchCameraRequested);
    unawaited(_initializeCamera());
    if (!widget.isBarcodeMode) {
      unawaited(_ensureModelsReady());
    }
  }

  @override
  void didUpdateWidget(covariant OcrCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.switchCameraSignal != widget.switchCameraSignal) {
      oldWidget.switchCameraSignal?.removeListener(_onSwitchCameraRequested);
      widget.switchCameraSignal?.addListener(_onSwitchCameraRequested);
    }

    if (oldWidget.isBarcodeMode != widget.isBarcodeMode ||
        oldWidget.isContinuous != widget.isContinuous ||
        oldWidget.strictness != widget.strictness) {
      _clearStatusMessage();
      if (!widget.isBarcodeMode && !_isModelReady) {
        unawaited(_ensureModelsReady());
      }
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (oldWidget.isPaused != widget.isPaused) {
      if (widget.isPaused) {
        unawaited(_stopContinuousCapture(controller));
        if (!_isProcessingFrame) {
          unawaited(_pausePreviewSafely(controller));
        }
      } else {
        unawaited(_resumeAfterPause(controller));
      }
      return;
    }

    if (oldWidget.isContinuous != widget.isContinuous ||
        oldWidget.isBarcodeMode != widget.isBarcodeMode) {
      unawaited(_syncContinuousCapture(controller));
    }
  }

  Future<void> _resumeAfterPause(CameraController controller) async {
    await _resumePreviewSafely(controller);
    if (!mounted || _cameraController != controller || widget.isPaused) {
      return;
    }
    await _syncContinuousCapture(controller);
  }

  void _onSwitchCameraRequested() {
    if (_cameras.length < 2 || _isSwitchingCamera || _isInitializingCamera) {
      return;
    }
    _isSwitchingCamera = true;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    unawaited(
      _initializeCamera().whenComplete(() {
        _isSwitchingCamera = false;
      }),
    );
  }

  Future<void> _pausePreviewSafely(CameraController controller) async {
    if (_cameraController != controller || !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.pausePreview();
    } catch (_) {
      // Ignore pause errors on platforms that do not support pausePreview.
    }
  }

  Future<void> _resumePreviewSafely(CameraController controller) async {
    if (_cameraController != controller || !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.resumePreview();
    } catch (_) {
      // Ignore resume errors on platforms that do not support resumePreview.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_cameraController != null) {
        unawaited(_disposeCamera());
      }
    } else if (state == AppLifecycleState.resumed &&
        !widget.isPaused &&
        _cameraController == null) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _ensureModelsReady() async {
    if (!widget.ocrService.isSupported || _isPreparingModels || _isModelReady) {
      return;
    }
    final alreadyReady = await widget.ocrService.isModelReady();
    if (!mounted) {
      return;
    }
    if (alreadyReady) {
      setState(() {
        _isModelReady = true;
        _modelError = null;
      });
      final controller = _cameraController;
      if (controller != null && controller.value.isInitialized) {
        unawaited(_syncContinuousCapture(controller));
      }
      return;
    }

    setState(() {
      _isPreparingModels = true;
      _modelError = null;
      _statusMessage = 'Preparing PaddleOCR v5 ONNX models (~20 MB)...';
      _statusIsError = false;
      _statusActionLabel = null;
      _statusAction = null;
    });

    try {
      await widget.ocrService.prepareModels();
      if (!mounted) {
        return;
      }
      setState(() {
        _isModelReady = true;
        _isPreparingModels = false;
        _modelError = null;
        if (_statusMessage?.startsWith('Preparing PaddleOCR') ?? false) {
          _statusMessage = null;
        }
      });
      final controller = _cameraController;
      if (controller != null && controller.value.isInitialized) {
        unawaited(_syncContinuousCapture(controller));
      }
    } on VinOcrException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparingModels = false;
        _modelError = error.message;
        _statusMessage = error.message;
        _statusIsError = true;
        _statusActionLabel = 'Retry';
        _statusAction = () => unawaited(_ensureModelsReady());
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparingModels = false;
        _modelError = 'Failed to prepare on-device OCR models.';
        _statusMessage = _modelError;
        _statusIsError = true;
        _statusActionLabel = 'Retry';
        _statusAction = () => unawaited(_ensureModelsReady());
      });
    }
  }

  Future<void> _initializeCamera() async {
    if (!mounted) {
      return;
    }
    final generation = ++_cameraGeneration;
    setState(() {
      _isInitializingCamera = true;
      _cameraError = null;
      _isPermissionDenied = false;
    });

    await _disposeCamera(bumpGeneration: false);
    if (!mounted || generation != _cameraGeneration) {
      return;
    }

    try {
      final cameras = await availableCameras();
      if (!mounted || generation != _cameraGeneration) {
        return;
      }
      if (cameras.isEmpty) {
        setState(() {
          _isInitializingCamera = false;
          _cameraError = 'No camera was detected on this device.';
        });
        return;
      }

      final hadCameras = _cameras.isNotEmpty;
      _cameras = cameras;
      if (_selectedCameraIndex >= _cameras.length) {
        _selectedCameraIndex = 0;
      }
      if (!hadCameras && _selectedCameraIndex == 0) {
        final backIndex = _cameras.indexWhere(
          (cam) => cam.lensDirection == CameraLensDirection.back,
        );
        if (backIndex >= 0) {
          _selectedCameraIndex = backIndex;
        }
      }

      final formatGroup = defaultTargetPlatform == TargetPlatform.iOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420;
      final controller = CameraController(
        _cameras[_selectedCameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: formatGroup,
      );

      await controller.initialize();
      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }

      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {
        // Focus mode selection may not be supported on all cameras.
      }
      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {
        // Exposure mode selection may not be supported on all cameras.
      }

      double minZoom = 1.0;
      double maxZoom = 1.0;
      try {
        minZoom = await controller.getMinZoomLevel();
        maxZoom = await controller.getMaxZoomLevel();
      } catch (_) {
        // Leave default 1.0..1.0 if zoom query fails.
      }

      var supportsExposure = false;
      var minEv = -2.0;
      var maxEv = 2.0;
      var evStep = 0.0;
      try {
        final rawMinEv = await controller.getMinExposureOffset();
        final rawMaxEv = await controller.getMaxExposureOffset();
        final rawStep = await controller.getExposureOffsetStepSize();
        if (rawMinEv.isFinite &&
            rawMaxEv.isFinite &&
            rawMaxEv > rawMinEv + 0.05) {
          final clampedMin = rawMinEv.clamp(-4.0, 0.0);
          final clampedMax = rawMaxEv.clamp(0.0, 4.0);
          if (clampedMax > clampedMin + 0.05) {
            supportsExposure = true;
            minEv = clampedMin;
            maxEv = clampedMax;
            evStep = rawStep.isFinite && rawStep > 0.0 ? rawStep : 0.0;
          }
        }
      } catch (_) {
        // Exposure offset queries may not be supported on all cameras.
      }

      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }

      final restoredEv = supportsExposure
          ? _exposureOffset.clamp(minEv, maxEv)
          : 0.0;
      if (supportsExposure && restoredEv.abs() >= 0.05) {
        try {
          await controller.setExposureOffset(restoredEv);
        } catch (_) {
          // Ignore if restoring exposure offset fails.
        }
      }

      setState(() {
        _cameraController = controller;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _zoomScale = 0.0;
        _isTorchOn = false;
        _supportsExposureOffset = supportsExposure;
        _minExposureOffset = minEv;
        _maxExposureOffset = maxEv;
        _exposureStepSize = evStep;
        _exposureOffset = restoredEv;
        _isInitializingCamera = false;
      });

      if (!widget.isPaused) {
        await _syncContinuousCapture(controller);
      }
    } on CameraException catch (error) {
      if (!mounted || generation != _cameraGeneration) {
        return;
      }
      final denied = error.code.toLowerCase().contains('access') ||
          error.code.toLowerCase().contains('permission');
      setState(() {
        _isInitializingCamera = false;
        _isPermissionDenied = denied;
        _cameraError = denied
            ? 'Camera permission is required to scan VIN barcodes and printed text.'
            : (error.description ?? 'Unable to start camera preview.');
      });
    } catch (_) {
      if (!mounted || generation != _cameraGeneration) {
        return;
      }
      setState(() {
        _isInitializingCamera = false;
        _cameraError = 'Unable to start camera preview.';
      });
    }
  }

  Future<void> _disposeCamera({bool bumpGeneration = true}) async {
    if (bumpGeneration) {
      _cameraGeneration++;
    }
    _fallbackContinuousTimer?.cancel();
    _fallbackContinuousTimer = null;

    final controller = _cameraController;
    _cameraController = null;
    _isStreamActive = false;
    if (controller == null) {
      return;
    }
    try {
      if (controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Ignore stream teardown errors.
    }
    try {
      if (_isTorchOn && controller.value.isInitialized) {
        await controller.setFlashMode(FlashMode.off);
      }
    } catch (_) {
      // Ignore torch teardown errors.
    }
    try {
      await controller.dispose();
    } catch (_) {
      // Ignore camera disposal errors.
    }
  }

  Future<void> _syncContinuousCapture(CameraController controller) async {
    if (!mounted || _cameraController != controller) {
      return;
    }
    final shouldStream = widget.isContinuous &&
        !widget.isPaused &&
        controller.value.isInitialized &&
        (widget.isBarcodeMode || _isModelReady);

    if (!shouldStream) {
      await _stopContinuousCapture(controller);
      return;
    }

    if (widget.preprocessor.supportsStreamFramePrep) {
      _fallbackContinuousTimer?.cancel();
      _fallbackContinuousTimer = null;
      if (_isStreamActive || controller.value.isStreamingImages) {
        return;
      }
      try {
        _isStreamActive = true;
        await controller.startImageStream(_onLiveCameraFrame);
      } catch (_) {
        _isStreamActive = false;
        _startFallbackContinuousTimer();
      }
    } else {
      _startFallbackContinuousTimer();
    }
  }

  Future<void> _stopContinuousCapture(CameraController controller) async {
    _fallbackContinuousTimer?.cancel();
    _fallbackContinuousTimer = null;
    if (!_isStreamActive && !controller.value.isStreamingImages) {
      return;
    }
    _isStreamActive = false;
    try {
      if (controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Ignore errors stopping an already-stopped image stream.
    }
  }

  void _startFallbackContinuousTimer() {
    if (_fallbackContinuousTimer != null) {
      return;
    }
    _fallbackContinuousTimer = Timer.periodic(_fallbackCaptureInterval, (_) {
      if (!mounted ||
          !widget.isContinuous ||
          widget.isPaused ||
          _isProcessingFrame) {
        return;
      }
      unawaited(_captureAndAnalyzePhoto(isFromContinuousFallback: true));
    });
  }

  int _computeSensorRotationDegrees(CameraController controller) {
    final description = controller.description;
    final sensorOrientation = description.sensorOrientation;
    final deviceDegrees = switch (controller.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    if (description.lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + deviceDegrees) % 360;
    }
    return (sensorOrientation - deviceDegrees + 360) % 360;
  }

  void _onLiveCameraFrame(CameraImage image) {
    if (!mounted ||
        !widget.isContinuous ||
        widget.isPaused ||
        _isProcessingFrame ||
        _isInitializingCamera ||
        _isSwitchingCamera) {
      return;
    }
    if (!widget.isBarcodeMode && !_isModelReady) {
      return;
    }

    final cooldown =
        widget.isBarcodeMode ? _liveBarcodeCooldown : _liveOcrCooldown;
    final lastFinished = _lastFrameFinishedAt;
    if (lastFinished != null &&
        DateTime.now().difference(lastFinished) < cooldown) {
      return;
    }
    if (image.planes.isEmpty) {
      return;
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final yPlane = image.planes.first;
    // Copy luma bytes synchronously before the native ImageProxy is recycled.
    final lumaCopy = Uint8List.fromList(yPlane.bytes);
    final rotationDegrees = _computeSensorRotationDegrees(controller);
    final viewportSize = _lastViewportSize ?? MediaQuery.sizeOf(context);
    final cropRect = _computeNormalizedCropRect(viewportSize);

    _isProcessingFrame = true;
    unawaited(
      _processLiveLumaFrame(
        lumaBytes: lumaCopy,
        width: image.width,
        height: image.height,
        rowStride: yPlane.bytesPerRow,
        pixelStride: yPlane.bytesPerPixel ?? 1,
        rotationDegrees: rotationDegrees,
        cropRect: cropRect,
        isBarcodeSnapshot: widget.isBarcodeMode,
      ),
    );
  }

  Future<void> _processLiveLumaFrame({
    required Uint8List lumaBytes,
    required int width,
    required int height,
    required int rowStride,
    required int pixelStride,
    required int rotationDegrees,
    required Rect? cropRect,
    required bool isBarcodeSnapshot,
  }) async {
    PreparedOcrImage? prepared;
    try {
      prepared = await widget.preprocessor.prepareStreamFrame(
        lumaBytes: lumaBytes,
        width: width,
        height: height,
        rowStride: rowStride,
        pixelStride: pixelStride,
        rotationDegrees: rotationDegrees,
        gamma: _gamma,
        hdrEnabled: _hdrEnabled,
        cropRect: cropRect,
      );
      if (prepared == null || !mounted || widget.isPaused) {
        return;
      }

      if (isBarcodeSnapshot) {
        await _analyzeBarcodeAtPath(prepared.path, isManualSnap: false);
      } else {
        await _analyzeOcrAtPath(prepared.path, isManualSnap: false);
      }
    } catch (_) {
      // Silently skip transient live frames so scanning never stalls or crashes.
    } finally {
      if (prepared != null && prepared.isTemporaryCopy) {
        unawaited(widget.ocrService.deleteTempImage(prepared.path));
      }
      _lastFrameFinishedAt = DateTime.now();
      _isProcessingFrame = false;
    }
  }

  Future<void> _setZoomScale(double normalizedZoom) async {
    final controller = _cameraController;
    final clamped = normalizedZoom.clamp(0.0, 1.0);
    setState(() => _zoomScale = clamped);
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (_maxZoom <= _minZoom) {
      return;
    }
    // Map 0.5 -> 2x when supported so the 2x chip matches standard zoom feel.
    final double targetZoom;
    if (_maxZoom >= 2.0) {
      if (clamped <= 0.5) {
        targetZoom = _minZoom + (2.0 - _minZoom) * (clamped / 0.5);
      } else {
        targetZoom = 2.0 + (_maxZoom - 2.0) * ((clamped - 0.5) / 0.5);
      }
    } else {
      targetZoom = _minZoom + (_maxZoom - _minZoom) * clamped;
    }
    try {
      await controller.setZoomLevel(targetZoom.clamp(_minZoom, _maxZoom));
    } catch (_) {
      // Ignore unsupported zoom adjustments.
    }
  }

  Future<void> _setExposureOffset(double value) async {
    if (!_supportsExposureOffset) {
      return;
    }
    var target = value.clamp(_minExposureOffset, _maxExposureOffset);
    if (_exposureStepSize > 0.0) {
      target = (target / _exposureStepSize).round() * _exposureStepSize;
      target = target.clamp(_minExposureOffset, _maxExposureOffset);
    }
    setState(() => _exposureOffset = target);

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.setExposureOffset(target);
    } catch (_) {
      // Ignore transient hardware exposure errors.
    }
  }

  void _setGamma(double value) {
    setState(() => _gamma = value.clamp(0.45, 2.0));
  }

  void _setHdrEnabled(bool enabled) {
    setState(() => _hdrEnabled = enabled);
  }

  Future<void> _applyLightingPreset(double ev, double gamma, bool hdr) async {
    setState(() {
      _gamma = gamma.clamp(0.45, 2.0);
      _hdrEnabled = hdr;
    });
    if (_supportsExposureOffset) {
      await _setExposureOffset(ev);
    }
  }

  Future<void> _resetLighting() => _applyLightingPreset(0.0, 1.0, false);

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final nextTorch = !_isTorchOn;
    try {
      await controller.setFlashMode(
        nextTorch ? FlashMode.torch : FlashMode.off,
      );
      if (mounted) {
        setState(() => _isTorchOn = nextTorch);
      }
    } catch (_) {
      // Torch unavailable on selected lens.
    }
  }

  Future<void> _handleTapToFocus(
    TapUpDetails details,
    BoxConstraints constraints,
  ) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
      return;
    }
    final point = Offset(
      (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
      (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0),
    );
    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
    } catch (_) {
      // Ignore focus/exposure point failures on lenses without support.
    }
  }

  Rect? _computeNormalizedCropRect(Size viewportSize) {
    final width = viewportSize.width;
    final height = viewportSize.height;
    if (width <= 0 || height <= 0) {
      return null;
    }
    // Crop generously around the horizontal viewfinder reticle so off-center
    // VIN plates/barcodes are kept while trimming cluttered dashboard edges.
    final padX = math.max(widget.scanWindow.width * 0.05, 16.0) / width;
    final padY = math.max(widget.scanWindow.height * 0.90, 80.0) / height;

    final left = ((widget.scanWindow.left / width) - padX).clamp(0.0, 0.35);
    final right = ((widget.scanWindow.right / width) + padX).clamp(0.65, 1.0);
    final top = ((widget.scanWindow.top / height) - padY).clamp(0.0, 0.72);
    final bottom = ((widget.scanWindow.bottom / height) + padY).clamp(0.28, 1.0);

    if (right - left < 0.25 || bottom - top < 0.14) {
      return null;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  void _setTransientBanner(
    String message, {
    required bool isError,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? autoClearAfter,
  }) {
    _transientStatusTimer?.cancel();
    _transientStatusTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
      _statusActionLabel = actionLabel;
      _statusAction = onAction;
    });
    if (autoClearAfter != null) {
      _transientStatusTimer = Timer(autoClearAfter, _clearStatusMessage);
    }
  }

  void _clearStatusMessage() {
    _transientStatusTimer?.cancel();
    _transientStatusTimer = null;
    if (mounted && (_statusMessage != null || _statusActionLabel != null)) {
      setState(() {
        _statusMessage = null;
        _statusActionLabel = null;
        _statusAction = null;
      });
    }
  }

  Future<void> _analyzeBarcodeAtPath(
    String imagePath, {
    required bool isManualSnap,
  }) async {
    final analyzer = widget.onAnalyzeBarcodeImage;
    if (analyzer == null) {
      if (isManualSnap) {
        _setTransientBanner(
          'Barcode image analysis is unavailable on this platform.',
          isError: true,
        );
      }
      return;
    }

    final capture = await analyzer(imagePath);
    if (!mounted || widget.isPaused) {
      return;
    }

    final barcodes = capture?.barcodes ?? const [];
    String? normalFallbackCandidate;

    for (final barcode in barcodes) {
      final candidate = widget.validator.extractFromBarcode(
            barcode.rawValue,
            strictness: widget.strictness,
          ) ??
          widget.validator.extractFromBarcode(
            barcode.displayValue,
            strictness: widget.strictness,
          );
      if (candidate != null) {
        _clearStatusMessage();
        widget.onVinRecognized(candidate);
        return;
      }

      if (widget.strictness == VinScanStrictness.strict &&
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
      _setTransientBanner(
        'Extra barcode characters detected ($recoveredVin)',
        isError: true,
        actionLabel: 'Use Normal',
        onAction: () {
          widget.onSwitchStrictnessToNormal?.call();
          widget.onVinRecognized(recoveredVin);
        },
        autoClearAfter: isManualSnap ? null : const Duration(seconds: 4),
      );
      return;
    }

    if (barcodes.isNotEmpty) {
      _setTransientBanner(
        widget.strictness == VinScanStrictness.strict
            ? 'Barcode is not an exact 17-character VIN'
            : 'Scanned barcode does not contain a valid VIN',
        isError: true,
        autoClearAfter: isManualSnap ? null : const Duration(seconds: 2),
      );
      return;
    }

    if (isManualSnap) {
      final isNeutralLighting =
          !_hdrEnabled &&
          _exposureOffset.abs() < 0.05 &&
          (_gamma - 1.0).abs() < 0.05;
      if (isNeutralLighting) {
        _setTransientBanner(
          'No barcode detected — try HDR or adjusting Exposure/Gamma',
          isError: true,
          actionLabel: 'Lighting',
          onAction: () {
            if (mounted) {
              setState(() => _isLightingPanelExpanded = true);
            }
          },
        );
      } else {
        _setTransientBanner(
          'No VIN barcode detected in photo — try holding steady or OCR mode',
          isError: true,
          actionLabel: 'Manual',
          onAction: () => widget.onManualEntryTap(null),
        );
      }
    }
  }

  Future<void> _analyzeOcrAtPath(
    String imagePath, {
    required bool isManualSnap,
  }) async {
    final ocrResult = await widget.ocrService.recognizeText(imagePath);
    if (!mounted || widget.isPaused) {
      return;
    }

    final lines = ocrResult.orderedLines;
    final extraction = widget.validator.extractFromOcrText(
      lines,
      strictness: widget.strictness,
    );

    if (extraction.vin != null) {
      _clearStatusMessage();
      widget.onVinRecognized(extraction.vin!);
      return;
    }

    // If Strict mode missed a VIN that Normal mode can recover, offer a 1-tap switch.
    if (widget.strictness == VinScanStrictness.strict &&
        widget.onSwitchStrictnessToNormal != null) {
      final normalFallback = widget.validator.extractFromOcrText(
        lines,
        strictness: VinScanStrictness.normal,
      );
      if (normalFallback.vin != null) {
        _setTransientBanner(
          'Possible VIN (${normalFallback.vin}) needs Normal mode',
          isError: true,
          actionLabel: 'Use Normal',
          onAction: () {
            widget.onSwitchStrictnessToNormal?.call();
            widget.onVinRecognized(normalFallback.vin!);
          },
          autoClearAfter: isManualSnap ? null : const Duration(seconds: 4),
        );
        return;
      }
    }

    final snippet = extraction.bestSnippet;
    if (snippet != null && snippet.isNotEmpty) {
      _setTransientBanner(
        'Partial read: $snippet',
        isError: true,
        actionLabel: 'Edit',
        onAction: () => widget.onManualEntryTap(snippet),
        autoClearAfter: isManualSnap ? null : const Duration(seconds: 3),
      );
      return;
    }

    if (!isManualSnap) {
      return;
    }

    final isNeutralLighting =
        !_hdrEnabled &&
        _exposureOffset.abs() < 0.05 &&
        (_gamma - 1.0).abs() < 0.05;
    if (lines.isEmpty) {
      if (isNeutralLighting) {
        _setTransientBanner(
          'No text detected — try HDR or adjusting Exposure/Gamma',
          isError: true,
          actionLabel: 'Lighting',
          onAction: () {
            if (mounted) {
              setState(() => _isLightingPanelExpanded = true);
            }
          },
        );
      } else {
        _setTransientBanner(
          'No text detected — hold steady or try another preset',
          isError: true,
          actionLabel: 'Manual',
          onAction: () => widget.onManualEntryTap(null),
        );
      }
    } else {
      _setTransientBanner(
        'No valid 17-character VIN found in frame',
        isError: true,
        actionLabel: 'Manual',
        onAction: () => widget.onManualEntryTap(null),
      );
    }
  }

  Future<void> _captureAndAnalyzePhoto({
    bool isFromContinuousFallback = false,
  }) async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _isProcessingFrame ||
        widget.isPaused) {
      return;
    }

    if (!widget.isBarcodeMode && !_isModelReady) {
      await _ensureModelsReady();
      if (!mounted || !_isModelReady) {
        return;
      }
    }

    final viewportSize = _lastViewportSize ?? MediaQuery.sizeOf(context);
    final cropRect = _computeNormalizedCropRect(viewportSize);
    final activeGamma = _gamma;
    final activeHdr = _hdrEnabled;
    final isBarcodeSnapshot = widget.isBarcodeMode;

    if (!isFromContinuousFallback) {
      setState(() {
        _isProcessingFrame = true;
        _statusMessage =
            isBarcodeSnapshot ? 'Looking for barcode...' : 'Looking for text...';
        _statusIsError = false;
        _statusActionLabel = null;
        _statusAction = null;
      });
    } else {
      _isProcessingFrame = true;
    }

    String? rawImagePath;
    PreparedOcrImage? preparedImage;
    try {
      final photo = await controller.takePicture();
      rawImagePath = photo.path;
      preparedImage = await widget.preprocessor.prepareForOcr(
        imagePath: rawImagePath,
        gamma: activeGamma,
        hdrEnabled: activeHdr,
        cropRect: cropRect,
      );
      if (isBarcodeSnapshot) {
        await _analyzeBarcodeAtPath(
          preparedImage.path,
          isManualSnap: !isFromContinuousFallback,
        );
      } else {
        await _analyzeOcrAtPath(
          preparedImage.path,
          isManualSnap: !isFromContinuousFallback,
        );
      }
    } on VinOcrException catch (error) {
      if (!mounted || isFromContinuousFallback) {
        return;
      }
      _setTransientBanner(
        error.message,
        isError: true,
        actionLabel: 'Retry',
        onAction: () => unawaited(_captureAndAnalyzePhoto()),
      );
    } on CameraException catch (error) {
      if (!mounted || isFromContinuousFallback) {
        return;
      }
      _setTransientBanner(
        error.description ?? 'Camera capture failed. Please try again.',
        isError: true,
      );
    } catch (_) {
      if (!mounted || isFromContinuousFallback) {
        return;
      }
      _setTransientBanner(
        'Capture failed. Please try again.',
        isError: true,
      );
    } finally {
      if (rawImagePath != null) {
        unawaited(widget.ocrService.deleteTempImage(rawImagePath));
      }
      if (preparedImage != null && preparedImage.isTemporaryCopy) {
        unawaited(widget.ocrService.deleteTempImage(preparedImage.path));
      }
      if (mounted && !isFromContinuousFallback) {
        setState(() => _isProcessingFrame = false);
      } else {
        _isProcessingFrame = false;
      }
      if (mounted && widget.isPaused) {
        final activeController = _cameraController;
        if (activeController != null && activeController.value.isInitialized) {
          unawaited(_pausePreviewSafely(activeController));
        }
      }
    }
  }

  @override
  void dispose() {
    _transientStatusTimer?.cancel();
    _fallbackContinuousTimer?.cancel();
    widget.switchCameraSignal?.removeListener(_onSwitchCameraRequested);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    super.dispose();
  }

  String _buildPromptText() {
    if (!widget.isBarcodeMode && _isPreparingModels) {
      return 'Preparing PaddleOCR v5 models...';
    }
    final strictnessLabel =
        widget.strictness == VinScanStrictness.normal ? 'Normal' : 'Strict';
    final hdrTag = _hdrEnabled ? ' • HDR' : '';
    if (widget.isBarcodeMode) {
      return widget.isContinuous
          ? 'Align VIN barcode ($strictnessLabel$hdrTag)'
          : 'Align VIN barcode & tap Snap ($strictnessLabel$hdrTag)';
    }
    return widget.isContinuous
        ? 'Live OCR scanning printed VIN ($strictnessLabel$hdrTag)'
        : 'Align printed VIN & tap Snap ($strictnessLabel$hdrTag)';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = _cameraController;
    final isReady = controller != null && controller.value.isInitialized;
    final applyPreviewFilter = _hdrEnabled || (_gamma - 1.0).abs() >= 0.02;

    if (_cameraError != null) {
      return ColoredBox(
        color: colorScheme.surface,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _isPermissionDenied
                          ? Icons.no_photography_rounded
                          : Icons.videocam_off_rounded,
                      size: 48,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isPermissionDenied
                          ? 'Camera Permission Required'
                          : 'Camera Unavailable',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _cameraError!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (_isPermissionDenied && !kIsWeb) ...<Widget>[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => unawaited(openAppSettings()),
                          icon: const Icon(Icons.settings_rounded),
                          label: const Text('Open App Settings'),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => unawaited(_initializeCamera()),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry Camera'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: () => widget.onManualEntryTap(null),
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

    final showSnapButton = !widget.isContinuous;
    final String? snapLabel;
    if (!showSnapButton) {
      snapLabel = null;
    } else if (_isProcessingFrame) {
      snapLabel = widget.isBarcodeMode ? 'Scanning...' : 'Reading VIN...';
    } else if (!widget.isBarcodeMode && _isPreparingModels) {
      snapLabel = 'Preparing OCR...';
    } else {
      snapLabel = widget.isBarcodeMode ? 'Snap Barcode' : 'Snap VIN (OCR)';
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (isReady)
          LayoutBuilder(
            builder: (context, constraints) {
              _lastViewportSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final previewSize = controller.value.previewSize;
              final isPortrait =
                  MediaQuery.orientationOf(context) == Orientation.portrait;
              final rawPreview = previewSize == null
                  ? CameraPreview(controller)
                  : FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: isPortrait
                            ? previewSize.height
                            : previewSize.width,
                        height: isPortrait
                            ? previewSize.width
                            : previewSize.height,
                        child: CameraPreview(controller),
                      ),
                    );
              final filteredPreview = applyPreviewFilter
                  ? ColorFiltered(
                      colorFilter: ColorFilter.matrix(
                        OcrImagePreprocessor.buildPreviewColorMatrix(
                          gamma: _gamma,
                          hdrEnabled: _hdrEnabled,
                        ),
                      ),
                      child: rawPreview,
                    )
                  : rawPreview;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    unawaited(_handleTapToFocus(details, constraints)),
                child: filteredPreview,
              );
            },
          )
        else
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  if (_isInitializingCamera) ...<Widget>[
                    const SizedBox(height: 12),
                    const Text(
                      'Starting camera...',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ScannerOverlay(
          scanWindow: widget.scanWindow,
          isPaused: widget.isPaused || !isReady,
          showScanLine: widget.isContinuous,
          promptText: _buildPromptText(),
          statusMessage:
              _statusMessage ?? (!widget.isBarcodeMode ? _modelError : null),
          statusIsError: _statusMessage != null ? _statusIsError : true,
          statusActionLabel: _statusActionLabel,
          onStatusAction: _statusAction,
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ScannerControls(
            zoomScale: _zoomScale,
            torchState: !isReady
                ? TorchState.unavailable
                : (_isTorchOn ? TorchState.on : TorchState.off),
            isCameraRunning: isReady && !widget.isPaused,
            supportsZoom: _maxZoom > _minZoom,
            onZoomChanged: (value) => unawaited(_setZoomScale(value)),
            onToggleTorch: () => unawaited(_toggleTorch()),
            onManualEntryTap: () => widget.onManualEntryTap(null),
            primaryActionLabel: snapLabel,
            primaryActionIcon: widget.isBarcodeMode
                ? Icons.camera_alt_rounded
                : Icons.document_scanner_rounded,
            isPrimaryBusy:
                _isProcessingFrame || (!widget.isBarcodeMode && _isPreparingModels),
            onPrimaryActionTap: isReady && !widget.isPaused
                ? () => unawaited(_captureAndAnalyzePhoto())
                : null,
            showLightingControls: true,
            isLightingExpanded: _isLightingPanelExpanded,
            onToggleLightingPanel: () => setState(
              () => _isLightingPanelExpanded = !_isLightingPanelExpanded,
            ),
            supportsExposureOffset: _supportsExposureOffset,
            exposureOffset: _exposureOffset,
            minExposureOffset: _minExposureOffset,
            maxExposureOffset: _maxExposureOffset,
            onExposureChanged: (ev) => unawaited(_setExposureOffset(ev)),
            gamma: _gamma,
            onGammaChanged: _setGamma,
            hdrEnabled: _hdrEnabled,
            onHdrChanged: _setHdrEnabled,
            onResetLighting: () => unawaited(_resetLighting()),
            onApplyLightingPreset: (ev, gamma, hdr) =>
                unawaited(_applyLightingPreset(ev, gamma, hdr)),
          ),
        ),
      ],
    );
  }
}
