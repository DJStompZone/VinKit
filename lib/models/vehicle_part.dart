import 'package:vinkit_app/models/json_parsers.dart';

/// Represents a replacement part recommendation returned for a vehicle.
class VehiclePart {
  /// Creates an immutable [VehiclePart] instance.
  const VehiclePart({
    required this.category,
    required this.position,
    required this.brand,
    required this.partNumber,
    required this.detail,
    required this.source,
    required this.verified,
  });

  /// Parses a [VehiclePart] instance from a JSON object.
  factory VehiclePart.fromJson(Map<String, dynamic> json) {
    return VehiclePart(
      category: JsonParsers.readString(json, 'category'),
      position: JsonParsers.readString(json, 'position'),
      brand: JsonParsers.readString(json, 'brand'),
      partNumber: JsonParsers.readString(json, 'part_number'),
      detail: JsonParsers.readString(json, 'detail'),
      source: JsonParsers.readString(json, 'source'),
      verified: JsonParsers.readBool(json, 'verified'),
    );
  }

  /// Maps raw category keys to user-friendly headings.
  static const Map<String, String> _categoryLabels = <String, String>{
    'oil_filter': 'Oil Filter',
    'air_filter': 'Engine Air Filter',
    'cabin_filter': 'Cabin Air Filter',
    'fuel_filter': 'Fuel Filter',
    'battery': 'Battery',
    'wiper': 'Wiper Blades',
  };

  /// Raw category identifier such as `oil_filter` or `wiper`.
  final String category;

  /// Mounting position such as `driver`, `passenger`, or `rear`.
  final String position;

  /// Manufacturer or product line brand.
  final String brand;

  /// Part number identifier, or `NS` when non-serviceable.
  final String partNumber;

  /// Semicolon-separated specification and fitment notes.
  final String detail;

  /// Data source attribution for the recommendation.
  final String source;

  /// Whether this fitment entry is marked as verified.
  final bool verified;

  /// Returns a human-readable category title for [category].
  static String labelForCategory(String category) {
    return _categoryLabels[category] ??
        JsonParsers.titleCaseIdentifier(category);
  }

  /// Human-readable category label for this part.
  String get categoryLabel => labelForCategory(category);

  /// Human-readable mounting position label, or empty when not applicable.
  String get positionLabel => JsonParsers.titleCaseIdentifier(position);

  /// Whether this part entry represents a non-serviceable component (`NS`).
  bool get isNonServiceable =>
      partNumber.trim().toUpperCase() == 'NS' ||
      detail.toLowerCase().contains('non serviceable');

  /// Extracts a concise tier or line name from parenthesized [brand] suffixes,
  /// e.g. `Valvoline (BEAM BLADE)` -> `Beam Blade`.
  String get brandTierLabel {
    final match = RegExp(r'\(([^)]+)\)').firstMatch(brand);
    if (match == null) {
      return '';
    }
    return JsonParsers.titleCaseIdentifier(match.group(1) ?? '');
  }

  /// Base brand name with any parenthesized tier suffix removed.
  String get baseBrandName {
    final cleaned = brand.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    return cleaned.isNotEmpty ? cleaned : brand;
  }

  /// Extracts a compact wiper blade length label (e.g. `26"`) from [detail].
  String? get wiperLengthLabel {
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:in\.?|")',
      caseSensitive: false,
    ).firstMatch(detail);
    if (match == null) {
      return null;
    }
    return '${match.group(1)}"';
  }

  /// Extracts the wiper arm connector type from [detail], if present.
  String? get armConnectorLabel {
    for (final segment in detailSegments) {
      final match = RegExp(
        r'^Arm\s+Connector\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(segment);
      if (match != null) {
        final value = match.group(1)?.trim() ?? '';
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  /// Extracts the original OEM blade style from [detail], if present.
  String? get oemTypeLabel {
    for (final segment in detailSegments) {
      final match = RegExp(
        r'^Original\s*\(OEM\)\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(segment);
      if (match != null) {
        final value = match.group(1)?.trim() ?? '';
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  /// Splits semicolon-delimited [detail] notes into clean display lines.
  List<String> get detailSegments {
    if (detail.isEmpty) {
      return const <String>[];
    }
    return detail
        .split(';')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  /// Extracts structured `Key: Value` pairs from [detailSegments] (such as
  /// battery CCA, reserve capacity, and OE group).
  List<MapEntry<String, String>> get specKeyValues {
    final entries = <MapEntry<String, String>>[];
    for (final segment in detailSegments) {
      final colonIndex = segment.indexOf(':');
      if (colonIndex <= 0 || colonIndex >= segment.length - 1) {
        continue;
      }
      final key = segment.substring(0, colonIndex).trim();
      final value = segment.substring(colonIndex + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty && key.length <= 28) {
        entries.add(MapEntry<String, String>(key, value));
      }
    }
    return List<MapEntry<String, String>>.unmodifiable(entries);
  }

  /// Returns non-`Key: Value` prose notes from [detailSegments].
  List<String> get proseDetailSegments {
    final notes = <String>[];
    for (final segment in detailSegments) {
      final colonIndex = segment.indexOf(':');
      final isKeyValue = colonIndex > 0 &&
          colonIndex < segment.length - 1 &&
          segment.substring(0, colonIndex).trim().length <= 28;
      if (!isKeyValue) {
        notes.add(segment);
      }
    }
    return List<String>.unmodifiable(notes);
  }
}
