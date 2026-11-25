import 'dart:math' as math;
import 'dart:ui';

import 'package:vinkit_app/services/vin_ocr_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';

/// Snapshot of in-progress multi-frame VIN assembly for live OCR feedback UI.
class VinAssemblyProgress {
  /// Creates a [VinAssemblyProgress].
  const VinAssemblyProgress({
    required this.slots,
    required this.confirmedSlots,
    required this.filledCount,
    required this.confirmedCount,
    required this.bestPartialText,
  });

  /// Length-17 list of best character estimates per slot (`null` = not yet read).
  final List<String?> slots;

  /// Length-17 list indicating whether each slot has multi-frame confirmation.
  final List<bool> confirmedSlots;

  /// Number of populated slots out of 17.
  final int filledCount;

  /// Number of multi-frame confirmed slots out of 17.
  final int confirmedCount;

  /// Compact alphanumeric preview of the assembled characters (for manual edit).
  final String bestPartialText;
}

/// Result of feeding a single live OCR frame into [VinFrameAssembler].
class VinFrameAssemblyResult {
  /// Creates a [VinFrameAssemblyResult].
  const VinFrameAssemblyResult({
    this.vin,
    this.progress,
    this.assembledFromMultipleFrames = false,
    this.bestSnippet,
  });

  /// Validated 17-character VIN when locked, or `null` if still assembling.
  final String? vin;

  /// Live 17-slot assembly progress when actively piecing together fragments.
  final VinAssemblyProgress? progress;

  /// Whether [vin] was reconstructed across multiple partial/glared frames.
  final bool assembledFromMultipleFrames;

  /// Best raw VIN-like snippet observed in the current frame for manual fallback.
  final String? bestSnippet;
}

/// Accumulates partial and glare-corrupted OCR reads across recent live camera
/// frames to reconstruct a verified 17-character automotive VIN.
///
/// Designed exclusively for Live OCR mode:
/// - Clean single-frame VINs still lock immediately with zero added delay.
/// - Localized windshield glare spots are solved via per-slot character voting
///   and same-row gap estimation.
/// - Panning across a VIN in overlapping chunks is solved via multi-hypothesis
///   overlap alignment (requiring >= 3 non-trivial overlapping characters).
/// - Unrelated door-jamb / sticker text is isolated in separate tracks and
///   filtered via automotive stopwords + VIN structural/check-digit rules.
/// - Manufacturer quirks (such as 18-character VINs with an extra trailing
///   letter or leading `I`) are handled via sliding 17-character window scoring.
class VinFrameAssembler {
  /// Creates a [VinFrameAssembler].
  VinFrameAssembler({
    this.validator = const VinValidator(),
    DateTime Function()? clock,
    this.windowDuration = const Duration(seconds: 6),
    this.staleHypothesisDuration = const Duration(milliseconds: 3500),
    this.maxHypotheses = 8,
  }) : _clock = clock ?? DateTime.now;

  /// Validator used for ISO 3779 check-digit verification and single-frame fast path.
  final VinValidator validator;
  final DateTime Function() _clock;

  /// Maximum age of observations kept in the rolling buffer.
  final Duration windowDuration;

  /// Maximum idle time before an unreinforced hypothesis is evicted.
  final Duration staleHypothesisDuration;

  /// Maximum number of concurrent alignment hypotheses tracked at once.
  final int maxHypotheses;

  static const int _vinLength = VinValidator.vinLength;
  static const int _maxHypothesisSpan = 20;
  static const int _minFragmentLength = 4;
  static const int _minSeedLength = 5;
  static const int _minProgressSlotsToDisplay = 6;

  static final RegExp _validVinPattern = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');
  static final RegExp _nonAlphanumericPattern = RegExp(r'[^A-Z0-9]+');
  static final RegExp _wrappingAsteriskPattern = RegExp(r'^\*+|\*+$');
  static final RegExp _hasDigitPattern = RegExp(r'[0-9]');
  static final RegExp _hasLetterPattern = RegExp(r'[A-Z]');
  static final RegExp _forbiddenLettersPattern = RegExp(r'[IOQ]');
  static final RegExp _measurementPattern = RegExp(
    r'^\d+(?:PSI|KPA|LB|LBS|KG|KGS|MM|CM|IN|MPH|KMH)$',
  );
  static final RegExp _vinLabelPrefixPattern = RegExp(
    r'^(?:VIN|V\.?I\.?N\.?|CHASSIS|SERIAL)(?:\s*(?:NO\.?|NUM(?:BER)?|#))?[\s:=/-]*',
    caseSensitive: false,
  );
  static final RegExp _vinLabelInlinePattern = RegExp(
    r'(?:VIN|V\.?I\.?N\.?)[\s:=#-]+([A-Z0-9\s-]{5,24})',
    caseSensitive: false,
  );

