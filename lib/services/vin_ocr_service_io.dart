import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_ocr/mobile_ocr_plugin.dart';
import 'package:vinkit_app/services/vin_ocr_service.dart';

/// Mobile [VinOcrService] backed by `mobile_ocr` (ONNX Runtime Mobile with
/// PaddleOCR v5 on Android, and Apple Vision on iOS).
class MobileVinOcrService implements VinOcrService {
  /// Creates a [MobileVinOcrService].
  MobileVinOcrService({MobileOcr? plugin}) : _plugin = plugin ?? MobileOcr();

  final MobileOcr _plugin;

  @override
  bool get isSupported {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Future<bool> isModelReady() async {
    if (!isSupported) {
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return true;
    }
    try {
      final availability = await _plugin.getModelAvailability();
      return availability.detectorReady && availability.recognizerReady;
    } on OcrException catch (error) {
      debugPrint('Failed checking OCR model availability: $error');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> prepareModels() async {
    if (!isSupported) {
      throw const VinOcrException(
        'On-device OCR is only available on Android and iOS.',
        code: 'UNSUPPORTED_PLATFORM',
      );
    }
    try {
      final status = await _plugin.prepareModels();
      if (!status.isReady) {
        throw const VinOcrException(
          'OCR models could not be prepared. Check your connection and retry.',
          code: 'MODEL_NOT_READY',
        );
      }
    } on OcrException catch (error) {
      throw VinOcrException(error.message, code: error.code);
    } on MissingPluginException {
      throw const VinOcrException(
        'On-device OCR plugin is unavailable on this device.',
        code: 'MISSING_PLUGIN',
      );
    }
  }

  @override
  Future<VinOcrResult> recognizeText(
    String imagePath, {
    String? requestId,
  }) async {
    if (!isSupported) {
      throw const VinOcrException(
        'On-device OCR is only available on Android and iOS.',
        code: 'UNSUPPORTED_PLATFORM',
      );
    }
    try {
      final detection = await _plugin.detectText(
        imagePath: imagePath,
        includeAllConfidenceScores: true,
        requestId: requestId,
      );
      final blocks = detection.blocks
          .map(
            (block) => VinOcrTextBlock(
              text: block.text,
              confidence: block.confidence,
              boundingBox: block.boundingBox,
            ),
          )
          .toList(growable: false);
      return VinOcrResult(
        blocks: blocks,
        imageSize: detection.imageSize,
      );
    } on OcrException catch (error) {
      throw VinOcrException(error.message, code: error.code);
    } on MissingPluginException {
      throw const VinOcrException(
        'On-device OCR plugin is unavailable on this device.',
        code: 'MISSING_PLUGIN',
      );
    } on ArgumentError catch (error) {
      throw VinOcrException(
        error.message?.toString() ?? 'Captured image file could not be read.',
        code: 'INVALID_IMAGE',
      );
    } on PlatformException catch (error) {
      throw VinOcrException(
        error.message ?? 'On-device OCR failed while reading the image.',
        code: error.code,
      );
    } catch (error) {
      debugPrint('Unexpected OCR recognition error: $error');
      throw const VinOcrException(
        'OCR could not process this capture. Try steadier framing or adjusting lighting.',
        code: 'UNEXPECTED_ERROR',
      );
    }
  }

  @override
  Future<void> cancelPendingRecognition(String requestId) async {
    if (!isSupported) {
      return;
    }
    try {
      await _plugin.cancelRequest(requestId);
    } catch (_) {
      // Ignore cancellation errors if no request is active or engine is detaching.
    }
  }

  @override
  Future<void> deleteTempImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup errors on temporary cache images.
    }
  }
}

/// Creates the IO [VinOcrService] implementation.
VinOcrService createPlatformVinOcrService() => MobileVinOcrService();
