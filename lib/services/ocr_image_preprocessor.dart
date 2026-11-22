import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Prepared image path returned by [OcrImagePreprocessor.prepareForOcr] or
/// [OcrImagePreprocessor.prepareStreamFrame].
class PreparedOcrImage {
  /// Creates a [PreparedOcrImage].
  const PreparedOcrImage({
    required this.path,
    required this.isTemporaryCopy,
  });

  /// File path to pass into the barcode or OCR engine.
  final String path;

  /// Whether [path] is a newly generated temporary file that should be deleted
  /// after recognition finishes.
  final bool isTemporaryCopy;
}

/// Preprocesses captured photos and live camera stream frames by cropping
/// around the VIN viewfinder ROI, bounding resolution to avoid native OOM
/// pressure, and applying optional HDR local-contrast recovery + gamma LUT.
class OcrImagePreprocessor {
  /// Creates an [OcrImagePreprocessor].
  const OcrImagePreprocessor({
    this.channel = defaultChannel,
  });

  /// Default platform method channel handled on Android in `MainActivity.kt`.
  static const MethodChannel defaultChannel = MethodChannel(
    'zone.stomp.vinkit/ocr_image_prep',
  );

  /// Platform channel used to invoke native image preprocessing.
  final MethodChannel channel;

  /// Whether native live stream frame preparation (`prepareStreamFrame`) is
  /// supported on the current platform.
  bool get supportsStreamFramePrep =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Prepares [imagePath] for barcode/OCR recognition with optional normalized
  /// [cropRect] (`0..1`), [gamma] (`0.45..2.0`), and [hdrEnabled] tone/contrast
  /// enhancement.
  ///
  /// Falls back cleanly to the original [imagePath] when native preprocessing
  /// is unavailable or fails.
  Future<PreparedOcrImage> prepareForOcr({
    required String imagePath,
    double gamma = 1.0,
    bool hdrEnabled = false,
    Rect? cropRect,
    int maxDimension = 1600,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return PreparedOcrImage(path: imagePath, isTemporaryCopy: false);
    }

    try {
      final preparedPath = await channel.invokeMethod<String>(
        'prepareOcrImage',
        <String, Object?>{
          'imagePath': imagePath,
          'gamma': gamma.clamp(0.35, 2.5),
          'hdr': hdrEnabled,
          'maxDimension': maxDimension,
          if (cropRect != null) ...<String, double>{
            'cropLeft': cropRect.left.clamp(0.0, 0.95),
            'cropTop': cropRect.top.clamp(0.0, 0.95),
            'cropRight': cropRect.right.clamp(0.05, 1.0),
            'cropBottom': cropRect.bottom.clamp(0.05, 1.0),
          },
        },
      );
      if (preparedPath != null &&
          preparedPath.isNotEmpty &&
          preparedPath != imagePath) {
        return PreparedOcrImage(path: preparedPath, isTemporaryCopy: true);
      }
    } on MissingPluginException {
      // Native preprocessor unavailable (e.g. widget tests or non-Android).
    } on PlatformException {
      // Fall back to original image if preprocessing reports a platform error.
    } catch (_) {
      // Defensive fallback.
    }

    return PreparedOcrImage(path: imagePath, isTemporaryCopy: false);
  }

  /// Converts a live camera luminance plane (`YUV_420_888` / `NV21` plane 0)
  /// directly into an oriented, ROI-cropped, Gamma/HDR-adjusted temporary JPEG
  /// for fast, silent continuous scanning.
  ///
  /// Returns `null` if native stream preparation is unavailable or fails.
  Future<PreparedOcrImage?> prepareStreamFrame({
    required Uint8List lumaBytes,
    required int width,
    required int height,
    required int rowStride,
    required int pixelStride,
    required int rotationDegrees,
    double gamma = 1.0,
    bool hdrEnabled = false,
    Rect? cropRect,
    int maxDimension = 1280,
  }) async {
    if (!supportsStreamFramePrep ||
        lumaBytes.isEmpty ||
        width <= 0 ||
        height <= 0) {
      return null;
    }

    try {
      final preparedPath = await channel.invokeMethod<String>(
        'prepareStreamFrame',
        <String, Object?>{
          'lumaBytes': lumaBytes,
          'width': width,
          'height': height,
          'rowStride': rowStride,
          'pixelStride': pixelStride,
          'rotationDegrees': rotationDegrees,
          'gamma': gamma.clamp(0.35, 2.5),
          'hdr': hdrEnabled,
          'maxDimension': maxDimension,
          if (cropRect != null) ...<String, double>{
            'cropLeft': cropRect.left.clamp(0.0, 0.95),
            'cropTop': cropRect.top.clamp(0.0, 0.95),
            'cropRight': cropRect.right.clamp(0.05, 1.0),
            'cropBottom': cropRect.bottom.clamp(0.05, 1.0),
          },
        },
      );
      if (preparedPath != null && preparedPath.isNotEmpty) {
        return PreparedOcrImage(path: preparedPath, isTemporaryCopy: true);
      }
    } on MissingPluginException {
      // Unavailable in tests or non-Android runtimes.
    } on PlatformException {
      // Skip frame on transient error.
    } catch (_) {
      // Defensive fallback.
    }
    return null;
  }

  /// Builds a 4x5 [ColorFilter.matrix] approximating power-law [gamma]
  /// (`out = in^(1 / gamma)`) on the live camera preview.
  static List<double> buildPreviewGammaMatrix(double gamma) =>
      buildPreviewColorMatrix(gamma: gamma);

  /// Builds a 4x5 [ColorFilter.matrix] combining live preview approximations of
  /// [gamma] (`0.45..2.0`) and [hdrEnabled] local contrast boost.
  static List<double> buildPreviewColorMatrix({
    double gamma = 1.0,
    bool hdrEnabled = false,
  }) {
    final clamped = gamma.clamp(0.45, 2.0);
    final neutralGamma = (clamped - 1.0).abs() < 0.02;
    if (neutralGamma && !hdrEnabled) {
      return const <double>[
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ];
    }

    double scale = 1.0;
    double bias = 0.0;
    if (!neutralGamma) {
      final midtone = math.pow(0.5, 1.0 / clamped).toDouble();
      if (clamped >= 1.0) {
        bias = (2.0 * midtone - 1.0).clamp(0.0, 0.55);
        scale = 1.0 - bias;
      } else {
        scale = (2.0 * (1.0 - midtone)).clamp(1.0, 2.1);
        bias = 1.0 - scale;
      }
    }

    if (hdrEnabled) {
      // Subtle visual high-contrast cue around mid-gray + shadow lift so HDR
      // mode is immediately recognizable on the live camera preview.
      const contrast = 1.18;
      scale *= contrast;
      bias = contrast * (bias - 0.5) + 0.52;
    }

    final offset = bias * 255.0;
    return <double>[
      scale, 0, 0, 0, offset,
      0, scale, 0, 0, offset,
      0, 0, scale, 0, offset,
      0, 0, 0, 1, 0,
    ];
  }
}
