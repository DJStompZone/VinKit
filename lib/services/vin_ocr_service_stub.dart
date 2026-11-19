import 'package:vinkit_app/services/vin_ocr_service.dart';

/// Fallback [VinOcrService] used on Web/Wasm where native ONNX Runtime Mobile
/// and Apple Vision OCR are unavailable.
class UnsupportedVinOcrService implements VinOcrService {
  /// Creates an [UnsupportedVinOcrService].
  const UnsupportedVinOcrService();

  @override
  bool get isSupported => false;

  @override
  Future<bool> isModelReady() async => false;

  @override
  Future<void> prepareModels() async {
    throw const VinOcrException(
      'On-device OCR is only available on Android and iOS.',
      code: 'UNSUPPORTED_PLATFORM',
    );
  }

  @override
  Future<VinOcrResult> recognizeText(String imagePath) async {
    throw const VinOcrException(
      'On-device OCR is only available on Android and iOS.',
      code: 'UNSUPPORTED_PLATFORM',
    );
  }

  @override
  Future<void> deleteTempImage(String imagePath) async {}
}

/// Creates the web/stub [VinOcrService].
VinOcrService createPlatformVinOcrService() => const UnsupportedVinOcrService();
