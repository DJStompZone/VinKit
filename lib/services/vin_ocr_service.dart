import 'dart:ui';

import 'package:vinkit_app/services/vin_ocr_service_stub.dart'
    if (dart.library.io) 'package:vinkit_app/services/vin_ocr_service_io.dart'
    as impl;

/// Exception thrown when on-device OCR model preparation or text recognition fails.
class VinOcrException implements Exception {
  /// Creates a [VinOcrException] with a user-facing [message].
  const VinOcrException(this.message, {this.code});

  /// Human-readable description of the OCR error.
  final String message;

  /// Optional platform error code.
  final String? code;

  @override
  String toString() =>
      code == null ? 'VinOcrException: $message' : 'VinOcrException($code): $message';
}

/// Single recognized text region returned by [VinOcrService].
class VinOcrTextBlock {
  /// Creates a [VinOcrTextBlock].
  const VinOcrTextBlock({
    required this.text,
    required this.confidence,
    this.boundingBox = Rect.zero,
  });

  /// Recognized text string.
  final String text;

  /// Confidence score in the range `0.0..1.0`.
  final double confidence;

  /// Bounding box of the detected text region in image coordinates.
  final Rect boundingBox;
}

/// Aggregated result of running on-device OCR on a captured camera image.
class VinOcrResult {
  /// Creates a [VinOcrResult].
  const VinOcrResult({
    required this.blocks,
    this.imageSize = Size.zero,
  });

  /// All recognized text blocks in the image.
  final List<VinOcrTextBlock> blocks;

  /// Source image dimensions reported by the OCR engine.
  final Size imageSize;

  /// Returns deduplicated candidate lines ordered for VIN extraction.
  ///
  /// Includes both merged horizontal rows (combining split VIN fragments on
  /// the same line) and individual recognized text blocks.
  List<String> get orderedLines {
    final nonEmpty = blocks
        .where((block) => block.text.trim().isNotEmpty)
        .toList(growable: false);
    if (nonEmpty.isEmpty) {
      return const <String>[];
    }

    bool hasValidBox(Rect rect) =>
        rect != Rect.zero &&
        rect.left.isFinite &&
        rect.top.isFinite &&
        rect.right.isFinite &&
        rect.bottom.isFinite &&
        rect.width >= 0 &&
        rect.height >= 0;

    final hasGeometry = nonEmpty.every((block) => hasValidBox(block.boundingBox));
    final lines = <String>[];
    final seen = <String>{};

    void addLine(String value) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        lines.add(trimmed);
      }
    }

    if (hasGeometry) {
      final sorted = List<VinOcrTextBlock>.of(nonEmpty)
        ..sort((a, b) {
          final dy = a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy);
          if (dy != 0) {
            return dy;
          }
          return a.boundingBox.left.compareTo(b.boundingBox.left);
        });

      final rows = <List<VinOcrTextBlock>>[];
      for (final block in sorted) {
        if (rows.isEmpty) {
          rows.add(<VinOcrTextBlock>[block]);
          continue;
        }
        final currentRow = rows.last;
        final avgCenterY = currentRow
                .map((b) => b.boundingBox.center.dy)
                .reduce((a, b) => a + b) /
            currentRow.length;
        final avgHeight = currentRow
                .map((b) => b.boundingBox.height)
                .reduce((a, b) => a + b) /
            currentRow.length;
        final tolerance = (avgHeight > 0 ? avgHeight : 24.0) * 0.65;

        if ((block.boundingBox.center.dy - avgCenterY).abs() <= tolerance) {
          currentRow.add(block);
        } else {
          rows.add(<VinOcrTextBlock>[block]);
        }
      }

      for (final row in rows) {
        row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
        if (row.length > 1) {
          addLine(row.map((b) => b.text.trim()).join(' '));
          addLine(row.map((b) => b.text.trim()).join());
        }
        for (final block in row) {
          addLine(block.text);
        }
      }
    } else {
      if (nonEmpty.length > 1) {
        addLine(nonEmpty.map((b) => b.text.trim()).join(' '));
      }
      for (final block in nonEmpty) {
        addLine(block.text);
      }
    }

    return lines;
  }
}

/// Abstract interface for on-device VIN text recognition (PaddleOCR v5 via
/// ONNX Runtime Mobile on Android and Apple Vision on iOS).
abstract interface class VinOcrService {
  /// Whether on-device OCR is supported on the current platform.
  bool get isSupported;

  /// Returns `true` when required native OCR models are cached and ready.
  Future<bool> isModelReady();

  /// Ensures required native OCR models are downloaded and verified on device.
  Future<void> prepareModels();

  /// Runs on-device text recognition on the JPEG/PNG image at [imagePath].
  ///
  /// Passing [requestId] allows cancelling an in-flight native OCR request via
  /// [cancelPendingRecognition] (and replaces any prior request with the same ID).
  Future<VinOcrResult> recognizeText(String imagePath, {String? requestId});

  /// Best-effort cancellation of an in-flight native OCR request started with
  /// [requestId].
  Future<void> cancelPendingRecognition(String requestId);

  /// Best-effort deletion of a temporary captured camera file at [imagePath].
  Future<void> deleteTempImage(String imagePath);
}

/// Creates the platform-appropriate [VinOcrService] implementation.
VinOcrService createPlatformVinOcrService() => impl.createPlatformVinOcrService();
