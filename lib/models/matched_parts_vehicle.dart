import 'package:vinkit_app/models/json_parsers.dart';

/// Represents a secondary matched vehicle entry used for parts lookup.
class MatchedPartsVehicle {
  /// Creates an immutable [MatchedPartsVehicle] instance.
  const MatchedPartsVehicle({
    this.id,
    this.year,
    required this.make,
    required this.model,
    required this.trim,
    required this.engine,
    this.matchScore,
    required this.matchType,
  });

  /// Parses a [MatchedPartsVehicle] instance from a JSON object.
  factory MatchedPartsVehicle.fromJson(Map<String, dynamic> json) {
    return MatchedPartsVehicle(
      id: JsonParsers.readInt(json, 'id'),
      year: JsonParsers.readInt(json, 'year'),
      make: JsonParsers.readString(json, 'make'),
      model: JsonParsers.readString(json, 'model'),
      trim: JsonParsers.readString(json, 'trim'),
      engine: JsonParsers.readString(json, 'engine'),
      matchScore: JsonParsers.readInt(json, 'match_score'),
      matchType: JsonParsers.readString(json, 'match_type'),
    );
  }

  /// Catalog identifier for the matched vehicle.
  final int? id;

  /// Matched model year.
  final int? year;

  /// Matched vehicle make.
  final String make;

  /// Matched vehicle model.
  final String model;

  /// Matched vehicle trim.
  final String trim;

  /// Matched engine description.
  final String engine;

  /// Confidence score produced by the catalog matching algorithm.
  final int? matchScore;

  /// Strategy identifier explaining how the catalog match was resolved.
  final String matchType;

  /// Formatted summary combining year, make, model, trim, and engine.
  String get summary {
    final tokens = <String>[
      if (year != null && year! > 0) year.toString(),
      if (make.isNotEmpty) make,
      if (model.isNotEmpty) model,
      if (trim.isNotEmpty) trim,
      if (engine.isNotEmpty) engine,
    ];
    return tokens.join(' ');
  }
}
