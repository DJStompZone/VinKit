import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart' show TorchState;
import 'package:permission_handler/permission_handler.dart';
import 'package:vinkit_app/services/ocr_image_preprocessor.dart';
import 'package:vinkit_app/services/vin_ocr_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';
import 'package:vinkit_app/widgets/scanner_controls.dart';
import 'package:vinkit_app/widgets/scanner_overlay.dart';

/// Live camera capture view for reading plaintext printed VINs using on-device
/// OCR (ONNX Runtime Mobile with PaddleOCR v5 on Android, Apple Vision on iOS).
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
    this.onSwitchStrictnessToNormal,
    this.preprocessor = const OcrImagePreprocessor(),
  });

  /// On-device OCR engine (PaddleOCR v5 ONNX Runtime / Apple Vision).
  final VinOcrService ocrService;

  /// VIN validator and OCR text extractor.
  final VinValidator validator;

  /// Active VIN matching strictness mode.
  final VinScanStrictness strictness;

  /// Alignment frame rectangle matching the barcode viewfinder.
  final Rect scanWindow;

  /// Whether camera interaction is temporarily paused (e.g. result screen open).
  final bool isPaused;

  /// Called immediately when OCR recognizes a valid 17-character VIN.
  final ValueChanged<String> onVinRecognized;

  /// Called when the user opens manual VIN entry, optionally prefilled with a
  /// partial OCR snippet.
  final ValueChanged<String?> onManualEntryTap;

  /// Optional shortcut to switch strictness from Strict to Normal when OCR
  /// detects a candidate that only matches under Normal mode.
  final VoidCallback? onSwitchStrictnessToNormal;

  /// Native image preprocessor cropping to the viewfinder ROI and applying
  /// user-selected gamma correction before OCR inference.
  final OcrImagePreprocessor preprocessor;

  @override
  State<OcrCameraView> createState() => _OcrCameraViewState();
}