  static const Set<String> _validModelYearChars = <String>{
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P',
    'R', 'S', 'T', 'V', 'W', 'X', 'Y', '1', '2', '3', '4', '5', '6', '7',
    '8', '9',
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

  /// Common non-VIN automotive door-jamb / windshield label words to ignore.
  static const Set<String> _automotiveStopwords = <String>{
    'GVWR', 'GAWR', 'FRONT', 'REAR', 'TIRE', 'TIRES', 'COLD', 'PRESSURE',
    'PAINT', 'TRIM', 'DATE', 'TYPE', 'MOTOR', 'MOTORS', 'VEHICLE', 'SAFETY',
    'STANDARDS', 'FEDERAL', 'CONFORMS', 'COMPLIES', 'APPLICABLE', 'EFFECT',
    'PASSENGER', 'TRUCK', 'CANADA', 'MEXICO', 'JAPAN', 'KOREA', 'GERMANY',
    'ENGLAND', 'FRANCE', 'ITALY', 'SWEDEN', 'CHINA', 'MADE', 'BUILT',
    'ASSEMBLED', 'MANUFACTURE', 'MANUFACTURED', 'HONDA', 'TOYOTA', 'FORD',
    'CHEVROLET', 'NISSAN', 'HYUNDAI', 'SUBARU', 'MAZDA', 'DODGE', 'JEEP',
    'CHRYSLER', 'VOLKSWAGEN', 'MERCEDES', 'AUDI', 'VOLVO', 'LEXUS', 'ACURA',
    'INFINITI', 'BUICK', 'CADILLAC', 'LINCOLN', 'PONTIAC', 'SATURN', 'SCION',
    'MITSUBISHI', 'SUZUKI', 'ISUZU', 'PORSCHE', 'TESLA', 'RIVIAN', 'GENESIS',
    'MAXLOAD', 'SEATING', 'CAPACITY', 'COMBINED', 'WEIGHT', 'OCCUPANTS',
    'CARGO', 'NEVER', 'EXCEED', 'MANUAL', 'OWNER', 'OWNERS', 'SPARE', 'LOAD',
    'COLOR', 'AXLE', 'TRANS', 'ENGINE', 'CATALYST', 'EMISSION', 'EMISSIONS',
    'CONTROL', 'INFORMATION', 'SHOWN', 'ABOVE', 'BELOW', 'SEE', 'ONLY',
    'WITH', 'FROM', 'THAT', 'THIS', 'FOR', 'THE', 'AND', 'INC', 'CORP',
    'LTD', 'USA', 'MPV', 'SUV', 'SEDAN', 'COUPE', 'CHASSIS', 'SERIAL',
    'NUMBER', 'MODEL', 'YEAR', 'CLASS', 'GROUP', 'FAMILY', 'NOTICE',
    'WARNING', 'CAUTION', 'DANGER', 'AIRBAG', 'BRAKE', 'COOLANT', 'FLUID',
  };

  final List<_VinHypothesis> _hypotheses = <_VinHypothesis>[];
  int _frameCounter = 0;

  /// Clears all accumulated partial OCR hypotheses.
  void reset() {
    _hypotheses.clear();
  }

  /// Processes a live OCR frame and returns either a locked VIN or the current
  /// multi-frame assembly progress.
  VinFrameAssemblyResult addFrame(
    VinOcrResult ocrResult, {
    required VinScanStrictness strictness,
  }) {
    final now = _clock();
    _pruneExpired(now);

    final candidateLines = _buildSingleFrameCandidateLines(ocrResult);

    // 1. Fast path: if this single frame already yields a clean, unrepaired,
    // check-digit-valid VIN, lock immediately and reset the buffer.
    // Fuzzy-repaired single frames are routed through multi-frame voting so
    // localized glare corruption on 2+ characters cannot prematurely lock the
    // wrong VIN via a lucky 1-char check-digit collision.
    final singleFrame = validator.extractFromOcrText(
      candidateLines,
      strictness: strictness,
    );
    if (singleFrame.vin != null &&
        !singleFrame.usedFuzzyRepair &&
        validator.hasValidCheckDigit(singleFrame.vin!)) {
      reset();
      return VinFrameAssemblyResult(
        vin: singleFrame.vin,
        assembledFromMultipleFrames: false,
      );
    }

    // 2. Extract cleaned partial/gapped VIN candidate fragments from this frame.
    final frameId = ++_frameCounter;
    final fragments = _extractFragments(ocrResult, strictness: strictness);
    if (fragments.isEmpty) {
      return VinFrameAssemblyResult(
        progress: _buildBestProgress(),
        bestSnippet: singleFrame.bestSnippet,
      );
    }

    // 3. Align each fragment into existing hypotheses or seed new ones.
    for (final fragment in fragments) {
      _integrateFragment(fragment, frameId: frameId, now: now);
    }

    // Keep hypothesis list bounded by quality + recency.
    _trimHypotheses();

    // 4. Attempt to solve any hypothesis that now spans >= 17 characters.
    final solvedVin = _solveBestVin(strictness: strictness);
    if (solvedVin != null) {
      reset();
      return VinFrameAssemblyResult(
        vin: solvedVin,
        assembledFromMultipleFrames: true,
      );
    }

    return VinFrameAssemblyResult(
      progress: _buildBestProgress(),
      bestSnippet: singleFrame.bestSnippet,
    );
  }

  void _pruneExpired(DateTime now) {
    _hypotheses.removeWhere((hypothesis) {
      if (now.difference(hypothesis.lastUpdated) > staleHypothesisDuration) {
        return true;
      }
      hypothesis.pruneOlderThan(now.subtract(windowDuration));
      return hypothesis.isEmpty;
    });
  }

  void _trimHypotheses() {
    if (_hypotheses.length <= maxHypotheses) {
      return;
    }
    _hypotheses.sort((a, b) => b.rankingScore.compareTo(a.rankingScore));
    _hypotheses.removeRange(maxHypotheses, _hypotheses.length);
  }

  List<_OcrFragment> _extractFragments(
    VinOcrResult result, {
    required VinScanStrictness strictness,
  }) {
    final fragments = <_OcrFragment>[];
    final seenPatterns = <String>{};

    void addFragment(
      String pattern, {
      required double confidence,
      required bool hasVinLabel,
    }) {
      final concreteCount = _countConcreteChars(pattern);
      if (concreteCount < _minFragmentLength || pattern.length > 24) {
        return;
      }
      if (!seenPatterns.add(pattern)) {
        return;
      }
      fragments.add(
        _OcrFragment(
          pattern: pattern,
          concreteCount: concreteCount,
          confidence: confidence.clamp(0.4, 1.0),
          hasVinLabel: hasVinLabel,
        ),
      );
    }

    void processRawText(
      String raw, {
      required double confidence,
      bool forceVinLabel = false,
    }) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return;
      }

      // Check inline "VIN: ..." labeled spans first.
      for (final match in _vinLabelInlinePattern.allMatches(trimmed)) {
        final labeled = match.group(1);
        if (labeled != null) {
          final cleaned = _cleanSegment(labeled, strictness: strictness);
          if (cleaned != null && !_isNoiseFragment(cleaned, hasVinLabel: true)) {
            addFragment(
              cleaned,
              confidence: confidence,
              hasVinLabel: true,
            );
          }
        }
      }

      // Strip leading label prefix and evaluate the full segment.
      final withoutLabel =
          trimmed.replaceFirst(_vinLabelPrefixPattern, '').trim();
      final hadLabel = forceVinLabel || withoutLabel.length != trimmed.length;
      final wholeCleaned = _cleanSegment(withoutLabel, strictness: strictness);
      if (wholeCleaned != null &&
          !_isNoiseFragment(wholeCleaned, hasVinLabel: hadLabel)) {
        addFragment(
          wholeCleaned,
          confidence: confidence,
          hasVinLabel: hadLabel,
        );
      }

      // Also evaluate individual whitespace-delimited tokens so non-VIN words
      // on the same line don't contaminate a partial VIN token.
      final tokens = withoutLabel.split(RegExp(r'\s+'));
      if (tokens.length > 1) {
        for (final token in tokens) {
          final cleanedToken = _cleanSegment(token, strictness: strictness);
          if (cleanedToken != null &&
              !_isNoiseFragment(cleanedToken, hasVinLabel: hadLabel)) {
            addFragment(
              cleanedToken,
              confidence: confidence,
              hasVinLabel: hadLabel,
            );
          }
        }
      }
    }

