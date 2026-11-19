/// Controls how strictly scanned barcodes and OCR text are matched against
/// 17-character automotive VIN rules.
enum VinScanStrictness {
  /// Flexible shop-floor matching: handles extra leading/trailing barcode
  /// characters (such as manufacturer suffix letters), embedded VINs inside
  /// longer 2D barcode payloads, and check-digit-verified OCR character repair.
  normal,

  /// Strict matching: requires an exact 17-character VIN (stripping only
  /// whitespace, hyphens, Code 39 `*` sentinels, and legacy leading `I` on
  /// 18-character Code 39 barcodes) with no fuzzy OCR substitutions.
  strict,
}

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

/// Outcome of attempting to extract a VIN from recognized OCR text lines.
class VinOcrExtractionResult {
  /// Creates a [VinOcrExtractionResult].
  const VinOcrExtractionResult({
    this.vin,
    this.bestSnippet,
    this.usedFuzzyRepair = false,
  });

  /// Extracted valid 17-character VIN, or `null` when none was found.
  final String? vin;

  /// Best VIN-like text fragment observed when no valid VIN was extracted,
  /// useful for prefilling manual entry.
  final String? bestSnippet;

  /// Whether [vin] required single-character check-digit repair on ambiguous
  /// OCR glyphs (for example `S`/`5` or `B`/`8`).
  final bool usedFuzzyRepair;
}

