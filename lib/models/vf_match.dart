import 'package:vinkit_app/models/json_parsers.dart';

/// Represents an engine match entry from the Valvoline Product Finder catalog.
class VfMatch {
  /// Creates an immutable [VfMatch] instance.
  const VfMatch({
    required this.engineId,
    this.matchScore,
    required this.matchType,
    required this.make,
    required this.modelRaw,
    required this.engineRaw,
    required this.region,
    this.yearFrom,
    this.yearTo,
    this.displacementL,
    required this.grade,
    this.capacityQt,
  });

  /// Parses a [VfMatch] instance from a JSON object.
  factory VfMatch.fromJson(Map<String, dynamic> json) {
    return VfMatch(
      engineId: JsonParsers.readString(json, 'engine_id'),
      matchScore: JsonParsers.readInt(json, 'match_score'),
      matchType: JsonParsers.readString(json, 'match_type'),
      make: JsonParsers.readString(json, 'make'),
      modelRaw: JsonParsers.readString(json, 'model_raw'),
      engineRaw: JsonParsers.readString(json, 'engine_raw'),
      region: JsonParsers.readString(json, 'region'),
      yearFrom: JsonParsers.readInt(json, 'year_from'),
      yearTo: JsonParsers.readInt(json, 'year_to'),
      displacementL: JsonParsers.readDouble(json, 'displacement_l'),
      grade: JsonParsers.readString(json, 'grade'),
      capacityQt: JsonParsers.readDouble(json, 'capacity_qt'),
    );
  }

  /// Catalog engine identifier.
  final String engineId;

  /// Match score assigned by the catalog matcher.
  final int? matchScore;

  /// Match strategy name such as `exact_displacement`.
  final String matchType;

  /// Matched manufacturer make.
  final String make;

  /// Raw catalog model label.
  final String modelRaw;

  /// Raw catalog engine description.
  final String engineRaw;

  /// Market region code, if specified.
  final String region;

  /// First applicable model year.
  final int? yearFrom;

  /// Last applicable model year.
  final int? yearTo;

  /// Engine displacement in liters.
  final double? displacementL;

  /// Recommended oil viscosity grade.
  final String grade;

  /// Recommended oil capacity in US quarts.
  final double? capacityQt;
}
