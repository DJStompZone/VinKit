import 'package:vinkit_app/models/json_parsers.dart';

/// Represents decoded core vehicle attributes returned by the VIN API.
class VehicleInfo {
  /// Creates an immutable [VehicleInfo] instance.
  const VehicleInfo({
    this.id,
    this.year,
    required this.make,
    required this.model,
    required this.trim,
    required this.engine,
  });

  /// Parses a [VehicleInfo] instance from a JSON object.
  factory VehicleInfo.fromJson(Map<String, dynamic> json) {
    return VehicleInfo(
      id: JsonParsers.readInt(json, 'id'),
      year: JsonParsers.readInt(json, 'year'),
      make: JsonParsers.readString(json, 'make'),
      model: JsonParsers.readString(json, 'model'),
      trim: JsonParsers.readString(json, 'trim'),
      engine: JsonParsers.readString(json, 'engine'),
    );
  }

  /// An empty [VehicleInfo] placeholder used when vehicle metadata is absent.
  static const VehicleInfo empty = VehicleInfo(
    make: '',
    model: '',
    trim: '',
    engine: '',
  );

  /// Internal database identifier for the vehicle, if provided.
  final int? id;

  /// Vehicle model year.
  final int? year;

  /// Vehicle manufacturer make name.
  final String make;

  /// Vehicle model name.
  final String model;

  /// Vehicle trim level or package name.
  final String trim;

  /// Decoded engine specification summary.
  final String engine;

  /// Returns a formatted headline combining year, make, model, and trim.
  String get displayTitle {
    final parts = <String>[
      if (year != null && year! > 0) year.toString(),
      if (make.isNotEmpty) make,
      if (model.isNotEmpty) model,
      if (trim.isNotEmpty) trim,
    ];
    return parts.isEmpty ? 'Unknown Vehicle' : parts.join(' ');
  }

  /// Whether at least one primary vehicle field was decoded.
  bool get hasDetails =>
      year != null ||
      make.isNotEmpty ||
      model.isNotEmpty ||
      trim.isNotEmpty ||
      engine.isNotEmpty;
}
