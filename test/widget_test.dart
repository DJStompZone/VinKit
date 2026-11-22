import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vinkit_app/models/oil_spec.dart';
import 'package:vinkit_app/models/vehicle_info.dart';
import 'package:vinkit_app/models/vehicle_part.dart';
import 'package:vinkit_app/models/vehicle_service_item.dart';
import 'package:vinkit_app/models/vf_match.dart';
import 'package:vinkit_app/models/vin_lookup_exception.dart';
import 'package:vinkit_app/models/vin_lookup_result.dart';
import 'package:vinkit_app/screens/scanner_screen.dart';
import 'package:vinkit_app/screens/vehicle_result_screen.dart';
import 'package:vinkit_app/services/scanner_feedback_service.dart';
import 'package:vinkit_app/services/vin_lookup_controller.dart';
import 'package:vinkit_app/services/vin_lookup_service.dart';
import 'package:vinkit_app/services/vin_ocr_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';
import 'package:vinkit_app/theme/app_theme.dart';
import 'package:vinkit_app/widgets/camera_permission_view.dart';
import 'package:vinkit_app/widgets/manual_vin_sheet.dart';
import 'package:vinkit_app/widgets/scanner_controls.dart';
import 'package:vinkit_app/widgets/scanner_overlay.dart';
import 'package:vinkit_app/widgets/startup_splash_overlay.dart';

class _FakeFeedbackService implements ScannerFeedbackService {
  int playCount = 0;

  @override
  Future<void> playValidScanFeedback() async {
    playCount++;
  }
}

class _FakeVinLookupService implements VinLookupService {
  _FakeVinLookupService(this.handler);

  final Future<VinLookupResult> Function(String vin) handler;

  @override
  Future<VinLookupResult> lookupVin(String vin) => handler(vin);

  @override
  void dispose() {}
}

class _FakeOcrService implements VinOcrService {
  const _FakeOcrService();

  @override
  bool get isSupported => true;

  @override
  Future<bool> isModelReady() async => true;

  @override
  Future<void> prepareModels() async {}

  @override
  Future<VinOcrResult> recognizeText(String imagePath) async {
    return const VinOcrResult(
      blocks: <VinOcrTextBlock>[
        VinOcrTextBlock(text: 'VIN: 1FM5K8GCXNGA77516', confidence: 0.96),
      ],
    );
  }

  @override
  Future<void> deleteTempImage(String imagePath) async {}
}

