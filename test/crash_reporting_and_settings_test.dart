import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vinkit_app/models/oil_spec.dart';
import 'package:vinkit_app/models/vehicle_info.dart';
import 'package:vinkit_app/models/vehicle_part.dart';
import 'package:vinkit_app/models/vehicle_service_item.dart';
import 'package:vinkit_app/models/vf_match.dart';
import 'package:vinkit_app/models/vin_lookup_result.dart';
import 'package:vinkit_app/screens/scanner_screen.dart';
import 'package:vinkit_app/services/camera_permission_service.dart';
import 'package:vinkit_app/services/crash_reporting_service.dart';
import 'package:vinkit_app/services/vin_lookup_controller.dart';
import 'package:vinkit_app/services/vin_lookup_service.dart';
import 'package:vinkit_app/services/vin_ocr_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';
import 'package:vinkit_app/theme/app_theme.dart';

class _FakeCrashlyticsBackend implements CrashlyticsBackend {
  _FakeCrashlyticsBackend({
    this.persistedOptIn = false,
  });

  @override
  bool get isSupported => true;

  bool persistedOptIn;
  bool collectionEnabled = false;
  int deleteUnsentCount = 0;
  int sendUnsentCount = 0;
  final List<FlutterErrorDetails> fatalFlutterErrors = <FlutterErrorDetails>[];
  final List<Object> recordedErrors = <Object>[];
  final List<bool> recordedFatalFlags = <bool>[];
  final List<String> logs = <String>[];
  final Map<String, Object> customKeys = <String, Object>{};

  @override
  Future<bool> initialize() async {
    collectionEnabled = persistedOptIn;
    return persistedOptIn;
  }

  @override
  Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {
    collectionEnabled = enabled;
    persistedOptIn = enabled;
  }

  @override
  Future<void> deleteUnsentReports() async {
    deleteUnsentCount++;
  }

  @override
  Future<void> sendUnsentReports() async {
    sendUnsentCount++;
  }

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {
    fatalFlutterErrors.add(details);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    recordedErrors.add(error);
    recordedFatalFlags.add(fatal);
  }

  @override
  Future<void> log(String message) async {
    logs.add(message);
  }

  @override
  Future<void> setCustomKey(String key, Object value) async {
    customKeys[key] = value;
  }
}

class _FakePermissionService implements CameraPermissionService {
  CameraPermissionState status = CameraPermissionState.granted;
  int openSettingsCount = 0;

  @override
  Future<CameraPermissionState> checkStatus() async => status;

  @override
  Future<CameraPermissionState> requestPermission() async => status;

  @override
  Future<bool> openSettings() async {
    openSettingsCount++;
    return true;
  }
}

class _FakeVinLookupService implements VinLookupService {
  @override
  Future<VinLookupResult> lookupVin(String vin) async {
    return VinLookupResult(
      vin: vin,
      vehicle: const VehicleInfo(
        id: 1,
        year: 2022,
        make: 'Ford',
        model: 'Explorer',
        trim: 'ST',
        engine: '3.0L V6',
      ),
      partsByCategory: const <String, List<VehiclePart>>{},
      oilSpecs: const <OilSpec>[],
      services: const <VehicleServiceItem>[],
      vfMatches: const <VfMatch>[],
    );
  }

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
  Future<VinOcrResult> recognizeText(
    String imagePath, {
    String? requestId,
  }) async =>
      const VinOcrResult(blocks: <VinOcrTextBlock>[]);

  @override
  Future<void> cancelPendingRecognition(String requestId) async {}

  @override
  Future<void> deleteTempImage(String imagePath) async {}
}