/// Validates and extracts 17-character automotive VIN strings from manual input,
/// linear/2D barcode payloads, and OCR text output.
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
  static final RegExp _nonAlphanumericPattern = RegExp(r'[^A-Z0-9]+');
  static final RegExp _hasDigitPattern = RegExp(r'[0-9]');
  static final RegExp _hasLetterPattern = RegExp(r'[A-Z]');
  static final RegExp _vinLabelPrefixPattern = RegExp(
    r'^(?:VIN|V\.?I\.?N\.?|CHASSIS|SERIAL)(?:\s*(?:NO\.?|NUM(?:BER)?|#))?[\s:=/-]*',
    caseSensitive: false,
  );
  static final RegExp _vinLabelInlinePattern = RegExp(
    r'(?:VIN|V\.?I\.?N\.?)[\s:=#-]+([A-Z0-9\s-]{17,24})',
    caseSensitive: false,
  );

  static const Map<String, int> _iso3779Values = <String, int>{
    '0': 0,
    '1': 1,
    '2': 2,
    '3': 3,
    '4': 4,
    '5': 5,
    '6': 6,
    '7': 7,
    '8': 8,
    '9': 9,
    'A': 1,
    'B': 2,
    'C': 3,
    'D': 4,
    'E': 5,
    'F': 6,
    'G': 7,
    'H': 8,
    'J': 1,
    'K': 2,
    'L': 3,
    'M': 4,
    'N': 5,
    'P': 7,
    'R': 9,
    'S': 2,
    'T': 3,
    'U': 4,
    'V': 5,
    'W': 6,
    'X': 7,
    'Y': 8,
    'Z': 9,
  };

  static const List<int> _iso3779Weights = <int>[
    8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2,
  ];

  static const Set<String> _validModelYearChars = <String>{
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P',
    'R', 'S', 'T', 'V', 'W', 'X', 'Y', '1', '2', '3', '4', '5', '6', '7',
    '8', '9',
  };

  static const Set<String> _commonWmiFirstChars = <String>{
    '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'A', 'J', 'K', 'L', 'M', 'N', 'P', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  };

  static const Map<String, List<String>> _ocrConfusionAlternatives =
      <String, List<String>>{
    '0': <String>['D', '8'],
    'D': <String>['0'],
    '1': <String>['7', 'T', 'J'],
    '7': <String>['1', 'Z'],
    '2': <String>['Z'],
    'Z': <String>['2', '7'],
    '5': <String>['S', '6'],
    'S': <String>['5'],
    '6': <String>['G', '5'],
    'G': <String>['6', 'C'],
    '8': <String>['B', '0', '9'],
    'B': <String>['8'],
    '9': <String>['8', 'G'],
    'U': <String>['V'],
    'V': <String>['U'],
    'M': <String>['N'],
    'N': <String>['M'],
    'E': <String>['F'],
    'F': <String>['E'],
    'C': <String>['G'],
    'K': <String>['X'],
    'X': <String>['K'],
    'T': <String>['1'],
  };

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

  /// Returns `true` when [vin] satisfies the ISO 3779 position-9 check digit.
  bool hasValidCheckDigit(String vin) {
    if (!_validVinPattern.hasMatch(vin)) {
      return false;
    }

    var sum = 0;
    for (var i = 0; i < vinLength; i++) {
      final value = _iso3779Values[vin[i]];
      if (value == null) {
        return false;
      }
      sum += value * _iso3779Weights[i];
    }

    final remainder = sum % 11;
    final expected = remainder == 10 ? 'X' : '$remainder';
    return vin[8] == expected;
  }

  /// Extracts and validates a 17-character VIN from a raw barcode [raw] string.
  ///
  /// In [VinScanStrictness.strict] mode, strips only Code 39 sentinel
  /// asterisks, whitespace/hyphens, and the legacy leading `I` prefix on
  /// 18-character Code 39 barcodes.
  ///
  /// In [VinScanStrictness.normal] mode (the default), also handles extra
  /// leading/trailing characters (such as manufacturer suffix letters like
  /// Hyundai's appended `A`) and embedded VINs inside longer 2D barcode
  /// payloads, ranking candidates using ISO 3779 check-digit and structural
  /// scoring.
  String? extractFromBarcode(
    String? raw, {
    VinScanStrictness strictness = VinScanStrictness.normal,
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final strictCandidate = _extractStrictBarcode(raw);
    if (strictCandidate != null) {
      return strictCandidate;
    }

    if (strictness == VinScanStrictness.strict) {
      return null;
    }

    return _extractFlexibleBarcode(raw);
  }

  /// Extracts a 17-character VIN from recognized OCR text lines.
  ///
  /// In [VinScanStrictness.normal] mode, normalizes forbidden OCR confusions
  /// (`I`/`l`/`|` -> `1`, `O`/`Q` -> `0`) and attempts single-character
  /// ISO 3779 check-digit-verified repair on common lookalike glyphs.
  ///
  /// In [VinScanStrictness.strict] mode, requires an exact valid 17-character
  /// VIN without character substitutions.
  VinOcrExtractionResult extractFromOcrText(
    List<String> lines, {
    VinScanStrictness strictness = VinScanStrictness.normal,
  }) {
    if (lines.isEmpty) {
      return const VinOcrExtractionResult();
    }

    _ScoredCandidate? bestMatch;
    String? bestSnippet;

    void consider(String candidate, {required int bonus, bool repaired = false}) {
      if (!_validVinPattern.hasMatch(candidate)) {
        return;
      }
      final score = _scoreVinCandidate(candidate) + bonus;
      if (bestMatch == null || score > bestMatch!.score) {
        bestMatch = _ScoredCandidate(
          vin: candidate,
          score: score,
          usedFuzzyRepair: repaired,
        );
      }
    }

    void trackSnippet(String raw) {
      final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (cleaned.length < 10 || cleaned.length > 22) {
        return;
      }
      if (!_hasDigitPattern.hasMatch(cleaned) ||
          !_hasLetterPattern.hasMatch(cleaned)) {
        return;
      }
      if (bestSnippet == null) {
        bestSnippet = cleaned;
        return;
      }
      final currentDistance = (bestSnippet!.length - vinLength).abs();
      final nextDistance = (cleaned.length - vinLength).abs();
      if (nextDistance < currentDistance) {
        bestSnippet = cleaned;
      }
    }

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      // 1. Check inline "VIN: ..." matches first before general cleanup.
      for (final match in _vinLabelInlinePattern.allMatches(trimmed)) {
        final labeledSegment = match.group(1);
        if (labeledSegment != null) {
          _evaluateOcrSegment(
            labeledSegment,
            strictness: strictness,
            baseBonus: 35,
            consider: consider,
            trackSnippet: trackSnippet,
          );
        }
      }

      // 2. Strip leading VIN/Chassis label prefixes on the whole line.
      final withoutLabel = trimmed.replaceFirst(_vinLabelPrefixPattern, '').trim();
      final hadLabel = withoutLabel.length != trimmed.length;
      _evaluateOcrSegment(
        withoutLabel,
        strictness: strictness,
        baseBonus: hadLabel ? 25 : 0,
        consider: consider,
        trackSnippet: trackSnippet,
      );

      // 3. Also evaluate whitespace-delimited tokens individually in case a
      // line mixes unrelated metadata with a standalone VIN token.
      for (final token in withoutLabel.split(RegExp(r'\s+'))) {
        if (token.length >= 14) {
          _evaluateOcrSegment(
            token,
            strictness: strictness,
            baseBonus: 10,
            consider: consider,
            trackSnippet: trackSnippet,
          );
        }
      }
    }

    if (bestMatch != null) {
      return VinOcrExtractionResult(
        vin: bestMatch!.vin,
        usedFuzzyRepair: bestMatch!.usedFuzzyRepair,
      );
    }

    return VinOcrExtractionResult(bestSnippet: bestSnippet);
  }

  String? _extractStrictBarcode(String raw) {
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

  String? _extractFlexibleBarcode(String raw) {
    final upper = raw.trim().toUpperCase();
    final candidates = <_ScoredCandidate>[];

    void addCandidate(
      String window, {
      required int bonus,
      required bool requireCheckDigit,
    }) {
      if (!_validVinPattern.hasMatch(window)) {
        return;
      }
      final validCheck = hasValidCheckDigit(window);
      if (requireCheckDigit && !validCheck) {
        return;
      }
      if (!_hasDigitPattern.hasMatch(window) ||
          !_hasLetterPattern.hasMatch(window)) {
        return;
      }
      candidates.add(
        _ScoredCandidate(
          vin: window,
          score: _scoreVinCandidate(window) + bonus,
        ),
      );
    }

    // Check inline "VIN: ..." labeled segments inside 2D barcode payloads.
    for (final match in _vinLabelInlinePattern.allMatches(upper)) {
      final segment =
          match.group(1)?.replaceAll(_nonAlphanumericPattern, '') ?? '';
      if (segment.length == vinLength) {
        addCandidate(segment, bonus: 40, requireCheckDigit: false);
      } else if (segment.length == vinLength + 1) {
        addCandidate(segment.substring(0, vinLength),
            bonus: 35, requireCheckDigit: false);
        addCandidate(segment.substring(1), bonus: 30, requireCheckDigit: false);
      } else if (segment.length > vinLength + 1) {
        for (var i = 0; i <= segment.length - vinLength; i++) {
          addCandidate(
            segment.substring(i, i + vinLength),
            bonus: i == 0 ? 30 : 20,
            requireCheckDigit: true,
          );
        }
      }
    }

    // Evaluate separator-stripped payload (handles whitespace/hyphens/sentinels
    // and common 18-character manufacturer barcodes such as Elantra trailing 'A').
    final stripped = upper
        .replaceAll(_wrappingAsteriskPattern, '')
        .replaceAll(_nonAlphanumericPattern, '');

    if (stripped.length == vinLength) {
      addCandidate(stripped, bonus: 25, requireCheckDigit: false);
    } else if (stripped.length == vinLength + 1) {
      // Single extra trailing or leading character (e.g. '5NPD84LF0KH412345A').
      addCandidate(
        stripped.substring(0, vinLength),
        bonus: 20,
        requireCheckDigit: false,
      );
      addCandidate(
        stripped.substring(1),
        bonus: 15,
        requireCheckDigit: false,
      );
    } else if (stripped.length > vinLength + 1 && stripped.length <= 256) {
      for (var i = 0; i <= stripped.length - vinLength; i++) {
        addCandidate(
          stripped.substring(i, i + vinLength),
          bonus: i == 0 ? 10 : 0,
          requireCheckDigit: true,
        );
      }
    }

    // Also inspect individual alphanumeric tokens in multi-field 2D barcodes
    // (DataMatrix / PDF417 / QR).
    final tokens = upper.split(_nonAlphanumericPattern);
    for (final token in tokens) {
      if (token.length < vinLength) {
        continue;
      }
      if (token.length == vinLength) {
        addCandidate(token, bonus: 25, requireCheckDigit: tokens.length > 1);
      } else if (token.length == vinLength + 1) {
        addCandidate(
          token.substring(0, vinLength),
          bonus: 20,
          requireCheckDigit: tokens.length > 2,
        );
        addCandidate(
          token.substring(1),
          bonus: 15,
          requireCheckDigit: tokens.length > 2,
        );
      } else if (token.length <= 128) {
        for (var i = 0; i <= token.length - vinLength; i++) {
          addCandidate(
            token.substring(i, i + vinLength),
            bonus: i == 0 ? 10 : 0,
            requireCheckDigit: true,
          );
        }
      }
    }

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.first.vin;
  }

  void _evaluateOcrSegment(
    String rawSegment, {
    required VinScanStrictness strictness,
    required int baseBonus,
    required void Function(String candidate, {required int bonus, bool repaired})
        consider,
    required void Function(String raw) trackSnippet,
  }) {
    final compactRaw = rawSegment
        .trim()
        .replaceAll(_wrappingAsteriskPattern, '')
        .replaceAllMapped(RegExp(r'[\s\-_.:/\\|]+'), (match) {
      // Preserve single vertical bar '|' in Normal mode as a potential OCR '1'.
      return strictness == VinScanStrictness.normal &&
              match.group(0) == '|'
          ? '1'
          : '';
    });

    final preCaseNormalized = strictness == VinScanStrictness.normal
        ? compactRaw.replaceAll('l', '1')
        : compactRaw;
    final upperRaw = preCaseNormalized.toUpperCase();
    trackSnippet(upperRaw);

    // Strict OCR mode: no character substitutions; require exact 17-char valid
    // VIN (or check-digit-validated 17-char window if embedded in longer text).
    if (strictness == VinScanStrictness.strict) {
      final strictClean = upperRaw.replaceAll(_nonAlphanumericPattern, '');
      if (strictClean.length == vinLength &&
          _validVinPattern.hasMatch(strictClean)) {
        if (hasValidCheckDigit(strictClean) || baseBonus >= 25) {
          consider(strictClean, bonus: baseBonus + 20);
        } else if (_hasDigitPattern.hasMatch(strictClean) &&
            _hasLetterPattern.hasMatch(strictClean) &&
            _validModelYearChars.contains(strictClean[9])) {
          consider(strictClean, bonus: baseBonus);
        }
      } else if (strictClean.length > vinLength && strictClean.length <= 64) {
        for (var i = 0; i <= strictClean.length - vinLength; i++) {
          final window = strictClean.substring(i, i + vinLength);
          if (_validVinPattern.hasMatch(window) && hasValidCheckDigit(window)) {
            consider(window, bonus: baseBonus + (i == 0 ? 10 : 0));
          }
        }
      }
      return;
    }

    // Normal OCR mode: normalize forbidden VIN letters (I -> 1, O/Q -> 0)
    // because real VINs never contain I, O, or Q.
    final normalized = _normalizeOcrForbiddenChars(upperRaw)
        .replaceAll(_nonAlphanumericPattern, '');
    trackSnippet(normalized);

    if (normalized.length < vinLength || normalized.length > 64) {
      return;
    }

    final windowCount = normalized.length - vinLength + 1;
    for (var i = 0; i < windowCount; i++) {
      final window = normalized.substring(i, i + vinLength);
      if (!_validVinPattern.hasMatch(window)) {
        continue;
      }
      if (!_hasDigitPattern.hasMatch(window) ||
          !_hasLetterPattern.hasMatch(window)) {
        continue;
      }

      final positionBonus =
          baseBonus + (normalized.length == vinLength ? 25 : (i == 0 ? 10 : 0));

      if (hasValidCheckDigit(window)) {
        consider(window, bonus: positionBonus + 30);
        continue;
      }

      // Try single-character OCR confusion repair verified by ISO 3779 check digit.
      final repaired = _repairSingleOcrChar(window);
      if (repaired != null) {
        consider(repaired, bonus: positionBonus + 10, repaired: true);
        continue;
      }

      // Allow clean exact-length (or 18-char single-extra-char) non-NA VINs
      // when structure strongly matches an automotive VIN.
      if (normalized.length <= vinLength + 1 &&
          _validModelYearChars.contains(window[9]) &&
          _countDigits(window.substring(11)) >= 4) {
        consider(window, bonus: positionBonus - 20);
      }
    }
  }

  String _normalizeOcrForbiddenChars(String input) {
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      switch (ch) {
        case 'I':
        case 'l':
        case '|':
          buffer.write('1');
        case 'O':
        case 'Q':
          buffer.write('0');
        default:
          buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  /// Attempts to repair a single OCR-confused character in [candidate] so that
  /// it satisfies the ISO 3779 check digit, preferring high-likelihood visual
  /// confusions (`S<->5`, `B<->8`, `D<->0`, `G<->6`, `Z<->2`) and preserving
  /// the WMI prefix (positions 0–2) whenever possible.
  String? _repairSingleOcrChar(String candidate) {
    String? best;
    var bestScore = -10000;

    for (var i = 0; i < vinLength; i++) {
      final original = candidate[i];
      final replacements = _ocrConfusionAlternatives[original];
      if (replacements == null) {
        continue;
      }

      for (final replacement in replacements) {
        final patched =
            '${candidate.substring(0, i)}$replacement${candidate.substring(i + 1)}';
        if (!hasValidCheckDigit(patched)) {
          continue;
        }
        final pairBonus = _ocrRepairPairBonus(original, replacement);
        // Prefer preserving WMI country/manufacturer prefix (indices 0..2) and
        // check digit (index 8) when an equally valid visual repair exists.
        final positionAdjustment = i < 3 ? -12 : (i == 8 ? -5 : 0);
        final score =
            _scoreVinCandidate(patched) + pairBonus + positionAdjustment;
        if (score > bestScore) {
          bestScore = score;
          best = patched;
        }
      }
    }

    return best;
  }

  int _ocrRepairPairBonus(String from, String to) {
    const highLikelihoodPairs = <String>{
      'S5', '5S',
      'B8', '8B',
      'D0', '0D',
      'G6', '6G',
      'Z2', '2Z',
    };
    const mediumLikelihoodPairs = <String>{
      'UV', 'VU',
      '08', '80',
      '89', '98',
      '56', '65',
      'MN', 'NM',
    };
    final pair = '$from$to';
    if (highLikelihoodPairs.contains(pair)) {
      return 25;
    }
    if (mediumLikelihoodPairs.contains(pair)) {
      return 12;
    }
    return 0;
  }

  int _scoreVinCandidate(String vin) {
    var score = 0;
    if (hasValidCheckDigit(vin)) {
      score += 100;
    }
    if (_validModelYearChars.contains(vin[9])) {
      score += 20;
    }
    if (_commonWmiFirstChars.contains(vin[0])) {
      score += 15;
    }

    final serialTail = vin.substring(11);
    final tailDigits = _countDigits(serialTail);
    if (tailDigits == 6) {
      score += 35;
    } else if (tailDigits == 5) {
      score += 28;
    } else if (tailDigits >= 4) {
      score += 18;
    }

    // Last 4 characters of passenger vehicle VINs are almost always numeric.
    if (_countDigits(vin.substring(13)) == 4) {
      score += 15;
    }

    if (!_hasDigitPattern.hasMatch(vin) || !_hasLetterPattern.hasMatch(vin)) {
      score -= 40;
    }
    return score;
  }

  int _countDigits(String value) {
    var count = 0;
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code >= 48 && code <= 57) {
        count++;
      }
    }
    return count;
  }
}

class _ScoredCandidate {
  const _ScoredCandidate({
    required this.vin,
    required this.score,
    this.usedFuzzyRepair = false,
  });

  final String vin;
  final int score;
  final bool usedFuzzyRepair;
}
