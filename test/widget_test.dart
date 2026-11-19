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
import 'package:vinkit_app/services/vin_validator.dart';
import 'package:vinkit_app/theme/app_theme.dart';
import 'package:vinkit_app/widgets/camera_permission_view.dart';
import 'package:vinkit_app/widgets/manual_vin_sheet.dart';

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
/// rendering, scanner beep feedback, error retries, clipboard copy, and camera
/// permission recovery UI.
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

  group('ScannerScreen desktop fallback', () {
    testWidgets(
      'uses DesktopVinEntryView without initializing mobile_scanner on unsupported desktop platforms',
      (tester) async {
        final controller = VinLookupController(
          service: _FakeVinLookupService((_) async => _explorerResult()),
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

        // Simulate a USB Code 39 scanner sending a leading I + wrapping asterisks.
        await tester.enterText(find.byType(TextField), '*I1FM5K8GCXNGA77516*');
        await tester.pump();
        await tester.tap(find.text('Look Up Vehicle Specs'));
        await tester.pumpAndSettle();

        expect(feedback.playCount, 1);
        expect(find.text('2022 Ford Explorer'), findsOneWidget);
        expect(find.text('5W-30'), findsOneWidget);
        expect(find.text('VO-115'), findsOneWidget);
      },
    );
  });
}