    final nonEmpty = result.blocks
        .where((b) => b.text.trim().isNotEmpty)
        .toList(growable: false);
    if (nonEmpty.isEmpty) {
      return fragments;
    }

    // Group blocks into horizontal rows when valid bounding boxes are present.
    final hasGeometry = nonEmpty.every((b) => _hasValidBox(b.boundingBox));
    if (hasGeometry) {
      final rows = _groupIntoHorizontalRows(nonEmpty);
      for (final row in rows) {
        final avgConfidence = row
                .map((b) => b.confidence > 0 ? b.confidence : 0.75)
                .reduce((a, b) => a + b) /
            row.length;

        if (row.length > 1) {
          // Build glare-gap composite fragments for blocks separated by a
          // localized glare washout on the same horizontal line.
          final gapped = _buildRowGappedComposite(row, strictness: strictness);
          if (gapped != null) {
            addFragment(
              gapped.pattern,
              confidence: avgConfidence,
              hasVinLabel: gapped.hasVinLabel,
            );
          } else {
            // Only collapse spacing across same-row blocks when there is NO
            // detected glare gap between them.
            final mergedSpaced = row.map((b) => b.text.trim()).join(' ');
            processRawText(mergedSpaced, confidence: avgConfidence);
          }
        }

        for (final block in row) {
          processRawText(
            block.text,
            confidence: block.confidence > 0 ? block.confidence : 0.75,
          );
        }
      }
    } else {
      for (final block in nonEmpty) {
        processRawText(
          block.text,
          confidence: block.confidence > 0 ? block.confidence : 0.75,
        );
      }
    }

