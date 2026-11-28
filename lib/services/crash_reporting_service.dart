import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vinkit_app/firebase_options.dart';

/// Category tag for user-submitted bug reports and feedback.
enum FeedbackCategory {
  /// Application crash, freeze, or UI bug.
  bugOrCrash('Bug / Crash'),

  /// Barcode or printed VIN OCR recognition issue.
  barcodeOrOcr('Barcode / OCR'),

  /// Missing or inaccurate decoded vehicle / part specification.
  vehicleSpecs('Vehicle Specs'),

  /// Feature request or general usability feedback.
  generalFeedback('General Feedback');

  const FeedbackCategory(this.label);

  /// Human-readable display label.
  final String label;
}

/// Synthetic non-fatal exception recorded to Crashlytics when a user manually
/// submits an in-app bug report or feedback entry.
class UserFeedbackReportException implements Exception {
  /// Creates a [UserFeedbackReportException].
  const UserFeedbackReportException({
    required this.category,
    required this.summary,
    this.vin,
  });

  /// Selected feedback category.
  final FeedbackCategory category;

  /// User-provided description summary.
  final String summary;

  /// Optional VIN attached by the user.
  final String? vin;

  @override
  String toString() {
    final vinPart =
        (vin != null && vin!.trim().isNotEmpty) ? ' [VIN: ${vin!.trim()}]' : '';
    return 'UserFeedbackReport(${category.label})$vinPart: $summary';
  }
}

/// Outcome of submitting a user bug report or feedback payload.
class FeedbackSubmissionResult {
  /// Creates a [FeedbackSubmissionResult].
  const FeedbackSubmissionResult({
    required this.formattedReport,
    required this.sentToCrashlytics,
    required this.copiedToClipboard,
  });

  /// Full formatted diagnostic report text.
  final String formattedReport;

  /// Whether the report was transmitted to Firebase Crashlytics.
  final bool sentToCrashlytics;

  /// Whether the report text was copied to the system clipboard.
  final bool copiedToClipboard;
}

/// Low-level abstraction over Firebase Core + Firebase Crashlytics so crash
/// reporting behavior can be deterministically verified in unit/widget tests.
abstract interface class CrashlyticsBackend {
  /// Whether the current platform supports native Firebase Crashlytics.
  bool get isSupported;

  /// Initializes Firebase Core and returns the persisted Crashlytics opt-in state.
  Future<bool> initialize();

  /// Enables or disables automatic Crashlytics data collection.
  Future<void> setCrashlyticsCollectionEnabled(bool enabled);

  /// Deletes any unsent crash reports queued on device.
  Future<void> deleteUnsentReports();

  /// Uploads any queued unsent crash reports when collection is disabled.
  Future<void> sendUnsentReports();

  /// Records a fatal Flutter framework error.
  Future<void> recordFlutterFatalError(FlutterErrorDetails details);

  /// Records a fatal or non-fatal caught error.
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  });

  /// Appends a breadcrumb log message to the active Crashlytics session.
  Future<void> log(String message);

  /// Associates a custom key/value pair (`String`, `int`, `double`, or `bool`)
  /// with subsequent Crashlytics reports.
  Future<void> setCustomKey(String key, Object value);
}

/// Production [CrashlyticsBackend] backed by `firebase_core` and
/// `firebase_crashlytics` on supported native platforms (Android, iOS, macOS).
class FirebaseCrashlyticsBackend implements CrashlyticsBackend {
  /// Creates a [FirebaseCrashlyticsBackend].
  const FirebaseCrashlyticsBackend();

  @override
  bool get isSupported {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS =>
        true,
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia =>
        false,
    };
  }

  bool get _supportsFirebaseCore {
    if (kIsWeb) {
      return true;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows =>
        true,
      TargetPlatform.linux || TargetPlatform.fuchsia => false,
    };
  }

  @override
  Future<bool> initialize() async {
    if (!_supportsFirebaseCore) {
      return false;
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    if (!isSupported) {
      return false;
    }
    return FirebaseCrashlytics.instance.isCrashlyticsCollectionEnabled;
  }

  @override
  Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {
    if (!isSupported) {
      return;
    }
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> deleteUnsentReports() async {
    if (!isSupported) {
      return;
    }
    await FirebaseCrashlytics.instance.deleteUnsentReports();
  }

  @override
  Future<void> sendUnsentReports() async {
    if (!isSupported) {
      return;
    }
    await FirebaseCrashlytics.instance.sendUnsentReports();
  }

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {
    if (!isSupported) {
      FlutterError.presentError(details);
      return;
    }
    await FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    if (!isSupported) {
      return;
    }
    await FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: fatal,
    );
  }

  @override
  Future<void> log(String message) async {
    if (!isSupported) {
      return;
    }
    await FirebaseCrashlytics.instance.log(message);
  }

  @override
  Future<void> setCustomKey(String key, Object value) async {
    if (!isSupported) {
      return;
    }
    await FirebaseCrashlytics.instance.setCustomKey(key, value);
  }
}

