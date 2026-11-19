/// Holds the outcome of validating a candidate VIN string.
class VinValidationResult {
  /// Creates a valid [VinValidationResult] for [normalizedVin].
  const VinValidationResult.valid({required this.normalizedVin})
      : isValid = true,
        errorMessage = null;

  /// Creates an invalid [VinValidationResult] with an explanatory [errorMessage].
  const VinValidationResult.invalid({
    required this.normalizedVin,
    required this.errorMessage,
  }) : isValid = false;

  /// Whether the candidate VIN satisfies all ISO 3779 character and length rules.
  final bool isValid;

  /// Uppercased VIN string after stripping whitespace and hyphens.
  final String normalizedVin;

  /// Human-readable validation failure reason, or `null` when valid.
  final String? errorMessage;
}

/// Validates and extracts 17-character automotive VIN strings from manual input
/// and Code 39 / Code 128 barcode payloads.
class VinValidator {
  /// Creates a [VinValidator] instance.
  const VinValidator();

  /// Required character length for standard post-1981 automotive VINs.
  static const int vinLength = 17;

  static final RegExp _validVinPattern = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');
  static final RegExp _forbiddenLettersPattern = RegExp(r'[IOQ]');
  static final RegExp _disallowedCharsPattern = RegExp(r'[^A-Z0-9]');
  static final RegExp _separatorPattern = RegExp(r'[\s-]+');
  static final RegExp _wrappingAsteriskPattern = RegExp(r'^\*+|\*+$');

  /// Normalizes user-typed or pasted input by trimming, removing spaces and
  /// hyphens, and converting characters to uppercase.
  String normalizeManualInput(String raw) {
    return raw.trim().replaceAll(_separatorPattern, '').toUpperCase();
  }

  /// Validates [raw] input against automotive VIN rules before network calls.
  VinValidationResult validate(String raw) {
    final normalized = normalizeManualInput(raw);
    if (normalized.isEmpty) {
      return const VinValidationResult.invalid(
        normalizedVin: '',
        errorMessage: 'Enter a 17-character VIN.',
      );
    }

    if (_forbiddenLettersPattern.hasMatch(normalized)) {
      return VinValidationResult.invalid(
        normalizedVin: normalized,
        errorMessage: 'VINs cannot contain the letters I, O, or Q.',
      );
    }

    if (_disallowedCharsPattern.hasMatch(normalized)) {
      return VinValidationResult.invalid(
        normalizedVin: normalized,
        errorMessage:
            'VIN must contain only letters A–Z (except I, O, Q) and digits 0–9.',
      );
    }

    if (normalized.length != vinLength) {
      return VinValidationResult.invalid(
        normalizedVin: normalized,
        errorMessage:
            'VIN must be exactly $vinLength characters (currently ${normalized.length}/$vinLength).',
      );
    }

    if (!_validVinPattern.hasMatch(normalized)) {
      return VinValidationResult.invalid(
        normalizedVin: normalized,
        errorMessage: 'Invalid VIN format.',
      );
    }

    return VinValidationResult.valid(normalizedVin: normalized);
  }

  /// Returns `true` if [raw] normalizes to a valid 17-character VIN.
  bool isValid(String raw) => validate(raw).isValid;

  /// Extracts and validates a 17-character VIN from a raw barcode [raw] string.
  ///
  /// Strips Code 39 sentinel asterisks and removes the legacy leading `I`
  /// prefix present on 18-character automotive Code 39 VIN barcodes.
  String? extractFromBarcode(String? raw) {
    if (raw == null) {
      return null;
    }

    var candidate = raw
        .trim()
        .replaceAll(_wrappingAsteriskPattern, '')
        .replaceAll(_separatorPattern, '')
        .toUpperCase();

    if (candidate.length == vinLength + 1 && candidate.startsWith('I')) {
      candidate = candidate.substring(1);
    }

    final result = validate(candidate);
    return result.isValid ? result.normalizedVin : null;
  }
}