VinLookupResult _explorerResult() {
  return const VinLookupResult(
    vin: '1FM5K8GCXNGA77516',
    vehicle: VehicleInfo(
      id: 31821,
      year: 2022,
      make: 'Ford',
      model: 'Explorer',
      trim: 'ST',
      engine: '3.0L V6 GTDI',
    ),
    partsByCategory: <String, List<VehiclePart>>{
      'oil_filter': <VehiclePart>[
        VehiclePart(
          category: 'oil_filter',
          position: '',
          brand: 'Valvoline (STANDARD)',
          partNumber: 'VO-115',
          detail: 'Engine Oil Filter',
          source: 'Valvoline Catalog',
          verified: true,
        ),
      ],
      'air_filter': <VehiclePart>[
        VehiclePart(
          category: 'air_filter',
          position: '',
          brand: 'Valvoline',
          partNumber: 'VA-224',
          detail: 'Engine Air Filter',
          source: 'Valvoline Catalog',
          verified: true,
        ),
      ],
      'cabin_filter': <VehiclePart>[
        VehiclePart(
          category: 'cabin_filter',
          position: '',
          brand: 'Valvoline',
          partNumber: 'VCA-2059',
          detail: 'Particulate; Located Behind Glove Box',
          source: 'Valvoline Catalog',
          verified: true,
        ),
      ],
      'wiper': <VehiclePart>[
        VehiclePart(
          category: 'wiper',
          position: 'driver',
          brand: 'Valvoline (BEAM BLADE)',
          partNumber: '836539',
          detail: 'FRONT LEFT | 26 in.; Arm Connector: PT 15; Original (OEM): Beam',
          source: 'Valvoline Catalog',
          verified: true,
        ),
        VehiclePart(
          category: 'wiper',
          position: 'passenger',
          brand: 'Valvoline (BEAM BLADE)',
          partNumber: '836536',
          detail: 'FRONT RIGHT | 21 in.; Arm Connector: PT 15; Original (OEM): Beam',
          source: 'Valvoline Catalog',
          verified: true,
        ),
        VehiclePart(
          category: 'wiper',
          position: 'rear',
          brand: 'Valvoline (REAR BLADE)',
          partNumber: '873271',
          detail: 'REAR | 11 in.; Arm Connector: U-Clip 8.5mm; Original (OEM): Beam',
          source: 'Valvoline Catalog',
          verified: true,
        ),
      ],
      'battery': <VehiclePart>[
        VehiclePart(
          category: 'battery',
          position: '',
          brand: 'Valvoline Battery (VALVOLINE)',
          partNumber: '48AGM-V',
          detail: 'AGM Valve-Regulated Battery Required.; Part CCA: 760; OE Group: 48',
          source: 'Valvoline Catalog',
          verified: true,
        ),
      ],
    },
    oilSpecs: <OilSpec>[
      OilSpec(
        origin: 'Valvoline',
        viscosity: '5W-30',
        oilType: 'synthetic',
        capacityQt: 6,
        specNotes: 'Restore & Protect Full Synthetic SAE 5W-30 Motor Oil',
        source: 'Valvoline Product Finder',
        verified: true,
      ),
      OilSpec(
        origin: 'Valvoline',
        viscosity: '5W-30',
        oilType: 'synthetic_blend',
        capacityQt: 6,
        specNotes: 'Daily Protection Synthetic Blend SAE 5W-30 Motor Oil',
        source: 'Valvoline Product Finder',
        verified: true,
      ),
    ],
    services: <VehicleServiceItem>[
      VehicleServiceItem(
        service: 'Cooling system',
        origin: 'Valvoline',
        notes: 'Multi-Vehicle Antifreeze / Coolant (Codes: ["719009", "719005"])',
        source: 'Valvoline Product Finder',
        verified: true,
      ),
    ],
    vfMatches: <VfMatch>[
      VfMatch(
        engineId: '5e755200bc0042b0',
        matchScore: 144,
        matchType: 'exact_displacement',
        make: 'Ford',
        modelRaw: 'Explorer, U625 (2019- )',
        engineRaw: 'Explorer 3.0 EcoBoost AWD (298 KW) (2020 - )',
        region: '',
        yearFrom: 2020,
        yearTo: 2027,
        displacementL: 3.0,
        grade: '5W-30',
        capacityQt: 6,
      ),
    ],
  );
}

