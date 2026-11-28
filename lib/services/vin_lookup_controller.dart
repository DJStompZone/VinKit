import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vinkit_app/models/vin_lookup_exception.dart';
import 'package:vinkit_app/models/vin_lookup_state.dart';
import 'package:vinkit_app/services/crash_reporting_service.dart';
import 'package:vinkit_app/services/vin_lookup_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';

/// Coordinates VIN validation, lookup execution, retries, and state resets.
class VinLookupController extends ChangeNotifier {
  /// Creates a [VinLookupController] backed by [service] and [validator].
  VinLookupController({
    required this.service,
    this.validator = const VinValidator(),
    this.crashReportingService,
  });

  /// Service used to fetch decoded vehicle data for a validated VIN.
  final VinLookupService service;

  /// Validator used to normalize and validate candidate VINs.
  final VinValidator validator;

  /// Optional opt-in crash and diagnostic reporting service.
  final CrashReportingService? crashReportingService;

  VinLookupState _state = const VinLookupIdle();
  String? _lastVin;
  int _activeRequestId = 0;
  bool _disposed = false;

  /// Current lifecycle state of the VIN lookup flow.
  VinLookupState get state => _state;

  /// Last normalized VIN requested, if any.
  String? get lastVin => _lastVin;

  /// Validates [rawVin] and queries the backend service when valid.
  Future<void> lookupVin(String rawVin) async {
    if (_disposed) {
      return;
    }

    final validation = validator.validate(rawVin);
    if (!validation.isValid) {
      _activeRequestId++;
      _lastVin = validation.normalizedVin;
      _state = VinLookupFailure(
        vin: validation.normalizedVin,
        error: VinLookupException(
          kind: VinLookupErrorKind.invalidVin,
          message: validation.errorMessage ?? 'Invalid VIN.',
        ),
      );
      _notify();
      return;
    }

    final normalizedVin = validation.normalizedVin;
    final redactedVin = CrashReportingService.redactVin(normalizedVin);
    final requestId = ++_activeRequestId;
    _lastVin = normalizedVin;
    _state = VinLookupLoading(vin: normalizedVin);
    _notify();

    unawaited(
      crashReportingService?.logBreadcrumb('VIN lookup started ($redactedVin)'),
    );

    try {
      final result = await service.lookupVin(normalizedVin);
      if (_disposed || requestId != _activeRequestId) {
        return;
      }
      _state = VinLookupSuccess(result: result);
      unawaited(
        crashReportingService?.logBreadcrumb(
          'VIN lookup succeeded ($redactedVin)',
        ),
      );
    } on VinLookupException catch (error) {
      if (_disposed || requestId != _activeRequestId) {
        return;
      }
      _state = VinLookupFailure(vin: normalizedVin, error: error);
      // Report unexpected server or payload parsing issues as non-fatal
      // diagnostics when the user has opted in to Crashlytics.
      if (error.kind == VinLookupErrorKind.serverError ||
          error.kind == VinLookupErrorKind.parseError ||
          error.kind == VinLookupErrorKind.unknown) {
        unawaited(
          crashReportingService?.recordNonFatalError(
            error,
            StackTrace.current,
            reason: 'VIN lookup failure (${error.kind.name})',
            contextKeys: <String, Object>{
              'last_lookup_error_kind': error.kind.name,
              'last_lookup_vin_prefix': redactedVin,
              if (error.statusCode != null)
                'last_lookup_status_code': error.statusCode!,
            },
          ),
        );
      } else {
        unawaited(
          crashReportingService?.logBreadcrumb(
            'VIN lookup ${error.kind.name} ($redactedVin)',
          ),
        );
      }
    } catch (error, stackTrace) {
      if (_disposed || requestId != _activeRequestId) {
        return;
      }
      _state = VinLookupFailure(
        vin: normalizedVin,
        error: VinLookupException(
          kind: VinLookupErrorKind.unknown,
          message: 'Unexpected error decoding VIN.',
          cause: error,
        ),
      );
      unawaited(
        crashReportingService?.recordNonFatalError(
          error,
          stackTrace,
          reason: 'Unhandled VIN lookup exception',
          contextKeys: <String, Object>{
            'last_lookup_error_kind': VinLookupErrorKind.unknown.name,
            'last_lookup_vin_prefix': redactedVin,
          },
        ),
      );
    }

    _notify();
  }

  /// Retries the most recently attempted VIN lookup.
  Future<void> retry() async {
    final vin = _lastVin;
    if (vin == null || vin.isEmpty) {
      return;
    }
    await lookupVin(vin);
  }

  /// Resets the state to idle and discards any in-flight request completions.
  void reset() {
    if (_disposed) {
      return;
    }
    _activeRequestId++;
    _lastVin = null;
    if (_state is! VinLookupIdle) {
      _state = const VinLookupIdle();
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
