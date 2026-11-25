import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinkit_app/services/vin_frame_assembler.dart';
import 'package:vinkit_app/services/vin_ocr_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';

VinOcrResult _frame(List<VinOcrTextBlock> blocks) =>
    VinOcrResult(blocks: blocks);

VinOcrTextBlock _block(
  String text, {
  double confidence = 0.90,
  Rect box = Rect.zero,
}) =>
    VinOcrTextBlock(text: text, confidence: confidence, boundingBox: box);

void main() {
  group('VinFrameAssembler', () {
    test('locks clean single-frame VIN immediately without delay', () {
      var now = DateTime(2026, 11, 24, 12, 0, 0);
      final assembler = VinFrameAssembler(clock: () => now);

      final result = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('1HGCM82633A004352')]),
        strictness: VinScanStrictness.normal,
      );

      expect(result.vin, '1HGCM82633A004352');
      expect(result.assembledFromMultipleFrames, isFalse);
      expect(result.progress, isNull);
    });

    test('assembles overlapping left-to-right panning chunks across glare', () {
      var now = DateTime(2026, 11, 24, 12, 0, 0);
      final assembler = VinFrameAssembler(clock: () => now);

      final step1 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('1HGCM8263', confidence: 0.92)]),
        strictness: VinScanStrictness.normal,
      );
      expect(step1.vin, isNull);
      expect(step1.progress, isNotNull);
      expect(step1.progress!.filledCount, 9);

      now = now.add(const Duration(milliseconds: 750));
      final step2 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('CM82633A00', confidence: 0.91)]),
        strictness: VinScanStrictness.normal,
      );
      expect(step2.vin, isNull);
      expect(step2.progress, isNotNull);
      expect(step2.progress!.filledCount, 13);
      expect(step2.progress!.confirmedCount, greaterThanOrEqualTo(6));

      now = now.add(const Duration(milliseconds: 750));
      final step3 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('3A004352', confidence: 0.93)]),
        strictness: VinScanStrictness.normal,
      );
      expect(step3.vin, '1HGCM82633A004352');
      expect(step3.assembledFromMultipleFrames, isTrue);
    });

    test('solves localized windshield glare split on same horizontal row', () {
      var now = DateTime(2026, 11, 24, 12, 0, 0);
      final assembler = VinFrameAssembler(clock: () => now);

      // Frame 1: glare washes out characters 7..8 ('63') in the middle of row.
      // Char width = 20px, gap = 40px -> 2 missing chars.
      final f1 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[
          _block(
            '1HGCM82',
            confidence: 0.91,
            box: const Rect.fromLTWH(100, 200, 140, 32),
          ),
          _block(
            '3A004352',
            confidence: 0.92,
            box: const Rect.fromLTWH(280, 202, 160, 32),
          ),
        ]),
        strictness: VinScanStrictness.normal,
      );
      expect(f1.vin, isNull);
      expect(f1.progress, isNotNull);
      expect(f1.progress!.filledCount, 15);

      // Frame 2: user tilts phone slightly; glare shifts left, exposing '82633A004352'.
      now = now.add(const Duration(milliseconds: 750));
      final f2 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[
          _block(
            '1HG',
            confidence: 0.88,
            box: const Rect.fromLTWH(100, 200, 60, 32),
          ),
          _block(
            '82633A004352',
            confidence: 0.93,
            box: const Rect.fromLTWH(200, 201, 240, 32),
          ),
        ]),
        strictness: VinScanStrictness.normal,
      );

      expect(f2.vin, '1HGCM82633A004352');
      expect(f2.assembledFromMultipleFrames, isTrue);
    });

    test('solves glare-corrupted full-width reads via per-slot voting', () {
      var now = DateTime(2026, 11, 24, 12, 0, 0);
      final assembler = VinFrameAssembler(clock: () => now);

      // Each frame has 2-3 corrupted characters in different spots so single-frame
      // extraction (and 1-char repair) cannot solve any single frame on its own.
      final f1 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('1HGXX82633A004352', confidence: 0.88)]),
        strictness: VinScanStrictness.normal,
      );
      expect(f1.vin, isNull);

      now = now.add(const Duration(milliseconds: 750));
      final f2 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('1HGCM82633A00XXXX', confidence: 0.89)]),
        strictness: VinScanStrictness.normal,
      );
      expect(f2.vin, isNull);

      now = now.add(const Duration(milliseconds: 750));
      final f3 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('1HGCM82ZZZA004352', confidence: 0.90)]),
        strictness: VinScanStrictness.normal,
      );
      expect(f3.vin, '1HGCM82633A004352');
      expect(f3.assembledFromMultipleFrames, isTrue);
    });

    test('handles Hyundai 18-character trailing letter quirk across partial frames', () {
      var now = DateTime(2026, 11, 24, 12, 0, 0);
      final assembler = VinFrameAssembler(clock: () => now);

      final f1 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('5NPD84LF0KH', confidence: 0.92)]),
        strictness: VinScanStrictness.normal,
      );
      expect(f1.vin, isNull);

      now = now.add(const Duration(milliseconds: 750));
      final f2 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('LF0KH412345A', confidence: 0.91)]),
        strictness: VinScanStrictness.normal,
      );
      expect(f2.vin, '5NPD84LF0KH412345');
      expect(f2.assembledFromMultipleFrames, isTrue);
    });

    test('ignores non-VIN door-jamb sticker clutter without false positives', () {
      var now = DateTime(2026, 11, 24, 12, 0, 0);
      final assembler = VinFrameAssembler(clock: () => now);

      for (var i = 0; i < 4; i++) {
        final result = assembler.addFrame(
          _frame(<VinOcrTextBlock>[
            _block('MFD BY HONDA MOTOR CO', confidence: 0.95),
            _block('GVWR 4500 LBS', confidence: 0.94),
            _block('TIRE PRESSURE 35 PSI', confidence: 0.93),
            _block('PAINT NH731P', confidence: 0.92),
            _block('CONFORMS TO FEDERAL SAFETY STANDARDS', confidence: 0.91),
          ]),
          strictness: VinScanStrictness.normal,
        );
        expect(result.vin, isNull);
        now = now.add(const Duration(milliseconds: 750));
      }
    });

    test('isolates real VIN fragments from concurrent door-jamb clutter', () {
      var now = DateTime(2026, 11, 24, 12, 0, 0);
      final assembler = VinFrameAssembler(clock: () => now);

      final f1 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[
          _block('GVWR 5200 LBS', confidence: 0.95),
          _block('VIN: 1FM5K8GCXN', confidence: 0.90),
          _block('TIRE 35 PSI COLD', confidence: 0.94),
        ]),
        strictness: VinScanStrictness.normal,
      );
      expect(f1.vin, isNull);

      now = now.add(const Duration(milliseconds: 750));
      final f2 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[
          _block('MFD BY FORD MOTOR CO', confidence: 0.95),
          _block('GCXNGA77516', confidence: 0.91),
          _block('GAWR FRONT 2750 LB', confidence: 0.93),
        ]),
        strictness: VinScanStrictness.normal,
      );
      expect(f2.vin, '1FM5K8GCXNGA77516');
      expect(f2.assembledFromMultipleFrames, isTrue);
    });

    test('strict mode rejects forbidden I/O/Q fragments while assembling clean ones', () {
      var now = DateTime(2026, 11, 24, 12, 0, 0);
      final assembler = VinFrameAssembler(clock: () => now);

      // Forbidden letters I/O must be ignored in strict mode.
      final bad1 = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('IHGCM8263', confidence: 0.95)]),
        strictness: VinScanStrictness.strict,
      );
      expect(bad1.vin, isNull);
      expect(bad1.progress, isNull);

      // Clean multi-frame reads with strong overlap succeed in strict mode.
      now = now.add(const Duration(milliseconds: 750));
      assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('1HGCM82633A004', confidence: 0.94)]),
        strictness: VinScanStrictness.strict,
      );
      now = now.add(const Duration(milliseconds: 750));
      final good = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('CM82633A004352', confidence: 0.94)]),
        strictness: VinScanStrictness.strict,
      );
      expect(good.vin, '1HGCM82633A004352');
      expect(good.assembledFromMultipleFrames, isTrue);
    });

    test('expires stale fragments when user moves to a different vehicle', () {
      var now = DateTime(2026, 11, 24, 12, 0, 0);
      final assembler = VinFrameAssembler(clock: () => now);

      // Car A partial prefix.
      final carA = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('1HGCM82633A', confidence: 0.92)]),
        strictness: VinScanStrictness.normal,
      );
      expect(carA.progress, isNotNull);

      // 5 seconds pass -> Car A hypothesis expires.
      now = now.add(const Duration(seconds: 5));

      // Car B partial suffix alone must NOT combine with expired Car A prefix.
      final carB = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('33A004352', confidence: 0.92)]),
        strictness: VinScanStrictness.normal,
      );
      expect(carB.vin, isNull);
      expect(carB.progress?.filledCount, 9);
    });

    test('does not stitch unrelated chunks on degenerate repeated overlap like 000', () {
      var now = DateTime(2026, 11, 24, 12, 0, 0);
      final assembler = VinFrameAssembler(clock: () => now);

      assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('ABCDE12000', confidence: 0.90)]),
        strictness: VinScanStrictness.normal,
      );
      now = now.add(const Duration(milliseconds: 750));
      final second = assembler.addFrame(
        _frame(<VinOcrTextBlock>[_block('0009876543', confidence: 0.90)]),
        strictness: VinScanStrictness.normal,
      );

      expect(second.vin, isNull);
      expect(second.progress?.filledCount, lessThan(17));
    });
  });
}
