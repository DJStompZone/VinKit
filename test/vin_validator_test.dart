import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinkit_app/services/vin_ocr_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';

/// Unit tests for [VinValidator] and [VinOcrResult].
void main() {
  const validator = VinValidator();

  group('VinValidator.validate', () {
    test('accepts standard 17-character alphanumeric VIN and normalizes case', () {
      final result = validator.validate(' 1fm5k8gcxnga77516 ');
      expect(result.isValid, isTrue);
      expect(result.normalizedVin, '1FM5K8GCXNGA77516');
      expect(result.errorMessage, isNull);
    });

    test('normalizes hyphens and internal whitespace before validating', () {
      final result = validator.validate('1HGCM-82633-A004352');
      expect(result.isValid, isTrue);
      expect(result.normalizedVin, '1HGCM82633A004352');
    });

    test('rejects empty input', () {
      final result = validator.validate('   ');
      expect(result.isValid, isFalse);
      expect(result.normalizedVin, isEmpty);
      expect(result.errorMessage, isNotNull);
    });

    test('rejects strings shorter or longer than 17 characters', () {
      final shortResult = validator.validate('1FM5K8GCXNGA7751');
      final longResult = validator.validate('1FM5K8GCXNGA775169');

      expect(shortResult.isValid, isFalse);
      expect(shortResult.errorMessage, contains('16/17'));
      expect(longResult.isValid, isFalse);
      expect(longResult.errorMessage, contains('18/17'));
    });

    test('rejects forbidden letters I, O, and Q', () {
      for (final forbidden in const <String>['I', 'O', 'Q', 'i', 'o', 'q']) {
        final candidate = '1FM5K8GCXNGA7751$forbidden';
        final result = validator.validate(candidate);
        expect(result.isValid, isFalse, reason: 'Failed to reject $forbidden');
        expect(result.errorMessage, contains('I, O, or Q'));
      }
    });

    test('rejects punctuation and special symbols', () {
      final result = validator.validate('1FM5K8GCXNGA7751!');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('A–Z'));
    });
  });

  group('VinValidator.hasValidCheckDigit', () {
    test('verifies ISO 3779 check digits accurately', () {
      expect(validator.hasValidCheckDigit('1FM5K8GCXNGA77516'), isTrue);
      expect(validator.hasValidCheckDigit('1HGCM82633A004352'), isTrue);
      expect(validator.hasValidCheckDigit('5NPD84LF0KH412345'), isTrue);
      expect(validator.hasValidCheckDigit('1FM5K8GC9NGA77516'), isFalse);
      expect(validator.hasValidCheckDigit('5NPD84LF5KH412345'), isFalse);
    });
  });

  group('VinValidator.extractFromBarcode', () {
    test('extracts valid 17-character VIN from Code 128 or Code 39 payload', () {
      expect(
        validator.extractFromBarcode('1FM5K8GCXNGA77516'),
        '1FM5K8GCXNGA77516',
      );
      expect(
        validator.extractFromBarcode(
          '1FM5K8GCXNGA77516',
          strictness: VinScanStrictness.strict,
        ),
        '1FM5K8GCXNGA77516',
      );
    });

    test('strips Code 39 sentinel asterisks', () {
      expect(
        validator.extractFromBarcode(
          '*1HGCM82633A004352*',
          strictness: VinScanStrictness.strict,
        ),
        '1HGCM82633A004352',
      );
    });

    test('strips legacy 18-character Code 39 leading I prefix in both modes', () {
      expect(
        validator.extractFromBarcode(
          'I1FM5K8GCXNGA77516',
          strictness: VinScanStrictness.strict,
        ),
        '1FM5K8GCXNGA77516',
      );
      expect(
        validator.extractFromBarcode(
          '*i1hgcm82633a004352*',
          strictness: VinScanStrictness.strict,
        ),
        '1HGCM82633A004352',
      );
    });

    test('handles Elantra trailing A in Normal mode and rejects in Strict mode', () {
      const elantraBarcode = '5NPD84LF0KH412345A';

      expect(
        validator.extractFromBarcode(
          elantraBarcode,
          strictness: VinScanStrictness.normal,
        ),
        '5NPD84LF0KH412345',
      );
      expect(
        validator.extractFromBarcode(
          elantraBarcode,
          strictness: VinScanStrictness.strict,
        ),
        isNull,
      );
    });

    test('handles extra leading character in Normal mode and rejects in Strict mode', () {
      expect(
        validator.extractFromBarcode(
          'X1FM5K8GCXNGA77516',
          strictness: VinScanStrictness.normal,
        ),
        '1FM5K8GCXNGA77516',
      );
      expect(
        validator.extractFromBarcode(
          'X1FM5K8GCXNGA77516',
          strictness: VinScanStrictness.strict,
        ),
        isNull,
      );
    });

    test('extracts embedded VIN from 2D barcode payloads in Normal mode only', () {
      const twoDPayload = 'MODEL:ELANTRA;VIN:5NPD84LF0KH412345A;TRIM:SEL';
      const concatenatedPayload = '0011FM5K8GCXNGA77516XYZ';

      expect(
        validator.extractFromBarcode(
          twoDPayload,
          strictness: VinScanStrictness.normal,
        ),
        '5NPD84LF0KH412345',
      );
      expect(
        validator.extractFromBarcode(
          concatenatedPayload,
          strictness: VinScanStrictness.normal,
        ),
        '1FM5K8GCXNGA77516',
      );
      expect(
        validator.extractFromBarcode(
          twoDPayload,
          strictness: VinScanStrictness.strict,
        ),
        isNull,
      );
      expect(
        validator.extractFromBarcode(
          concatenatedPayload,
          strictness: VinScanStrictness.strict,
        ),
        isNull,
      );
    });

    test('returns null for non-VIN barcodes or invalid characters', () {
      expect(validator.extractFromBarcode(null), isNull);
      expect(validator.extractFromBarcode('012345678905'), isNull);
      expect(
        validator.extractFromBarcode(
          'I1FM5K8GCXOGA77516',
          strictness: VinScanStrictness.strict,
        ),
        isNull,
      );
      expect(
        validator.extractFromBarcode(
          'NOTAVALIDBARCODE99999',
          strictness: VinScanStrictness.normal,
        ),
        isNull,
      );
    });
  });

  group('VinValidator.extractFromOcrText', () {
    test('extracts labeled and spaced plaintext VINs in both modes', () {
      final normalResult = validator.extractFromOcrText(
        const <String>['MFD BY FORD', 'VIN: 1FM5K 8GCX NGA77516'],
        strictness: VinScanStrictness.normal,
      );
      final strictResult = validator.extractFromOcrText(
        const <String>['VIN: 1FM5K8GCXNGA77516'],
        strictness: VinScanStrictness.strict,
      );

      expect(normalResult.vin, '1FM5K8GCXNGA77516');
      expect(normalResult.usedFuzzyRepair, isFalse);
      expect(strictResult.vin, '1FM5K8GCXNGA77516');
    });

    test('normalizes OCR I/O/Q/l misreads in Normal mode and rejects in Strict mode', () {
      final normalResult = validator.extractFromOcrText(
        const <String>['lHGCM82633AOO4352'],
        strictness: VinScanStrictness.normal,
      );
      final strictResult = validator.extractFromOcrText(
        const <String>['lHGCM82633AOO4352'],
        strictness: VinScanStrictness.strict,
      );

      expect(normalResult.vin, '1HGCM82633A004352');
      expect(strictResult.vin, isNull);
    });

    test('repairs single OCR lookalike glyph via ISO 3779 check digit in Normal mode', () {
      // '5' misread as 'S' in 1FM5K8GCXNGA77516.
      final normalResult = validator.extractFromOcrText(
        const <String>['1FMSK8GCXNGA77516'],
        strictness: VinScanStrictness.normal,
      );
      final strictResult = validator.extractFromOcrText(
        const <String>['1FMSK8GCXNGA77516'],
        strictness: VinScanStrictness.strict,
      );

      expect(normalResult.vin, '1FM5K8GCXNGA77516');
      expect(normalResult.usedFuzzyRepair, isTrue);
      // Strict mode does not perform fuzzy repair.
      expect(strictResult.vin, isNot('1FM5K8GCXNGA77516'));
    });

    test('returns bestSnippet when OCR only captures a partial VIN', () {
      final result = validator.extractFromOcrText(
        const <String>['GVWR 5200 LBS', '5NPD84LF0KH4123'],
        strictness: VinScanStrictness.normal,
      );

      expect(result.vin, isNull);
      expect(result.bestSnippet, '5NPD84LF0KH4123');
    });
  });

  group('VinOcrResult.orderedLines', () {
    test('merges horizontally aligned split VIN fragments into a single line', () {
      const result = VinOcrResult(
        blocks: <VinOcrTextBlock>[
          VinOcrTextBlock(
            text: 'XNGA77516',
            confidence: 0.92,
            boundingBox: Rect.fromLTWH(210, 102, 160, 32),
          ),
          VinOcrTextBlock(
            text: '1FM5K8GC',
            confidence: 0.95,
            boundingBox: Rect.fromLTWH(40, 100, 150, 32),
          ),
        ],
      );

      final extraction = validator.extractFromOcrText(result.orderedLines);
      expect(extraction.vin, '1FM5K8GCXNGA77516');
    });
  });
}