    // Sort longer, higher-confidence fragments first so seeds are as strong as
    // possible before short overlapping pieces align to them.
    fragments.sort((a, b) {
      final labelDiff = (b.hasVinLabel ? 1 : 0) - (a.hasVinLabel ? 1 : 0);
      if (labelDiff != 0) return labelDiff;
      final lenDiff = b.concreteCount.compareTo(a.concreteCount);
      if (lenDiff != 0) return lenDiff;
      return b.confidence.compareTo(a.confidence);
    });
    return fragments;
  }

  List<String> _buildSingleFrameCandidateLines(VinOcrResult result) {
    final nonEmpty = result.blocks
        .where((b) => b.text.trim().isNotEmpty)
        .toList(growable: false);
    if (nonEmpty.isEmpty) {
      return const <String>[];
    }

    final hasGeometry = nonEmpty.every((b) => _hasValidBox(b.boundingBox));
    if (hasGeometry) {
      return result.orderedLines;
    }

    // Without bounding-box geometry, evaluate individual blocks so unrelated
    // door-jamb lines (e.g. "VIN: 1FM5K8GCXN" + "TIRE 35 PSI") are never
    // concatenated across lines into a single false-positive string.
    final lines = <String>[];
    final seen = <String>{};
    for (final block in nonEmpty) {
      final trimmed = block.text.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        lines.add(trimmed);
      }
    }
    return lines;
  }

  _GappedComposite? _buildRowGappedComposite(
    List<VinOcrTextBlock> row, {
    required VinScanStrictness strictness,
  }) {
    if (row.length < 2 || row.length > 4) {
      return null;
    }

    final pieces = <({String text, Rect box, bool hasLabel})>[];
    var totalWidth = 0.0;
    var totalChars = 0;

    for (final block in row) {
      final raw = block.text.trim();
      final withoutLabel = raw.replaceFirst(_vinLabelPrefixPattern, '').trim();
      final hadLabel = withoutLabel.length != raw.length;
      if (hadLabel && withoutLabel.isEmpty) {
        // Standalone "VIN:" label block before the actual VIN fragments.
        continue;
      }
      final cleaned = _cleanSegment(withoutLabel, strictness: strictness);
      if (cleaned == null ||
          cleaned.length < 2 ||
          _automotiveStopwords.contains(cleaned) ||
          _measurementPattern.hasMatch(cleaned)) {
        continue;
      }
      if (block.boundingBox.width <= 0) {
        continue;
      }
      pieces.add((text: cleaned, box: block.boundingBox, hasLabel: hadLabel));
      totalWidth += block.boundingBox.width;
      totalChars += cleaned.length;
    }

    if (pieces.length < 2 || totalChars < 7 || totalWidth <= 0) {
      return null;
    }

    final avgCharWidth = totalWidth / totalChars;
    if (avgCharWidth <= 1.0) {
      return null;
    }

    final buffer = StringBuffer(pieces.first.text);
    var anyGap = false;
    var hasLabel = pieces.first.hasLabel;

    for (var i = 1; i < pieces.length; i++) {
      final prev = pieces[i - 1];
      final curr = pieces[i];
      hasLabel = hasLabel || curr.hasLabel;

      final gapPx = curr.box.left - prev.box.right;
      if (gapPx > avgCharWidth * 6.5) {
        // Too far apart to be the same glare-split VIN line.
        return null;
      }
      if (gapPx > avgCharWidth * 0.65) {
        final missing = (gapPx / avgCharWidth).round().clamp(1, 6);
        buffer.write('?' * missing);
        anyGap = true;
      }
      buffer.write(curr.text);
    }

    if (!anyGap) {
      return null;
    }

    final pattern = buffer.toString();
    if (pattern.length < 11 || pattern.length > _maxHypothesisSpan) {
      return null;
    }
    final concrete = pattern.replaceAll('?', '');
    if (!_hasDigitPattern.hasMatch(concrete) ||
        !_hasLetterPattern.hasMatch(concrete)) {
      return null;
    }

    return _GappedComposite(pattern: pattern, hasVinLabel: hasLabel);
  }

  String? _cleanSegment(
    String rawSegment, {
    required VinScanStrictness strictness,
  }) {
    final compactRaw = rawSegment
        .trim()
        .replaceAll(_wrappingAsteriskPattern, '')
        .replaceAllMapped(RegExp(r'[\s\-_.:/\\|]+'), (match) {
      return strictness == VinScanStrictness.normal && match.group(0) == '|'
          ? '1'
          : '';
    });

    final preCaseNormalized = strictness == VinScanStrictness.normal
        ? compactRaw.replaceAll('l', '1')
        : compactRaw;
    final upperRaw = preCaseNormalized.toUpperCase();

    if (strictness == VinScanStrictness.strict) {
      final strictClean = upperRaw.replaceAll(_nonAlphanumericPattern, '');
      if (strictClean.isEmpty || _forbiddenLettersPattern.hasMatch(strictClean)) {
        return null;
      }
      return strictClean;
    }

    final normalized = upperRaw
        .replaceAll('I', '1')
        .replaceAll('O', '0')
        .replaceAll('Q', '0')
        .replaceAll(_nonAlphanumericPattern, '');
    return normalized.isEmpty ? null : normalized;
  }

  bool _isNoiseFragment(String cleaned, {required bool hasVinLabel}) {
    if (cleaned.length < _minFragmentLength || cleaned.length > 24) {
      return true;
    }
    if (_automotiveStopwords.contains(cleaned)) {
      return true;
    }
    if (_measurementPattern.hasMatch(cleaned)) {
      return true;
    }
    // Reject single repeated character runs like "00000" or "AAAAA".
    if (cleaned.split('').toSet().length <= 1) {
      return true;
    }
    // Purely alphabetic 4-5 char tokens without a VIN label are almost always
    // ordinary English words on stickers/trim rather than VIN slices.
    if (!hasVinLabel &&
        cleaned.length <= 5 &&
        !_hasDigitPattern.hasMatch(cleaned)) {
      return true;
    }
    return false;
  }

  bool _canSeedNewHypothesis(_OcrFragment fragment) {
    if (fragment.concreteCount < _minSeedLength) {
      return false;
    }
    final concrete = fragment.pattern.replaceAll('?', '');
    final hasLetter = _hasLetterPattern.hasMatch(concrete);
    final hasDigit = _hasDigitPattern.hasMatch(concrete);

    if (hasLetter && hasDigit) {
      return true;
    }
    if (fragment.hasVinLabel && concrete.length >= _minSeedLength) {
      return true;
    }
    // Allow 6+ char all-letter VIN prefixes (e.g. WBAWBK) or 6-digit serial
    // suffixes (e.g. 004352) to seed a track, since they can only lock if later
    // merged into a valid letter+digit 17-char VIN.
    if (concrete.length >= 6 && concrete.split('').toSet().length >= 3) {
      return true;
    }
    return false;
  }

  void _integrateFragment(
    _OcrFragment fragment, {
    required int frameId,
    required DateTime now,
  }) {
    _VinHypothesis? bestHypothesis;
    _AlignmentMatch? bestAlignment;

    for (final hypothesis in _hypotheses) {
      final match = _findBestAlignment(hypothesis, fragment);
      if (match == null) {
        continue;
      }
      if (bestAlignment == null || match.score > bestAlignment.score) {
        bestAlignment = match;
        bestHypothesis = hypothesis;
      }
    }

    if (bestHypothesis != null && bestAlignment != null) {
      bestHypothesis.mergeFragment(
        fragment,
        offset: bestAlignment.offset,
        frameId: frameId,
        now: now,
      );
      return;
    }

    if (_canSeedNewHypothesis(fragment)) {
      final created = _VinHypothesis(now: now);
      created.mergeFragment(fragment, offset: 0, frameId: frameId, now: now);
      _hypotheses.add(created);
    }
  }

  _AlignmentMatch? _findBestAlignment(
    _VinHypothesis hypothesis,
    _OcrFragment fragment,
  ) {
    if (hypothesis.isEmpty) {
      return null;
    }
    final consensus = hypothesis.consensusChars();
    if (consensus.isEmpty) {
      return null;
    }

    final minIdx = hypothesis.minIndex;
    final maxIdx = hypothesis.maxIndex;
    final pattern = fragment.pattern;
    final len = pattern.length;
    final concreteCount = fragment.concreteCount;

    final int minRequiredMatches;
    final int maxAllowedMismatches;
    final double minMatchRatio;

    if (concreteCount >= 14) {
      minRequiredMatches = 8;
      maxAllowedMismatches = 7;
      minMatchRatio = 0.58;
    } else if (concreteCount >= 7) {
      minRequiredMatches = 3;
      maxAllowedMismatches = 1;
      minMatchRatio = 0.75;
    } else {
      minRequiredMatches = 3;
      maxAllowedMismatches = 0;
      minMatchRatio = 1.0;
    }

    _AlignmentMatch? best;
    final startOffset = minIdx - len + minRequiredMatches;
    final endOffset = maxIdx - minRequiredMatches + 1;

    for (var offset = startOffset; offset <= endOffset; offset++) {
      final newMin = math.min(minIdx, offset);
      final newMax = math.max(maxIdx, offset + len - 1);
      final newSpan = newMax - newMin + 1;
      if (newSpan > _maxHypothesisSpan) {
        continue;
      }

      var overlap = 0;
      var matches = 0;
      var mismatches = 0;
      var newSlotsFilled = 0;
      final matchedChars = <String>{};

      for (var i = 0; i < len; i++) {
        final ch = pattern[i];
        if (ch == '?') {
          continue;
        }
        final slot = offset + i;
        final existing = consensus[slot];
        if (existing == null) {
          newSlotsFilled++;
        } else {
          overlap++;
          if (existing == ch) {
            matches++;
            matchedChars.add(ch);
          } else {
            mismatches++;
            if (mismatches > maxAllowedMismatches) {
              break;
            }
          }
        }
      }

      if (mismatches > maxAllowedMismatches) {
        continue;
      }
      if (overlap < minRequiredMatches || matches < minRequiredMatches) {
        continue;
      }
      // Reject degenerate 3-character overlaps made of a single repeated digit
      // or letter (e.g. "000" aligning two unrelated numbers).
      if (matches == 3 && matchedChars.length <= 1) {
        continue;
      }
      final ratio = matches / overlap;
      if (ratio < minMatchRatio) {
        continue;
      }

      final score = (matches * 12) -
          (mismatches * 16) +
          math.min(newSlotsFilled, 6) * 2;
      if (score <= 0) {
        continue;
      }

      if (best == null || score > best.score) {
        best = _AlignmentMatch(offset: offset, score: score);
      }
    }

    return best;
  }

  String? _solveBestVin({required VinScanStrictness strictness}) {
    _SolvedCandidate? best;

    for (final hypothesis in _hypotheses) {
      if (hypothesis.isEmpty || hypothesis.distinctFrames < 2) {
        continue;
      }
      final span = hypothesis.maxIndex - hypothesis.minIndex + 1;
      if (span < _vinLength) {
        continue;
      }

      for (var start = hypothesis.minIndex;
          start <= hypothesis.maxIndex - _vinLength + 1;
          start++) {
        final candidate = _evaluateWindow(
          hypothesis,
          start: start,
          strictness: strictness,
        );
        if (candidate == null) {
          continue;
        }
        if (best == null || candidate.score > best.score) {
          best = candidate;
        }
      }
    }

    return best?.vin;
  }

  _SolvedCandidate? _evaluateWindow(
    _VinHypothesis hypothesis, {
    required int start,
    required VinScanStrictness strictness,
  }) {
    final chars = <String>[];
    final slotSummaries = <_SlotSummary>[];
    var multiFrameSlots = 0;
    var minSlotFrames = 999;
    var minDominance = 1.0;
    var totalWeight = 0.0;

    for (var i = 0; i < _vinLength; i++) {
      final summary = hypothesis.slotSummary(start + i);
      if (summary == null) {
        return null;
      }
      chars.add(summary.winner);
      slotSummaries.add(summary);
      if (summary.winnerFrames >= 2) {
        multiFrameSlots++;
      }
      if (summary.winnerFrames < minSlotFrames) {
        minSlotFrames = summary.winnerFrames;
      }
      if (summary.dominance < minDominance) {
        minDominance = summary.dominance;
      }
      totalWeight += summary.winnerWeight;
    }

    final vin = chars.join();
    if (!_validVinPattern.hasMatch(vin)) {
      return null;
    }
    if (!_hasDigitPattern.hasMatch(vin) || !_hasLetterPattern.hasMatch(vin)) {
      return null;
    }

    final hasValidModelYear = _validModelYearChars.contains(vin[9]);
    final serialDigits = _countDigits(vin.substring(11));
    final hasValidCheckDigit = validator.hasValidCheckDigit(vin);
    final startsAtLeftEdge = start == hypothesis.minIndex;
    final labelBonus = hypothesis.hasVinLabel ? 20 : 0;

    // Gate 1: ISO 3779 check-digit verified multi-frame assembly.
    if (hasValidCheckDigit && hasValidModelYear) {
      if (strictness == VinScanStrictness.strict) {
        // Strict mode: strong multi-frame agreement across the full VIN.
        if (minDominance >= 0.70 &&
            multiFrameSlots >= 10 &&
            slotSummaries.every(
              (s) => s.winnerFrames >= 2 || s.winnerWeight >= 0.85,
            )) {
          final score = 200 +
              labelBonus +
              multiFrameSlots * 4 +
              serialDigits * 2 +
              (startsAtLeftEdge ? 6 : 0) +
              totalWeight.round();
          return _SolvedCandidate(vin: vin, score: score);
        }
        return null;
      }

      // Normal mode: allows both stationary glare-tilt (high multiFrameSlots)
      // and left-to-right panning (overlapping chunks with >= 4 shared slots).
      final allSlotsConfident = slotSummaries.every(
        (s) =>
            s.dominance >= 0.60 &&
            (s.winnerFrames >= 2
                ? s.winnerWeight >= 0.65
                : s.winnerWeight >= 0.75),
      );
      if (allSlotsConfident && multiFrameSlots >= 4) {
        final score = 180 +
            labelBonus +
            multiFrameSlots * 4 +
            serialDigits * 2 +
            (startsAtLeftEdge ? 6 : 0) +
            totalWeight.round();
        return _SolvedCandidate(vin: vin, score: score);
      }
    }

    // Gate 2 (Normal mode only): single-slot OCR confusion repair when 15+
    // slots are already multi-frame confirmed and exactly one confusion swap
    // yields a valid ISO 3779 check digit.
    if (strictness == VinScanStrictness.normal &&
        !hasValidCheckDigit &&
        hypothesis.distinctFrames >= 3 &&
        multiFrameSlots >= 15) {
      final repaired = _tryRepairAssembledVin(vin, slotSummaries);
      if (repaired != null && _validModelYearChars.contains(repaired[9])) {
        final score = 140 +
            labelBonus +
            multiFrameSlots * 3 +
            serialDigits * 2 +
            (startsAtLeftEdge ? 4 : 0);
        return _SolvedCandidate(vin: repaired, score: score);
      }
    }

    // Gate 3 (Normal mode only): non-North-American VINs that don't use the
    // ISO 3779 check digit require strong 3-frame unanimous consensus across
    // every single slot + strong automotive VIN structure.
    if (strictness == VinScanStrictness.normal &&
        !hasValidCheckDigit &&
        hasValidModelYear &&
        serialDigits >= 4 &&
        minSlotFrames >= 3 &&
        minDominance >= 0.75 &&
        hypothesis.maxIndex - hypothesis.minIndex + 1 <= _vinLength + 1) {
      final score = 100 +
          labelBonus +
          multiFrameSlots * 2 +
          serialDigits * 2 +
          (startsAtLeftEdge ? 6 : 0);
      return _SolvedCandidate(vin: vin, score: score);
    }

    return null;
  }

  String? _tryRepairAssembledVin(
    String vin,
    List<_SlotSummary> slotSummaries,
  ) {
    final matches = <String>[];

    // First prefer runner-up characters actually observed in the vote table
    // at any slot where there was disagreement.
    for (var i = 0; i < _vinLength; i++) {
      final runnerUp = slotSummaries[i].runnerUp;
      if (runnerUp == null) {
        continue;
      }
      final candidate = '${vin.substring(0, i)}$runnerUp${vin.substring(i + 1)}';
      if (_validVinPattern.hasMatch(candidate) &&
          validator.hasValidCheckDigit(candidate)) {
        matches.add(candidate);
      }
    }
    if (matches.length == 1) {
      return matches.first;
    }
    if (matches.length > 1) {
      return null;
    }

    // Fallback: try standard OCR lookalike alternatives only on the single
    // weakest-confidence slot.
    var weakestIdx = 0;
    var weakestScore = double.infinity;
    for (var i = 0; i < _vinLength; i++) {
      final s = slotSummaries[i];
      final strength = s.winnerFrames + s.dominance;
      if (strength < weakestScore) {
        weakestScore = strength;
        weakestIdx = i;
      }
    }

    final alternatives = _ocrConfusionAlternatives[vin[weakestIdx]];
    if (alternatives == null) {
      return null;
    }
    for (final alt in alternatives) {
      final candidate =
          '${vin.substring(0, weakestIdx)}$alt${vin.substring(weakestIdx + 1)}';
      if (_validVinPattern.hasMatch(candidate) &&
          validator.hasValidCheckDigit(candidate)) {
        matches.add(candidate);
      }
    }

    return matches.length == 1 ? matches.first : null;
  }

  VinAssemblyProgress? _buildBestProgress() {
    _VinHypothesis? best;
    var bestScore = -1.0;

    for (final hypothesis in _hypotheses) {
      final filled = hypothesis.populatedSlotCount;
      if (filled < _minProgressSlotsToDisplay) {
        continue;
      }
      final rawText = hypothesis.compactText();
      final hasLetter = _hasLetterPattern.hasMatch(rawText);
      final hasDigit = _hasDigitPattern.hasMatch(rawText);
      if (!hypothesis.hasVinLabel && (!hasLetter || !hasDigit)) {
        continue;
      }
      final score = hypothesis.rankingScore;
      if (score > bestScore) {
        bestScore = score;
        best = hypothesis;
      }
    }

    if (best == null) {
      return null;
    }

    final span = best.maxIndex - best.minIndex + 1;
    final windowStart = span > _vinLength
        ? _chooseBestDisplayStart(best)
        : best.minIndex;

    final slots = List<String?>.filled(_vinLength, null);
    final confirmed = List<bool>.filled(_vinLength, false);
    var filledCount = 0;
    var confirmedCount = 0;
    final partialBuffer = StringBuffer();

    for (var i = 0; i < _vinLength; i++) {
      final summary = best.slotSummary(windowStart + i);
      if (summary != null) {
        slots[i] = summary.winner;
        filledCount++;
        partialBuffer.write(summary.winner);
        if (summary.winnerFrames >= 2) {
          confirmed[i] = true;
          confirmedCount++;
        }
      }
    }

    if (filledCount < _minProgressSlotsToDisplay) {
      return null;
    }

    return VinAssemblyProgress(
      slots: slots,
      confirmedSlots: confirmed,
      filledCount: filledCount,
      confirmedCount: confirmedCount,
      bestPartialText: partialBuffer.toString(),
    );
  }

  int _chooseBestDisplayStart(_VinHypothesis hypothesis) {
    var bestStart = hypothesis.minIndex;
    var bestWeight = -1.0;
    for (var start = hypothesis.minIndex;
        start <= hypothesis.maxIndex - _vinLength + 1;
        start++) {
      var weight = 0.0;
      for (var i = 0; i < _vinLength; i++) {
        final summary = hypothesis.slotSummary(start + i);
        if (summary != null) {
          weight += summary.winnerWeight;
        }
      }
      if (weight > bestWeight) {
        bestWeight = weight;
        bestStart = start;
      }
    }
    return bestStart;
  }

  static bool _hasValidBox(Rect rect) =>
      rect != Rect.zero &&
      rect.left.isFinite &&
      rect.top.isFinite &&
      rect.right.isFinite &&
      rect.bottom.isFinite &&
      rect.width >= 0 &&
      rect.height >= 0;

  static List<List<VinOcrTextBlock>> _groupIntoHorizontalRows(
    List<VinOcrTextBlock> blocks,
  ) {
    final sorted = List<VinOcrTextBlock>.of(blocks)
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
    }
    return rows;
  }

  static int _countConcreteChars(String pattern) {
    var count = 0;
    for (var i = 0; i < pattern.length; i++) {
      if (pattern[i] != '?') {
        count++;
      }
    }
    return count;
  }

  static int _countDigits(String value) {
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

class _OcrFragment {
  const _OcrFragment({
    required this.pattern,
    required this.concreteCount,
    required this.confidence,
    required this.hasVinLabel,
  });

  final String pattern;
  final int concreteCount;
  final double confidence;
  final bool hasVinLabel;
}

class _GappedComposite {
  const _GappedComposite({
    required this.pattern,
    required this.hasVinLabel,
  });

  final String pattern;
  final bool hasVinLabel;
}

class _AlignmentMatch {
  const _AlignmentMatch({required this.offset, required this.score});

  final int offset;
  final int score;
}

class _SolvedCandidate {
  const _SolvedCandidate({required this.vin, required this.score});

  final String vin;
  final int score;
}

class _SlotSummary {
  const _SlotSummary({
    required this.winner,
    required this.winnerWeight,
    required this.winnerFrames,
    required this.dominance,
    this.runnerUp,
  });

  final String winner;
  final double winnerWeight;
  final int winnerFrames;
  final double dominance;
  final String? runnerUp;
}

class _FrameVote {
  _FrameVote({
    required this.char,
    required this.weight,
    required this.timestamp,
  });

  String char;
  double weight;
  DateTime timestamp;
}

class _VinHypothesis {
  _VinHypothesis({required DateTime now}) : lastUpdated = now;

  // slotIndex -> frameId -> _FrameVote (at most one vote per frame per slot).
  final Map<int, Map<int, _FrameVote>> _slots = <int, Map<int, _FrameVote>>{};
  final Set<int> _frames = <int>{};
  DateTime lastUpdated;
  bool hasVinLabel = false;

  bool get isEmpty => _slots.isEmpty;

  int get populatedSlotCount => _slots.length;

  int get distinctFrames => _frames.length;

  int get minIndex => _slots.keys.reduce(math.min);

  int get maxIndex => _slots.keys.reduce(math.max);

  double get rankingScore {
    var score = populatedSlotCount * 4.0 + distinctFrames * 6.0;
    if (hasVinLabel) {
      score += 18.0;
    }
    return score;
  }

  void mergeFragment(
    _OcrFragment fragment, {
    required int offset,
    required int frameId,
    required DateTime now,
  }) {
    lastUpdated = now;
    if (fragment.hasVinLabel) {
      hasVinLabel = true;
    }
    _frames.add(frameId);

    final baseWeight = fragment.confidence + (fragment.hasVinLabel ? 0.15 : 0.0);
    for (var i = 0; i < fragment.pattern.length; i++) {
      final ch = fragment.pattern[i];
      if (ch == '?') {
        continue;
      }
      final slot = offset + i;
      final frameMap = _slots.putIfAbsent(slot, () => <int, _FrameVote>{});
      final existing = frameMap[frameId];
      if (existing == null || baseWeight > existing.weight) {
        frameMap[frameId] = _FrameVote(
          char: ch,
          weight: baseWeight,
          timestamp: now,
        );
      }
    }
  }

  void pruneOlderThan(DateTime cutoff) {
    final survivingFrames = <int>{};
    final emptySlots = <int>[];

    _slots.forEach((slot, frameMap) {
      frameMap.removeWhere((_, vote) => vote.timestamp.isBefore(cutoff));
      if (frameMap.isEmpty) {
        emptySlots.add(slot);
      } else {
        survivingFrames.addAll(frameMap.keys);
      }
    });

    for (final slot in emptySlots) {
      _slots.remove(slot);
    }
    _frames
      ..clear()
      ..addAll(survivingFrames);
  }

  Map<int, String> consensusChars() {
    final map = <int, String>{};
    for (final slot in _slots.keys) {
      final summary = slotSummary(slot);
      if (summary != null) {
        map[slot] = summary.winner;
      }
    }
    return map;
  }

  String compactText() {
    if (_slots.isEmpty) {
      return '';
    }
    final keys = _slots.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in keys) {
      final summary = slotSummary(key);
      if (summary != null) {
        buffer.write(summary.winner);
      }
    }
    return buffer.toString();
  }

  _SlotSummary? slotSummary(int slot) {
    final frameMap = _slots[slot];
    if (frameMap == null || frameMap.isEmpty) {
      return null;
    }

    final weights = <String, double>{};
    final frameCounts = <String, int>{};
    var totalWeight = 0.0;

    for (final vote in frameMap.values) {
      weights[vote.char] = (weights[vote.char] ?? 0.0) + vote.weight;
      frameCounts[vote.char] = (frameCounts[vote.char] ?? 0) + 1;
      totalWeight += vote.weight;
    }

    String? winner;
    var winnerWeight = -1.0;
    String? runnerUp;
    var runnerUpWeight = -1.0;

    weights.forEach((char, weight) {
      if (weight > winnerWeight) {
        runnerUp = winner;
        runnerUpWeight = winnerWeight;
        winner = char;
        winnerWeight = weight;
      } else if (weight > runnerUpWeight) {
        runnerUp = char;
        runnerUpWeight = weight;
      }
    });

    if (winner == null || totalWeight <= 0) {
      return null;
    }

    return _SlotSummary(
      winner: winner!,
      winnerWeight: winnerWeight,
      winnerFrames: frameCounts[winner!] ?? 0,
      dominance: winnerWeight / totalWeight,
      runnerUp: runnerUp,
    );
  }
}