void main() {
  group('CrashReportingService (opt-in Crashlytics)', () {
    test('defaults to opt-out, deletes unsent reports, and masks VIN serials', () async {
      final backend = _FakeCrashlyticsBackend(persistedOptIn: false);
      final service = CrashReportingService(backend: backend);
      addTearDown(() {
        service.uninstallGlobalErrorHooks();
        service.dispose();
      });

      await service.initialize(installErrorHooks: false);

      expect(service.isInitialized, isTrue);
      expect(service.isOptedIn, isFalse);
      expect(backend.collectionEnabled, isFalse);
      expect(backend.deleteUnsentCount, 1);

      // Errors and breadcrumbs are not sent to backend while opted out.
      await service.logBreadcrumb('Scanner opened');
      await service.recordNonFatalError(
        StateError('Test non-fatal'),
        StackTrace.current,
      );
      service.handlePlatformDispatcherError(
        StateError('Uncaught async'),
        StackTrace.current,
      );

      expect(backend.logs, isEmpty);
      expect(backend.recordedErrors, isEmpty);

      // VIN redaction masks the 6-digit production serial number.
      expect(
        CrashReportingService.redactVin('1FM5K8GCXNGA77516'),
        '1FM5K8GCXNG******',
      );
    });

    test('enabling opt-in forwards fatal/non-fatal errors and disabling deletes unsent reports', () async {
      final backend = _FakeCrashlyticsBackend(persistedOptIn: false);
      final service = CrashReportingService(backend: backend);
      addTearDown(() {
        service.uninstallGlobalErrorHooks();
        service.dispose();
      });

      await service.initialize(installErrorHooks: false);
      await service.setCustomKey('strictness', 'normal');
      expect(backend.customKeys, isEmpty);

      // Opt in.
      await service.setOptIn(true);
      expect(service.isOptedIn, isTrue);
      expect(backend.collectionEnabled, isTrue);
      expect(backend.customKeys['strictness'], 'normal');
      expect(backend.customKeys['app_version'], CrashReportingService.appVersion);

      // Fatal Flutter and PlatformDispatcher errors are now recorded.
      final details = FlutterErrorDetails(
        exception: Exception('Widget render crash'),
        stack: StackTrace.current,
      );
      service.handleFlutterError(details);
      expect(backend.fatalFlutterErrors, hasLength(1));

      final handled = service.handlePlatformDispatcherError(
        StateError('Async crash'),
        StackTrace.current,
      );
      expect(handled, isTrue);
      expect(backend.recordedErrors, hasLength(1));
      expect(backend.recordedFatalFlags.last, isTrue);

      // Opt back out.
      await service.setOptIn(false);
      expect(service.isOptedIn, isFalse);
      expect(backend.collectionEnabled, isFalse);
      expect(backend.deleteUnsentCount, 2);
    });

    test('submitUserFeedback sends structured report and restores opt-out state', () async {
      final backend = _FakeCrashlyticsBackend(persistedOptIn: false);
      final service = CrashReportingService(backend: backend);
      addTearDown(service.dispose);

      await service.initialize(installErrorHooks: false);

      final result = await service.submitUserFeedback(
        category: FeedbackCategory.barcodeOrOcr,
        description: 'Glare on windshield barcode prevented lock',
        vin: '1FM5K8GCXNGA77516',
        copyToClipboard: false,
        extraDiagnostics: const <String, String>{
          'capture_mode': 'barcode',
          'strictness': 'strict',
        },
      );

      expect(result.sentToCrashlytics, isTrue);
      expect(result.formattedReport, contains('Barcode / OCR'));
      expect(result.formattedReport, contains('1FM5K8GCXNGA77516'));
      expect(result.formattedReport, contains('strictness: strict'));
      expect(backend.recordedErrors.last, isA<UserFeedbackReportException>());
      expect(backend.sendUnsentCount, 1);
      // Restores collectionEnabled to false because user was opted out of automatic background collection.
      expect(backend.collectionEnabled, isFalse);
    });
  });

  group('SettingsSheet UI & ScannerScreen integration', () {
    testWidgets(
      'opens SettingsSheet from ScannerScreen HUD, toggles Crashlytics opt-in, resets state, and submits feedback',
      (tester) async {
        final backend = _FakeCrashlyticsBackend(persistedOptIn: false);
        final crashService = CrashReportingService(backend: backend);
        await crashService.initialize(installErrorHooks: false);
        addTearDown(crashService.dispose);

        final permissions = _FakePermissionService();
        final controller = VinLookupController(
          service: _FakeVinLookupService(),
          crashReportingService: crashService,
        );
        addTearDown(controller.dispose);

        var currentThemeMode = ThemeMode.system;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setHostState) => MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: currentThemeMode,
              home: ScannerScreen(
                vinController: controller,
                validator: const VinValidator(),
                themeMode: currentThemeMode,
                onCycleThemeMode: () {},
                onThemeModeChanged: (mode) =>
                    setHostState(() => currentThemeMode = mode),
                ocrService: const _FakeOcrService(),
                permissionService: permissions,
                crashReportingService: crashService,
                initialStrictness: VinScanStrictness.strict,
                cameraScannerSupportedOverride: true,
                ocrViewBuilder: (
                  context, {
                  required ocrService,
                  required validator,
                  required strictness,
                  required scanWindow,
                  required isPaused,
                  required isBarcodeMode,
                  required isContinuous,
                  required onVinRecognized,
                  required onManualEntryTap,
                  required onSwitchStrictnessToNormal,
                }) =>
                    Text('Camera View (${strictness.name}, paused=$isPaused)'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Camera View (strict, paused=false)'), findsOneWidget);

        // Open Settings from the top-right HUD gear button.
        await tester.tap(find.byKey(const Key('open_settings_button')));
        await tester.pumpAndSettle();

        expect(find.text('Settings & Diagnostics'), findsOneWidget);
        expect(find.text('Opt-In (Off)'), findsOneWidget);

        // Toggle Crashlytics Opt-In ON.
        await tester.tap(find.byKey(const Key('settings_crashlytics_switch')));
        await tester.pumpAndSettle();

        expect(crashService.isOptedIn, isTrue);
        expect(find.text('Opted In'), findsOneWidget);

        // Reset scanner state & temp cache (resets strictness from Strict back to Normal).
        await tester.ensureVisible(
          find.byKey(const Key('settings_reset_state_button')),
        );
        await tester.tap(find.byKey(const Key('settings_reset_state_button')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Scanner state, lighting controls, and temporary cache reset'),
          findsOneWidget,
        );

        // Submit a manual bug report / feedback.
        final descriptionField = find.byKey(
          const Key('settings_feedback_description_field'),
        );
        await tester.ensureVisible(descriptionField);
        await tester.enterText(
          descriptionField,
          'Door jamb sticker had low contrast in garage lighting.',
        );
        await tester.pump();

        final submitButton = find.byKey(
          const Key('settings_submit_feedback_button'),
        );
        await tester.ensureVisible(submitButton);
        await tester.tap(submitButton);
        await tester.pumpAndSettle();

        expect(backend.recordedErrors, isNotEmpty);
        expect(
          backend.recordedErrors.last,
          isA<UserFeedbackReportException>(),
        );

        // Close Settings sheet and confirm scanner resumes with reset Normal strictness.
        await tester.tap(find.byTooltip('Close Settings'));
        await tester.pumpAndSettle();

        expect(find.text('Camera View (normal, paused=false)'), findsOneWidget);
      },
    );
  });
}
