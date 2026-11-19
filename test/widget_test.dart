import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vinkit_app/models/oil_spec.dart';
import 'package:vinkit_app/models/vehicle_info.dart';
import 'package:vinkit_app/models/vehicle_part.dart';
import 'package:vinkit_app/models/vehicle_service_item.dart';
import 'package:vinkit_app/models/vin_lookup_exception.dart';
import 'package:vinkit_app/models/vin_lookup_result.dart';
import 'package:vinkit_app/services/vin_lookup_controller.dart';
import 'package:vinkit_app/services/vin_lookup_service.dart';
import 'package:vinkit_app/theme/app_theme.dart';
import 'package:vinkit_app/widgets/camera_permission_view.dart';
import 'package:vinkit_app/widgets/manual_vin_sheet.dart';
import 'package:vinkit_app/widgets/vehicle_result_sheet.dart';

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
      'wiper': <VehiclePart>[
        VehiclePart(
          category: 'wiper',
          position: 'driver',
          brand: 'Valvoline (BEAM BLADE)',
          partNumber: '836539',
          detail: 'FRONT LEFT | 26 in.; Arm Connector: PT 15',
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
    ],
    services: <VehicleServiceItem>[
      VehicleServiceItem(
        service: 'Cooling system',
        origin: 'Valvoline',
        notes: 'Multi-Vehicle Antifreeze / Coolant',
        source: 'Valvoline Product Finder',
        verified: true,
      ),
    ],
    vfMatches: [],
  );
}

/// Widget tests covering manual entry validation, vehicle result rendering,
/// error retries, clipboard copy, and camera permission recovery UI.
void main() {
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

  group('VehicleResultSheet', () {
    testWidgets('shows loading, decoded vehicle details, and copies raw VIN', (tester) async {
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
          home: Scaffold(
            body: VehicleResultSheet(
              controller: controller,
              onScanNext: () => scanNextTapped = true,
              onEnterDifferentVin: () {},
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('1FM5K8GCXNGA77516'), findsOneWidget);

      completer.complete(_explorerResult());
      await tester.pumpAndSettle();

      expect(find.text('2022 Ford Explorer ST'), findsOneWidget);
      expect(find.text('3.0L V6 GTDI'), findsOneWidget);
      expect(find.text('VO-115'), findsOneWidget);

      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copiedText, '1FM5K8GCXNGA77516');
      expect(find.text('Copied'), findsOneWidget);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('836539'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('836539'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Full Synthetic'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Full Synthetic'), findsOneWidget);

      await tester.tap(find.text('Scan Next Vehicle'));
      await tester.pump();
      expect(scanNextTapped, isTrue);

      await tester.pump(const Duration(seconds: 3));
    });

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
          home: Scaffold(
            body: VehicleResultSheet(
              controller: controller,
              onScanNext: () {},
              onEnterDifferentVin: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Request Timed Out'), findsOneWidget);
      expect(find.text('Retry Lookup'), findsOneWidget);

      await tester.tap(find.text('Retry Lookup'));
      await tester.pumpAndSettle();

      expect(find.text('2022 Ford Explorer ST'), findsOneWidget);
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
}
