/// Categorizes failures that can occur during VIN validation or lookup.
enum VinLookupErrorKind {
  /// Input failed client-side 17-character VIN validation.
  invalidVin,

  /// Backend could not decode or locate the requested VIN.
  notFound,

  /// Device lacks connectivity or failed to reach the host.
  network,

  /// Request exceeded connection, send, or receive timeouts.
  timeout,

  /// Backend returned an unexpected 5xx server failure.
  serverError,

  /// Backend returned an unexpected or malformed payload.
  parseError,

  /// Unclassified lookup failure.
  unknown,
}

/// Exception thrown when validating or decoding a VIN fails.
class VinLookupException implements Exception {
  /// Creates a [VinLookupException] describing the failure.
  const VinLookupException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.cause,
  });

  /// Classified error category.
  final VinLookupErrorKind kind;

  /// User-facing explanation of the failure.
  final String message;

  /// HTTP status code associated with the failure, if applicable.
  final int? statusCode;

  /// Underlying exception or error object, if captured.
  final Object? cause;

  /// Whether retrying the exact same network request may succeed.
  bool get isRetryable => switch (kind) {
        VinLookupErrorKind.network ||
        VinLookupErrorKind.timeout ||
        VinLookupErrorKind.serverError ||
        VinLookupErrorKind.unknown =>
          true,
        VinLookupErrorKind.invalidVin ||
        VinLookupErrorKind.notFound ||
        VinLookupErrorKind.parseError =>
          false,
      };

  @override
  String toString() =>
      'VinLookupException($kind, statusCode: $statusCode, message: $message)';
}
