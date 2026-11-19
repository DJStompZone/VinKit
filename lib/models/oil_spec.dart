import 'package:vinkit_app/models/json_parsers.dart';

/// Represents a motor oil specification and capacity recommendation.
class OilSpec {
  /// Creates an immutable [OilSpec] instance.
  const OilSpec({
    required this.origin,
    required this.viscosity,
    required this.oilType,
    this.capacityQt,
    required this.specNotes,
    required this.source,
    required this.verified,
  });

  /// Parses an [OilSpec] instance from a JSON object.
  factory OilSpec.fromJson(Map<String, dynamic> json) {
    return OilSpec(
      origin: JsonParsers.readString(json, 'origin'),
      viscosity: JsonParsers.readString(json, 'viscosity'),
      oilType: JsonParsers.readString(json, 'oil_type'),
      capacityQt: JsonParsers.readDouble(json, 'capacity_qt'),
      specNotes: JsonParsers.readString(json, 'spec_notes'),
      source: JsonParsers.readString(json, 'source'),
      verified: JsonParsers.readBool(json, 'verified'),
    );
  }

  /// Maps raw oil type identifiers to friendly display labels.
  static const Map<String, String> _oilTypeLabels = <String, String>{
    'synthetic': 'Full Synthetic',
    'synthetic_blend': 'Synthetic Blend',
    'maxlife': 'MaxLife High Mileage',
    'conventional': 'Conventional',
  };

  /// Brand or provider origin for the specification.
  final String origin;

  /// SAE viscosity grade such as `5W-30`.
  final String viscosity;

  /// Raw oil formulation key such as `synthetic` or `synthetic_blend`.
  final String oilType;

  /// Engine oil sump capacity in US quarts.
  final double? capacityQt;

  /// Descriptive specification notes.
  final String specNotes;

  /// Data source attribution.
  final String source;

  /// Whether this oil specification is verified.
  final bool verified;

  /// Friendly display label for [oilType].
  String get oilTypeLabel =>
      _oilTypeLabels[oilType] ?? JsonParsers.titleCaseIdentifier(oilType);

  /// Formatted capacity label in US quarts, or `null` when unavailable.
  String? get formattedCapacity =>
      capacityQt == null ? null : JsonParsers.formatQuarts(capacityQt!);
}