class _OcrCameraViewState extends State<OcrCameraView>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  int _selectedCameraIndex = 0;
  int _cameraGeneration = 0;

  bool _isInitializingCamera = true;
  String? _cameraError;
  bool _isPermissionDenied = false;

  bool _isModelReady = false;
  bool _isPreparingModels = false;
  String? _modelError;

  bool _isProcessingOcr = false;
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
    unawaited(_initializeCamera());
    unawaited(_ensureModelsReady());
  }

  @override
  void didUpdateWidget(covariant OcrCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (oldWidget.isPaused != widget.isPaused) {
      if (widget.isPaused) {
        if (!_isProcessingOcr) {
          unawaited(_pausePreviewSafely(controller));
        }
      } else {
        unawaited(_resumePreviewSafely(controller));
      }
    }
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
    if (!widget.ocrService.isSupported || _isPreparingModels) {
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

      _cameras = cameras;
      if (_selectedCameraIndex >= _cameras.length) {
        _selectedCameraIndex = 0;
      }
      // Default to the back camera on first initialization.
      if (_selectedCameraIndex == 0) {
        final backIndex = _cameras.indexWhere(
          (cam) => cam.lensDirection == CameraLensDirection.back,
        );
        if (backIndex >= 0) {
          _selectedCameraIndex = backIndex;
        }
      }

      final controller = CameraController(
        _cameras[_selectedCameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
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
            ? 'Camera permission is required to read printed VINs with OCR.'
            : (error.description ?? 'Unable to start OCR camera preview.');
      });
    } catch (_) {
      if (!mounted || generation != _cameraGeneration) {
        return;
      }
      setState(() {
        _isInitializingCamera = false;
        _cameraError = 'Unable to start OCR camera preview.';
      });
    }
  }

  Future<void> _disposeCamera({bool bumpGeneration = true}) async {
    if (bumpGeneration) {
      _cameraGeneration++;
    }
    final controller = _cameraController;
    _cameraController = null;
    if (controller == null) {
      return;
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
    // Map 0.5 -> 2x when supported so the 2x chip matches Barcode mode feel.
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

  Future<void> _applyLightingPreset(double ev, double gamma) async {
    setState(() => _gamma = gamma.clamp(0.45, 2.0));
    if (_supportsExposureOffset) {
      await _setExposureOffset(ev);
    }
  }

  Future<void> _resetLighting() => _applyLightingPreset(0.0, 1.0);

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
    // VIN plates are kept while trimming cluttered dashboard/windshield edges.
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

  Future<void> _captureAndRecognize() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _isProcessingOcr ||
        widget.isPaused) {
      return;
    }

    if (!_isModelReady) {
      await _ensureModelsReady();
      if (!mounted || !_isModelReady) {
        return;
      }
    }

    final viewportSize = _lastViewportSize ?? MediaQuery.sizeOf(context);
    final cropRect = _computeNormalizedCropRect(viewportSize);
    final activeGamma = _gamma;

    setState(() {
      _isProcessingOcr = true;
      _statusMessage = 'Looking for text...';
      _statusIsError = false;
      _statusActionLabel = null;
      _statusAction = null;
    });

    String? rawImagePath;
    PreparedOcrImage? preparedImage;
    try {
      final photo = await controller.takePicture();
      rawImagePath = photo.path;
      preparedImage = await widget.preprocessor.prepareForOcr(
        imagePath: rawImagePath,
        gamma: activeGamma,
        cropRect: cropRect,
      );
      final ocrResult = await widget.ocrService.recognizeText(
        preparedImage.path,
      );
      if (!mounted) {
        return;
      }

      final lines = ocrResult.orderedLines;
      final extraction = widget.validator.extractFromOcrText(
        lines,
        strictness: widget.strictness,
      );

      if (extraction.vin != null) {
        setState(() {
          _isProcessingOcr = false;
          _statusMessage = null;
          _statusActionLabel = null;
          _statusAction = null;
        });
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
          setState(() {
            _isProcessingOcr = false;
            _statusMessage =
                'Possible VIN (${normalFallback.vin}) needs Normal mode';
            _statusIsError = true;
            _statusActionLabel = 'Use Normal';
            _statusAction = () {
              widget.onSwitchStrictnessToNormal?.call();
              widget.onVinRecognized(normalFallback.vin!);
            };
          });
          return;
        }
      }

      final snippet = extraction.bestSnippet;
      final isNeutralLighting =
          _exposureOffset.abs() < 0.05 && (_gamma - 1.0).abs() < 0.05;
      setState(() {
        _isProcessingOcr = false;
        _statusIsError = true;
        if (snippet != null && snippet.isNotEmpty) {
          _statusMessage = 'Partial read: $snippet';
          _statusActionLabel = 'Edit';
          _statusAction = () => widget.onManualEntryTap(snippet);
        } else if (lines.isEmpty) {
          if (isNeutralLighting) {
            _statusMessage = 'No text detected — try adjusting Exposure/Gamma';
            _statusActionLabel = 'Lighting';
            _statusAction = () {
              if (mounted) {
                setState(() => _isLightingPanelExpanded = true);
              }
            };
          } else {
            _statusMessage =
                'No text detected — hold steady or try another preset';
            _statusActionLabel = 'Manual';
            _statusAction = () => widget.onManualEntryTap(null);
          }
        } else {
          _statusMessage = 'No valid 17-character VIN found in frame';
          _statusActionLabel = 'Manual';
          _statusAction = () => widget.onManualEntryTap(null);
        }
      });
    } on VinOcrException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessingOcr = false;
        _statusMessage = error.message;
        _statusIsError = true;
        _statusActionLabel = 'Retry';
        _statusAction = () => unawaited(_captureAndRecognize());
      });
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessingOcr = false;
        _statusMessage =
            error.description ?? 'Camera capture failed. Please try again.';
        _statusIsError = true;
        _statusActionLabel = null;
        _statusAction = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessingOcr = false;
        _statusMessage = 'OCR capture failed. Please try again.';
        _statusIsError = true;
        _statusActionLabel = null;
        _statusAction = null;
      });
    } finally {
      if (rawImagePath != null) {
        unawaited(widget.ocrService.deleteTempImage(rawImagePath));
      }
      if (preparedImage != null && preparedImage.isTemporaryCopy) {
        unawaited(widget.ocrService.deleteTempImage(preparedImage.path));
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
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = _cameraController;
    final isReady = controller != null && controller.value.isInitialized;
    final strictnessLabel =
        widget.strictness == VinScanStrictness.normal ? 'Normal' : 'Strict';
    final applyPreviewGamma = (_gamma - 1.0).abs() >= 0.02;

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
                          : 'OCR Camera Unavailable',
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
              final filteredPreview = applyPreviewGamma
                  ? ColorFiltered(
                      colorFilter: ColorFilter.matrix(
                        OcrImagePreprocessor.buildPreviewGammaMatrix(_gamma),
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
                      'Starting OCR camera...',
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
          showScanLine: false,
          promptText: _isPreparingModels
              ? 'Preparing PaddleOCR v5 models...'
              : 'Align printed VIN text & tap Read VIN ($strictnessLabel)',
          statusMessage: _statusMessage ?? _modelError,
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
            primaryActionLabel: _isProcessingOcr
                ? 'Reading VIN...'
                : (_isPreparingModels ? 'Preparing OCR...' : 'Read VIN (OCR)'),
            primaryActionIcon: Icons.document_scanner_rounded,
            isPrimaryBusy: _isProcessingOcr || _isPreparingModels,
            onPrimaryActionTap: isReady && !widget.isPaused
                ? () => unawaited(_captureAndRecognize())
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
            onResetLighting: () => unawaited(_resetLighting()),
            onApplyLightingPreset: (ev, gamma) =>
                unawaited(_applyLightingPreset(ev, gamma)),
          ),
        ),
      ],
    );
  }
}