/// Manages opt-in Firebase Crashlytics error reporting, privacy-preserving VIN
/// diagnostic context, breadcrumbs, and user-initiated bug/feedback reports.
///
/// By default, collection is **disabled (opt-in)** via native manifest metadata
/// (`firebase_crashlytics_collection_enabled = false` on Android and
/// `FirebaseCrashlyticsCollectionEnabled = false` on iOS/macOS) until the user
/// explicitly enables it in Settings.
class CrashReportingService extends ChangeNotifier {
  /// Creates a [CrashReportingService].
  CrashReportingService({
    CrashlyticsBackend? backend,
    bool initialOptIn = false,
  })  : _backend = backend ?? const FirebaseCrashlyticsBackend(),
        _isOptedIn = initialOptIn;

  /// Current VinKit application version string.
  static const String appVersion = '1.0.3+2';

  static const int _maxBreadcrumbs = 25;

  final CrashlyticsBackend _backend;
  bool _isInitialized = false;
  bool _isOptedIn;
  final Map<String, Object> _customKeys = <String, Object>{};
  final List<String> _breadcrumbs = <String>[];

  FlutterExceptionHandler? _previousFlutterErrorHandler;
  ErrorCallback? _previousPlatformErrorHandler;
  bool _errorHooksInstalled = false;

  /// Whether Firebase and the Crashlytics backend have finished initializing.
  bool get isInitialized => _isInitialized;

  /// Whether the active platform supports native Firebase Crashlytics reporting.
  bool get isNativeCrashlyticsSupported => _backend.isSupported;

  /// Whether the user has opted in to automatic crash and error reporting.
  bool get isOptedIn => _isOptedIn;

  /// Unmodifiable snapshot of active diagnostic custom keys.
  Map<String, Object> get customKeys => Map<String, Object>.unmodifiable(_customKeys);

  /// Unmodifiable list of recent diagnostic breadcrumbs.
  List<String> get breadcrumbs => List<String>.unmodifiable(_breadcrumbs);

  /// Masks the 6-digit sequential production serial number of a 17-character
  /// [rawVin] (`1FM5K8GCXNGA77516` -> `1FM5K8GCXNG******`) so automatic
  /// diagnostic breadcrumbs preserve vehicle Make/Model/Year/Engine prefix
  /// without recording the unique vehicle serial number.
  static String redactVin(String? rawVin) {
    if (rawVin == null) {
      return 'none';
    }
    final cleaned = rawVin.trim().toUpperCase();
    if (cleaned.isEmpty) {
      return 'none';
    }
    if (cleaned.length >= 12) {
      return '${cleaned.substring(0, 11)}${'*' * (cleaned.length - 11)}';
    }
    final visible = (cleaned.length ~/ 2).clamp(1, cleaned.length);
    return '${cleaned.substring(0, visible)}${'*' * (cleaned.length - visible)}';
  }

  /// Initializes Firebase Core, syncs the persisted opt-in preference, and
  /// optionally wires [FlutterError.onError] and [PlatformDispatcher.instance.onError].
  Future<void> initialize({bool installErrorHooks = true}) async {
    _customKeys['app_version'] = appVersion;
    _customKeys['platform'] = kIsWeb ? 'web' : defaultTargetPlatform.name;

    try {
      final persistedOptIn = await _backend.initialize();
      _isOptedIn = persistedOptIn;
      _isInitialized = true;

      if (_isOptedIn) {
        await _backend.setCrashlyticsCollectionEnabled(true);
        await _syncAllCustomKeysToBackend();
        await _backend.log('Crashlytics initialized (opt-in enabled)');
      } else {
        await _backend.setCrashlyticsCollectionEnabled(false);
        await _backend.deleteUnsentReports();
      }
    } on MissingPluginException {
      _isInitialized = false;
    } on PlatformException catch (error) {
      debugPrint('CrashReportingService platform init warning: ${error.code}');
      _isInitialized = false;
    } catch (error) {
      debugPrint('CrashReportingService initialization skipped: $error');
      _isInitialized = false;
    }

    if (installErrorHooks && !_errorHooksInstalled) {
      _installGlobalErrorHooks();
    }
    notifyListeners();
  }

  void _installGlobalErrorHooks() {
    _errorHooksInstalled = true;
    _previousFlutterErrorHandler = FlutterError.onError;
    _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;

    FlutterError.onError = handleFlutterError;
    PlatformDispatcher.instance.onError = handlePlatformDispatcherError;
  }