/// Widget tests covering manual entry validation, full-screen vehicle spec
/// rendering, scanner beep feedback, strictness selector, OCR mode switching,
/// error retries, clipboard copy, and camera permission recovery UI.
void main() {
  group('PlatformScannerFeedbackService', () {
    test('invokes native playScanBeep method channel and haptic feedback', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      var beepCalled = false;
      var hapticCalled = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        PlatformScannerFeedbackService.defaultChannel,
        (call) async {
          if (call.method == 'playScanBeep') {
            beepCalled = true;
          }
          return null;
        },
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            hapticCalled = true;
          }
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          PlatformScannerFeedbackService.defaultChannel,
          null,
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      const service = PlatformScannerFeedbackService();
      await service.playValidScanFeedback();

      expect(beepCalled, isTrue);
      expect(hapticCalled, isTrue);
    });
  });

  group('ManualVinSheet', () {
    testWidgets('validates forbidden characters and submits valid 17-char VIN', (tester) async {
      String? submittedVin;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    submittedVin = await showModalBottomSheet<String>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const ManualVinSheet(),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1FM5K8GCXOGA77516');
      await tester.pump();
      expect(
        find.text('VINs cannot contain the letters I, O, or Q.'),
        findsOneWidget,
      );

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Look Up Vehicle'),
      );
      expect(button.onPressed, isNull);

      await tester.enterText(find.byType(TextField), '1fm5k8gcxnga77516');
      await tester.pump();
      expect(find.text('17 / 17'), findsOneWidget);

      await tester.tap(find.text('Look Up Vehicle'));
      await tester.pumpAndSettle();
      expect(submittedVin, '1FM5K8GCXNGA77516');
    });
  });

  group('VehicleResultScreen', () {
    testWidgets(
      'displays Year/Make/Model, Oil, Filters, and Wipers immediately above the fold, plus full specs on scroll',
      (tester) async {
        // Use a realistic standard phone viewport (412 x 892 logical px).
        tester.view.physicalSize = const Size(412, 892);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        String? copiedText;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              final args = call.arguments as Map<Object?, Object?>;
              copiedText = args['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );

        final completer = Completer<VinLookupResult>();
        final controller = VinLookupController(
          service: _FakeVinLookupService((_) => completer.future),
        );
        addTearDown(controller.dispose);

        var scanNextTapped = false;
        unawaited(controller.lookupVin('1FM5K8GCXNGA77516'));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: VehicleResultScreen(
              controller: controller,
              onScanNext: () => scanNextTapped = true,
              onEnterDifferentVin: () {},
            ),
          ),
        );

        // Loading state immediately displays the scanned VIN.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('1FM5K8GCXNGA77516'), findsOneWidget);

        completer.complete(_explorerResult());
        await tester.pumpAndSettle();

        // Above-the-fold verification: NO scrolling yet!
        const visibleBottomEdge = 830.0;
        void expectImmediatelyVisible(Finder finder) {
          expect(finder, findsOneWidget);
          final rect = tester.getRect(finder);
          expect(
            rect.top,
            lessThan(visibleBottomEdge),
            reason: 'Expected $finder to be immediately visible without scrolling (top=${rect.top})',
          );
        }

        // Year, Make, Model, Trim, Engine
        expectImmediatelyVisible(find.text('2022 Ford Explorer'));
        expectImmediatelyVisible(find.text('ST'));
        expectImmediatelyVisible(find.text('3.0L V6 GTDI'));

        // Recommended Oil
        expectImmediatelyVisible(find.text('5W-30'));
        expectImmediatelyVisible(find.text('6 qt'));

        // Filters
        expectImmediatelyVisible(find.text('VO-115'));
        expectImmediatelyVisible(find.text('VA-224'));
        expectImmediatelyVisible(find.text('VCA-2059'));

        // Wipers (Driver, Passenger, Rear + lengths & part numbers)
        expectImmediatelyVisible(find.text('26"'));
        expectImmediatelyVisible(find.text('836539'));
        expectImmediatelyVisible(find.text('21"'));
        expectImmediatelyVisible(find.text('836536'));
        expectImmediatelyVisible(find.text('11"'));
        expectImmediatelyVisible(find.text('873271'));

        // Copy raw VIN
        await tester.tap(find.text('Copy'));
        await tester.pump();
        expect(copiedText, '1FM5K8GCXNGA77516');
        expect(find.text('Copied'), findsOneWidget);

        // Copy part number by tapping the pill
        await tester.tap(find.text('VO-115'));
        await tester.pump();
        expect(copiedText, 'VO-115');

        // Scroll down to verify Battery, Full Oil Options, Fluids & Codes, and Match Details
        final scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('48AGM-V'),
          250,
          scrollable: scrollable,
        );
        expect(find.text('48AGM-V'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('719009'),
          250,
          scrollable: scrollable,
        );
        expect(find.text('Multi-Vehicle Antifreeze / Coolant'), findsOneWidget);
        expect(find.text('719009'), findsOneWidget);
        expect(find.text('719005'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Explorer 3.0 EcoBoost AWD (298 KW) (2020 - )'),
          250,
          scrollable: scrollable,
        );
        expect(
          find.text('Explorer 3.0 EcoBoost AWD (298 KW) (2020 - )'),
          findsOneWidget,
        );

        // Copy All Specs button in top app bar
        await tester.tap(find.byTooltip('Copy All Specs'));
        await tester.pump();
        expect(copiedText, contains('2022 Ford Explorer ST'));
        expect(copiedText, contains('5W-30'));
        expect(copiedText, contains('VO-115'));
        expect(copiedText, contains('836539'));

        // Scan Next Vehicle sticky bottom button
        await tester.tap(find.text('Scan Next Vehicle'));
        await tester.pump();
        expect(scanNextTapped, isTrue);

        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets('shows retry button on retryable error and recovers on retry', (tester) async {
      var attempt = 0;
      final controller = VinLookupController(
        service: _FakeVinLookupService((_) async {
          attempt++;
          if (attempt == 1) {
            throw const VinLookupException(
              kind: VinLookupErrorKind.timeout,
              message: 'Timed out contacting VIN database.',
            );
          }
          return _explorerResult();
        }),
      );
      addTearDown(controller.dispose);

      await controller.lookupVin('1FM5K8GCXNGA77516');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: VehicleResultScreen(
            controller: controller,
            onScanNext: () {},
            onEnterDifferentVin: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Request Timed Out'), findsOneWidget);
      expect(find.text('Retry Lookup'), findsOneWidget);

      await tester.tap(find.text('Retry Lookup'));
      await tester.pumpAndSettle();

      expect(find.text('2022 Ford Explorer'), findsOneWidget);
    });
  });

  group('CameraPermissionView', () {
    testWidgets('renders settings, retry, and manual fallback actions on denial', (tester) async {
      var settingsOpened = false;
      var retried = false;
      var manualTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CameraPermissionView(
              error: const MobileScannerException(
                errorCode: MobileScannerErrorCode.permissionDenied,
              ),
              onRetryCamera: () => retried = true,
              onManualEntry: () => manualTapped = true,
              openSettingsAction: () async {
                settingsOpened = true;
                return true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Camera Permission Required'), findsOneWidget);

      await tester.tap(find.text('Open App Settings'));
      await tester.tap(find.text('Retry Camera'));
      await tester.tap(find.text('Enter VIN Manually'));

      expect(settingsOpened, isTrue);
      expect(retried, isTrue);
      expect(manualTapped, isTrue);
    });
  });

  group('ScannerScreen desktop fallback & strictness', () {
    testWidgets(
      'Normal mode accepts Elantra trailing A while Strict mode rejects it',
      (tester) async {
        String? lookedUpVin;
        final controller = VinLookupController(
          service: _FakeVinLookupService((vin) async {
            lookedUpVin = vin;
            return _explorerResult();
          }),
        );
        final feedback = _FakeFeedbackService();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: ScannerScreen(
              vinController: controller,
              validator: const VinValidator(),
              themeMode: ThemeMode.system,
              onCycleThemeMode: () {},
              feedbackService: feedback,
              cameraScannerSupportedOverride: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('VIN Spec Lookup'), findsOneWidget);
        expect(find.text('Normal'), findsOneWidget);
        expect(find.text('Strict'), findsOneWidget);

        // Elantra 18-char barcode with trailing 'A' is valid in Normal mode.
        await tester.enterText(find.byType(TextField), '5NPD84LF0KH412345A');
        await tester.pump();
        expect(find.text('Valid 17-character VIN ready'), findsOneWidget);

        // Switch to Strict mode: trailing 'A' should now be rejected.
        await tester.tap(find.text('Strict'));
        await tester.pump();
        expect(
          find.textContaining('18/17'),
          findsOneWidget,
        );

        // Switch back to Normal mode and submit.
        await tester.tap(find.text('Normal'));
        await tester.pump();
        await tester.tap(find.text('Look Up Vehicle Specs'));
        await tester.pumpAndSettle();

        expect(lookedUpVin, '5NPD84LF0KH412345');
        expect(feedback.playCount, 1);
        expect(find.text('2022 Ford Explorer'), findsOneWidget);
        expect(find.text('5W-30'), findsOneWidget);
        expect(find.text('VO-115'), findsOneWidget);
      },
    );
  });

  group('ScannerScreen OCR mode & HUD toggles', () {
    testWidgets(
      'switches between Barcode and OCR modes, updates Strictness, and plays beep on OCR VIN lock',
      (tester) async {
        final controller = VinLookupController(
          service: _FakeVinLookupService((_) async => _explorerResult()),
        );
        final feedback = _FakeFeedbackService();
        final fakeOcr = _FakeOcrService();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: ScannerScreen(
              vinController: controller,
              validator: const VinValidator(),
              themeMode: ThemeMode.dark,
              onCycleThemeMode: () {},
              feedbackService: feedback,
              ocrService: fakeOcr,
              cameraScannerSupportedOverride: true,
              ocrViewBuilder: (
                context, {
                required ocrService,
                required validator,
                required strictness,
                required scanWindow,
                required isPaused,
                required onVinRecognized,
                required onManualEntryTap,
                required onSwitchStrictnessToNormal,
              }) {
                return ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('Mock OCR (${strictness.name})'),
                        FilledButton(
                          onPressed: () =>
                              onVinRecognized('1FM5K8GCXNGA77516'),
                          child: const Text('Simulate OCR Read'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Barcode'), findsOneWidget);
        expect(find.text('OCR'), findsOneWidget);
        expect(find.text('Normal'), findsOneWidget);
        expect(find.text('Strict'), findsOneWidget);

        // Switch to OCR mode.
        await tester.tap(find.text('OCR'));
        await tester.pumpAndSettle();
        expect(find.text('Mock OCR (normal)'), findsOneWidget);

        // Toggle strictness to Strict while in OCR mode.
        await tester.tap(find.text('Strict'));
        await tester.pump();
        expect(find.text('Mock OCR (strict)'), findsOneWidget);

        // Simulate successful OCR VIN recognition -> instant BEEP + full spec screen.
        await tester.tap(find.text('Simulate OCR Read'));
        await tester.pumpAndSettle();

        expect(feedback.playCount, 1);
        expect(find.text('2022 Ford Explorer'), findsOneWidget);
        expect(find.text('5W-30'), findsOneWidget);
        expect(find.text('VO-115'), findsOneWidget);
      },
    );
  });

  group('StartupSplashOverlay', () {
    testWidgets('renders branded VinKit splash and invokes onFinished after animation', (tester) async {
      var finished = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: StartupSplashOverlay(
              duration: const Duration(milliseconds: 300),
              onFinished: () => finished = true,
            ),
          ),
        ),
      );

      expect(find.text('VinKit'), findsOneWidget);
      expect(finished, isFalse);

      await tester.pumpAndSettle();
      expect(finished, isTrue);
    });
  });

  group('ScannerControls Exposure & Gamma HUD', () {
    testWidgets(
      'expands lighting controls, applies Glare/Dark/Auto presets, and fits narrow screens',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        var isExpanded = false;
        var ev = 0.0;
        var gamma = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              backgroundColor: Colors.black,
              body: StatefulBuilder(
                builder: (context, setState) => Align(
                  alignment: Alignment.bottomCenter,
                  child: ScannerControls(
                    zoomScale: 0.0,
                    torchState: TorchState.off,
                    isCameraRunning: true,
                    onZoomChanged: (_) {},
                    onToggleTorch: () {},
                    onManualEntryTap: () {},
                    primaryActionLabel: 'Read VIN (OCR)',
                    onPrimaryActionTap: () {},
                    showLightingControls: true,
                    isLightingExpanded: isExpanded,
                    onToggleLightingPanel: () =>
                        setState(() => isExpanded = !isExpanded),
                    supportsExposureOffset: true,
                    exposureOffset: ev,
                    minExposureOffset: -2.0,
                    maxExposureOffset: 2.0,
                    onExposureChanged: (next) => setState(() => ev = next),
                    gamma: gamma,
                    onGammaChanged: (next) => setState(() => gamma = next),
                    onResetLighting: () => setState(() {
                      ev = 0.0;
                      gamma = 1.0;
                    }),
                    onApplyLightingPreset: (nextEv, nextGamma) => setState(() {
                      ev = nextEv;
                      gamma = nextGamma;
                    }),
                  ),
                ),
              ),
            ),
          ),
        );

        // Collapsed by default.
        expect(find.text('Glare'), findsNothing);
        expect(find.byTooltip('Adjust exposure & gamma'), findsOneWidget);

        // Expand lighting controls.
        await tester.tap(find.byTooltip('Adjust exposure & gamma'));
        await tester.pumpAndSettle();

        expect(find.text('Auto'), findsOneWidget);
        expect(find.text('Glare'), findsOneWidget);
        expect(find.text('Dark'), findsOneWidget);
        expect(find.text('EV'), findsOneWidget);
        expect(find.text('Gamma'), findsOneWidget);

        // Apply Glare preset.
        await tester.tap(find.text('Glare'));
        await tester.pump();
        expect(ev, closeTo(-1.2, 0.01));
        expect(gamma, closeTo(0.75, 0.01));
        expect(find.text('-1.2 EV'), findsOneWidget);
        expect(find.text('γ 0.75'), findsOneWidget);
        expect(find.text('Reset'), findsOneWidget);

        // Apply Dark preset.
        await tester.tap(find.text('Dark'));
        await tester.pump();
        expect(ev, closeTo(1.2, 0.01));
        expect(gamma, closeTo(1.45, 0.01));
        expect(find.text('+1.2 EV'), findsOneWidget);
        expect(find.text('γ 1.45'), findsOneWidget);

        // Reset back to neutral.
        await tester.tap(find.text('Reset'));
        await tester.pump();
        expect(ev, 0.0);
        expect(gamma, 1.0);
      },
    );
  });

  group('ScannerOverlay partial OCR action', () {
    testWidgets('displays partial VIN banner with working Edit action button', (tester) async {
      var editTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            backgroundColor: Colors.black,
            body: ScannerOverlay(
              scanWindow: const Rect.fromLTWH(24, 200, 320, 104),
              isPaused: false,
              showScanLine: false,
              statusMessage: 'Partial read: 5NPD84LF0KH4123',
              statusActionLabel: 'Edit',
              onStatusAction: () => editTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Partial read: 5NPD84LF0KH4123'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      expect(editTapped, isTrue);
    });
  });
}
