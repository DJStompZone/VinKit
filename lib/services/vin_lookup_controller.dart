import 'package:flutter/foundation.dart';
import 'package:vinkit_app/models/vin_lookup_exception.dart';
import 'package:vinkit_app/models/vin_lookup_state.dart';
import 'package:vinkit_app/services/vin_lookup_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';

/// Coordinates VIN validation, lookup execution, retries, and state resets.
class VinLookupController extends ChangeNotifier {
  /// Creates a [VinLookupController] backed by [service] and [validator].
  VinLookupController({
    required this.service,
    this.validator = const VinValidator(),
  });

  /// Service used to fetch decoded vehicle data for a validated VIN.
  final VinLookupService service;

  /// Validator used to normalize and validate candidate VINs.
  final VinValidator validator;

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
    final requestId = ++_activeRequestId;
    _lastVin = normalizedVin;
    _state = VinLookupLoading(vin: normalizedVin);
    _notify();

    try {
      final result = await service.lookupVin(normalizedVin);
      if (_disposed || requestId != _activeRequestId) {
        return;
      }
      _state = VinLookupSuccess(result: result);
    } on VinLookupException catch (error) {
      if (_disposed || requestId != _activeRequestId) {
        return;
      }
      _state = VinLookupFailure(vin: normalizedVin, error: error);
    } catch (error) {
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