  /// Restores the previous global error handlers if installed.
  void uninstallGlobalErrorHooks() {
    if (!_errorHooksInstalled) {
      return;
    }
    FlutterError.onError = _previousFlutterErrorHandler;
    PlatformDispatcher.instance.onError = _previousPlatformErrorHandler;
    _errorHooksInstalled = false;
  }

  /// Handles uncaught Flutter framework errors, forwarding to Crashlytics only
  /// when the user has opted in.
  @visibleForTesting
  void handleFlutterError(FlutterErrorDetails details) {
    if (_isOptedIn && _isInitialized && _backend.isSupported) {
      unawaited(_backend.recordFlutterFatalError(details));
      return;
    }
    if (_previousFlutterErrorHandler != null) {
      _previousFlutterErrorHandler!(details);
    } else {
      FlutterError.presentError(details);
    }
  }

  /// Handles uncaught asynchronous platform dispatcher errors, forwarding to
  /// Crashlytics only when the user has opted in.
  @visibleForTesting
  bool handlePlatformDispatcherError(Object error, StackTrace stack) {
    if (_isOptedIn && _isInitialized && _backend.isSupported) {
      unawaited(_backend.recordError(error, stack, fatal: true));
      return true;
    }
    if (_previousPlatformErrorHandler != null) {
      return _previousPlatformErrorHandler!(error, stack);
    }
    return false;
  }

  /// Updates the user's opt-in preference for automatic Crashlytics reporting.
  ///
  /// When disabled, collection is turned off immediately and any queued unsent
  /// local reports are deleted from the device.
  Future<void> setOptIn(bool enabled) async {
    if (_isOptedIn == enabled) {
      return;
    }
    _isOptedIn = enabled;
    notifyListeners();

    try {
      await _backend.setCrashlyticsCollectionEnabled(enabled);
      if (enabled) {
        await _syncAllCustomKeysToBackend();
        await _backend.log('User opted in to Crashlytics diagnostics');
      } else {
        await _backend.deleteUnsentReports();
      }
    } catch (error) {
      debugPrint('Failed updating Crashlytics opt-in preference: $error');
    }
  }

  Future<void> _syncAllCustomKeysToBackend() async {
    if (!_isOptedIn || !_isInitialized || !_backend.isSupported) {
      return;
    }
    for (final entry in _customKeys.entries) {
      try {
        await _backend.setCustomKey(entry.key, entry.value);
      } catch (_) {}
    }
  }

  /// Sets a diagnostic custom key (e.g. `capture_mode`, `strictness`) and
  /// forwards it to Crashlytics when opted in.
  Future<void> setCustomKey(String key, Object value) async {
    if (value is! String && value is! int && value is! double && value is! bool) {
      value = value.toString();
    }
    _customKeys[key] = value;
    if (!_isOptedIn || !_isInitialized || !_backend.isSupported) {
      return;
    }
    try {
      await _backend.setCustomKey(key, value);
    } catch (_) {}
  }

  /// Updates multiple scanner/application context keys at once.
  Future<void> updateDiagnosticsContext(Map<String, Object> entries) async {
    for (final entry in entries.entries) {
      await setCustomKey(entry.key, entry.value);
    }
  }

  /// Records a diagnostic breadcrumb message in the session ring buffer and
  /// forwards it to Crashlytics when opted in.
  Future<void> logBreadcrumb(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final timestamp = DateTime.now().toIso8601String();
    _breadcrumbs.add('[$timestamp] $trimmed');
    while (_breadcrumbs.length > _maxBreadcrumbs) {
      _breadcrumbs.removeAt(0);
    }
    if (!_isOptedIn || !_isInitialized || !_backend.isSupported) {
      return;
    }
    try {
      await _backend.log(trimmed);
    } catch (_) {}
  }

