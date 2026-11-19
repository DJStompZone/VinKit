import 'package:flutter_test/flutter_test.dart';
import 'package:vinkit_app/services/vin_validator.dart';

/// Unit tests for [VinValidator].
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

  group('VinValidator.extractFromBarcode', () {
    test('extracts valid 17-character VIN from Code 128 or Code 39 payload', () {
      expect(
        validator.extractFromBarcode('1FM5K8GCXNGA77516'),
        '1FM5K8GCXNGA77516',
      );
    });

    test('strips Code 39 sentinel asterisks', () {
      expect(
        validator.extractFromBarcode('*1HGCM82633A004352*'),
        '1HGCM82633A004352',
      );
    });

    test('strips legacy 18-character Code 39 leading I prefix', () {
      expect(
        validator.extractFromBarcode('I1FM5K8GCXNGA77516'),
        '1FM5K8GCXNGA77516',
      );
      expect(
        validator.extractFromBarcode('*i1hgcm82633a004352*'),
        '1HGCM82633A004352',
      );
    });

    test('returns null for non-VIN barcodes or invalid characters', () {
      expect(validator.extractFromBarcode(null), isNull);
      expect(validator.extractFromBarcode('012345678905'), isNull);
      expect(validator.extractFromBarcode('I1FM5K8GCXOGA77516'), isNull);
      expect(validator.extractFromBarcode('X1FM5K8GCXNGA77516'), isNull);
    });
  });
}
