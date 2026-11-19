import 'package:vinkit_app/models/vin_lookup_exception.dart';
import 'package:vinkit_app/models/vin_lookup_result.dart';

/// Represents the asynchronous lifecycle state of a VIN lookup request.
sealed class VinLookupState {
  /// Base constructor for [VinLookupState] variants.
  const VinLookupState();
}

/// Initial state when no lookup is active or displayed.
final class VinLookupIdle extends VinLookupState {
  /// Creates an idle [VinLookupState].
  const VinLookupIdle();
}

/// Active state while a VIN lookup request is in flight.
final class VinLookupLoading extends VinLookupState {
  /// Creates a loading [VinLookupState] for [vin].
  const VinLookupLoading({required this.vin});

  /// Normalized VIN currently being requested.
  final String vin;
}

/// Completed state carrying the decoded [result].
final class VinLookupSuccess extends VinLookupState {
  /// Creates a success [VinLookupState] carrying [result].
  const VinLookupSuccess({required this.result});

  /// Decoded vehicle, parts, oil, and service data.
  final VinLookupResult result;
}

/// Failed state carrying the [vin] attempted and structured [error].
final class VinLookupFailure extends VinLookupState {
  /// Creates a failure [VinLookupState] for [vin] and [error].
  const VinLookupFailure({
    required this.vin,
    required this.error,
  });

  /// VIN associated with the failed attempt.
  final String vin;

  /// Structured error explaining why the lookup failed.
  final VinLookupException error;
}