  /// Records a non-fatal caught exception (such as a VIN lookup server failure
  /// or native OCR error) when the user has opted in to Crashlytics.
  Future<void> recordNonFatalError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, Object>? contextKeys,
  }) async {
    await logBreadcrumb(
      'Non-fatal error${reason != null ? ' ($reason)' : ''}: $error',
    );
    if (contextKeys != null) {
      await updateDiagnosticsContext(contextKeys);
    }
    if (!_isOptedIn || !_isInitialized || !_backend.isSupported) {
      return;
    }
    try {
      await _backend.recordError(
        error,
        stackTrace ?? StackTrace.current,
        reason: reason,
        fatal: false,
      );
    } catch (_) {}
  }

  /// Builds a human-readable diagnostic summary of the current app and scanner
  /// state suitable for bug reports and clipboard sharing.
  String buildDiagnosticSummary({
    FeedbackCategory? category,
    String? description,
    String? vin,
    Map<String, String>? extraDiagnostics,
  }) {
    final buffer = StringBuffer()
      ..writeln('=== VinKit Diagnostic Report ===')
      ..writeln('App Version: $appVersion')
      ..writeln('Platform: ${kIsWeb ? 'web' : defaultTargetPlatform.name}')
      ..writeln('Timestamp: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln(
        'Crashlytics Opt-In: ${_isOptedIn ? 'Enabled' : 'Disabled (Opt-Out)'}',
      );

    if (category != null) {
      buffer.writeln('Category: ${category.label}');
    }
    if (vin != null && vin.trim().isNotEmpty) {
      buffer.writeln('Reported VIN: ${vin.trim().toUpperCase()}');
    }

    final mergedKeys = <String, String>{
      for (final entry in _customKeys.entries)
        if (entry.key != 'app_version' && entry.key != 'platform')
          entry.key: entry.value.toString(),
      ...?extraDiagnostics,
    };

    if (mergedKeys.isNotEmpty) {
      buffer.writeln('\n--- Scanner & State Context ---');
      for (final entry in mergedKeys.entries) {
        buffer.writeln('${entry.key}: ${entry.value}');
      }
    }

    if (description != null && description.trim().isNotEmpty) {
      buffer
        ..writeln('\n--- User Description ---')
        ..writeln(description.trim());
    }

    if (_breadcrumbs.isNotEmpty) {
      buffer.writeln('\n--- Recent Breadcrumbs ---');
      final recent = _breadcrumbs.length > 10
          ? _breadcrumbs.sublist(_breadcrumbs.length - 10)
          : _breadcrumbs;
      for (final crumb in recent) {
        buffer.writeln(crumb);
      }
    }

    return buffer.toString().trimRight();
  }

  /// Submits a manual user bug report or feedback entry.
  ///
  /// Copies the structured diagnostic report to the clipboard when
  /// [copyToClipboard] is `true`, and transmits a structured non-fatal
  /// [UserFeedbackReportException] to Firebase Crashlytics when supported and
  /// permitted.
  Future<FeedbackSubmissionResult> submitUserFeedback({
    required FeedbackCategory category,
    required String description,
    String? vin,
    bool includeDiagnostics = true,
    bool copyToClipboard = true,
    Map<String, String>? extraDiagnostics,
  }) async {
    final cleanedDescription = description.trim();
    final cleanedVin =
        (vin != null && vin.trim().isNotEmpty) ? vin.trim().toUpperCase() : null;

    final formatted = includeDiagnostics
        ? buildDiagnosticSummary(
            category: category,
            description: cleanedDescription,
            vin: cleanedVin,
            extraDiagnostics: extraDiagnostics,
          )
        : [
            '=== VinKit Feedback (${category.label}) ===',
            if (cleanedVin != null) 'VIN: $cleanedVin',
            cleanedDescription,
          ].join('\n');

    var copied = false;
    if (copyToClipboard) {
      try {
        await Clipboard.setData(
          ClipboardData(text: formatted),
        ).timeout(const Duration(milliseconds: 250));
        copied = true;
      } catch (_) {
        copied = false;
      }
    }

    var sentToCrashlytics = false;
    if (_isInitialized && _backend.isSupported) {
      final wasOptedIn = _isOptedIn;
      try {
        // An explicit manual bug report submission has direct user intent for
        // this single report; if automatic background reporting was off,
        // temporarily enable collection to flush the manual report and then
        // restore their opt-out setting.
        if (!wasOptedIn) {
          await _backend.setCrashlyticsCollectionEnabled(true);
        }
        await _backend.setCustomKey('feedback_category', category.label);
        if (cleanedVin != null) {
          await _backend.setCustomKey('feedback_vin', cleanedVin);
        }
        if (includeDiagnostics && extraDiagnostics != null) {
          for (final entry in extraDiagnostics.entries) {
            await _backend.setCustomKey('diag_${entry.key}', entry.value);
          }
        }
        await _backend.log('Manual user feedback submitted:\n$formatted');
        await _backend.recordError(
          UserFeedbackReportException(
            category: category,
            summary: cleanedDescription,
            vin: cleanedVin,
          ),
          StackTrace.current,
          reason: 'User-submitted feedback (${category.label})',
          fatal: false,
        );
        await _backend.sendUnsentReports();
        sentToCrashlytics = true;
      } catch (error) {
        debugPrint('Failed sending user feedback to Crashlytics: $error');
      } finally {
        if (!wasOptedIn) {
          try {
            await _backend.setCrashlyticsCollectionEnabled(false);
          } catch (_) {}
        }
      }
    }

    await logBreadcrumb('User feedback submitted (${category.label})');

    return FeedbackSubmissionResult(
      formattedReport: formatted,
      sentToCrashlytics: sentToCrashlytics,
      copiedToClipboard: copied,
    );
  }
}
