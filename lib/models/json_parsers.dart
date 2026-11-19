/// Shared defensive JSON parsing and formatting helpers for domain models.
abstract final class JsonParsers {
  /// Reads a trimmed string value for [key], returning an empty string if missing.
  static String readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  /// Reads an integer value for [key], parsing numeric strings when needed.
  static int? readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  /// Reads a floating-point value for [key], parsing numeric strings when needed.
  static double? readDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  /// Reads a boolean value for [key], defaulting to `false`.
  static bool readBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      return value.trim().toLowerCase() == 'true';
    }
    return false;
  }

  /// Converts a dynamic [value] to a string-keyed map when valid.
  static Map<String, dynamic>? readMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), entryValue),
      );
    }
    return null;
  }

  /// Converts a dynamic list [value] into a list of string-keyed maps.
  static List<Map<String, dynamic>> readMapList(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    final result = <Map<String, dynamic>>[];
    for (final item in value) {
      final parsed = readMap(item);
      if (parsed != null) {
        result.add(parsed);
      }
    }
    return result;
  }

  /// Converts a snake_case or lowercase [raw] identifier into Title Case words.
  static String titleCaseIdentifier(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final words = trimmed
        .split(RegExp(r'[_\s]+'))
        .where((word) => word.isNotEmpty);
    return words
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  /// Formats a fluid capacity [quarts] value into a compact readable string.
  static String formatQuarts(double quarts) {
    final formatted =
        quarts.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return '$formatted qt';
  }
}
