import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Prepared image path returned by [OcrImagePreprocessor.prepareForOcr].
class PreparedOcrImage {
  /// Creates a [PreparedOcrImage].
  const PreparedOcrImage({
    required this.path,
    required this.isTemporaryCopy,
  });

  /// File path to pass into the OCR engine.
  final String path;

  /// Whether [path] is a newly generated temporary file that should be deleted
  /// after OCR finishes.
  final bool isTemporaryCopy;
}

/// Preprocesses captured OCR images by cropping around the VIN viewfinder ROI,
/// bounding resolution to avoid native OOM pressure, and applying pixel-level
/// gamma correction.
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

  /// Prepares [imagePath] for OCR with optional normalized [cropRect] (`0..1`)
  /// and [gamma] (`0.45..2.0`, where `1.0` is neutral, `> 1.0` lifts shadows,
  /// and `< 1.0` tames glare).
  ///
  /// Falls back cleanly to the original [imagePath] when native preprocessing
  /// is unavailable or fails.
  Future<PreparedOcrImage> prepareForOcr({
    required String imagePath,
    double gamma = 1.0,
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

  /// Builds a 4x5 [ColorFilter.matrix] approximating power-law [gamma]
  /// (`out = in^(1 / gamma)`) on the live camera preview.
  static List<double> buildPreviewGammaMatrix(double gamma) {
    final clamped = gamma.clamp(0.45, 2.0);
    if ((clamped - 1.0).abs() < 0.02) {
      return const <double>[
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ];
    }

    final midtone = math.pow(0.5, 1.0 / clamped).toDouble();
    final double scale;
    final double bias;
    if (clamped >= 1.0) {
      bias = (2.0 * midtone - 1.0).clamp(0.0, 0.55);
      scale = 1.0 - bias;
    } else {
      scale = (2.0 * (1.0 - midtone)).clamp(1.0, 2.1);
      bias = 1.0 - scale;
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
