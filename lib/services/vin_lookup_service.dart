import 'package:vinkit_app/models/vin_lookup_result.dart';

/// Contract for decoding a 17-character VIN via a backend data provider.
///
/// Implement this interface to swap out the default API endpoint or response
/// format without modifying UI or state management layers.
abstract interface class VinLookupService {
  /// Fetches vehicle and maintenance details for the given [vin].
  ///
  /// Throws a [VinLookupException] when client-side validation fails or the
  /// backend request cannot be completed.
  Future<VinLookupResult> lookupVin(String vin);

  /// Releases underlying HTTP client resources held by this service.
  void dispose();
}
