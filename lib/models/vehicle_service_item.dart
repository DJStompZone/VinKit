import 'package:vinkit_app/models/json_parsers.dart';

/// Represents a fluid or maintenance service recommendation for a vehicle.
class VehicleServiceItem {
  /// Creates an immutable [VehicleServiceItem] instance.
  const VehicleServiceItem({
    required this.service,
    this.intervalMi,
    this.intervalMo,
    required this.origin,
    required this.notes,
    required this.source,
    required this.verified,
  });

  /// Parses a [VehicleServiceItem] instance from a JSON object.
  factory VehicleServiceItem.fromJson(Map<String, dynamic> json) {
    return VehicleServiceItem(
      service: JsonParsers.readString(json, 'service'),
      intervalMi: JsonParsers.readInt(json, 'interval_mi'),
      intervalMo: JsonParsers.readInt(json, 'interval_mo'),
      origin: JsonParsers.readString(json, 'origin'),
      notes: JsonParsers.readString(json, 'notes'),
      source: JsonParsers.readString(json, 'source'),
      verified: JsonParsers.readBool(json, 'verified'),
    );
  }

  /// System or service heading such as `Cooling system` or `Transferbox`.
  final String service;

  /// Recommended mileage interval, if specified.
  final int? intervalMi;

  /// Recommended time interval in months, if specified.
  final int? intervalMo;

  /// Provider origin name.
  final String origin;

  /// Fluid specification and product code notes.
  final String notes;

  /// Data source attribution.
  final String source;

  /// Whether this recommendation is verified.
  final bool verified;

  static final RegExp _codesBlockPattern = RegExp(
    r'\s*\(Codes:\s*\[([^\]]*)\]\s*\)\s*$',
    caseSensitive: false,
  );

  /// Formatted service interval summary, or `null` when intervals are omitted.
  String? get formattedInterval {
    final parts = <String>[
      if (intervalMi != null && intervalMi! > 0) '$intervalMi mi',
      if (intervalMo != null && intervalMo! > 0) '$intervalMo mo',
    ];
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' / ');
  }

  /// Human-readable fluid or service note with any trailing `(Codes: [...])`
  /// catalog block stripped.
  String get cleanNotes {
    if (notes.isEmpty) {
      return '';
    }
    return notes.replaceFirst(_codesBlockPattern, '').trim();
  }

  /// Extracts catalog product codes embedded in trailing `(Codes: [...])` notes.
  List<String> get productCodes {
    final match = _codesBlockPattern.firstMatch(notes);
    if (match == null) {
      return const <String>[];
    }
    final inner = match.group(1) ?? '';
    final codes = <String>[];
    for (final rawToken in inner.split(',')) {
      final cleaned = rawToken.trim().replaceAll(RegExp(r'^["\x27]|["\x27]$'), '').trim();
      if (cleaned.isNotEmpty) {
        codes.add(cleaned);
      }
    }
    return List<String>.unmodifiable(codes);
  }
}
