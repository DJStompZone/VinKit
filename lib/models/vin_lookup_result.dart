import 'package:vinkit_app/models/json_parsers.dart';
import 'package:vinkit_app/models/matched_parts_vehicle.dart';
import 'package:vinkit_app/models/oil_spec.dart';
import 'package:vinkit_app/models/vehicle_info.dart';
import 'package:vinkit_app/models/vehicle_part.dart';
import 'package:vinkit_app/models/vehicle_service_item.dart';
import 'package:vinkit_app/models/vf_match.dart';

/// Represents the full decoded vehicle, parts, oil, and service payload for a VIN.
class VinLookupResult {
  /// Creates an immutable [VinLookupResult] instance.
  const VinLookupResult({
    required this.vin,
    required this.vehicle,
    this.matchedPartsVehicle,
    required this.partsByCategory,
    required this.oilSpecs,
    required this.services,
    required this.vfMatches,
  });

  /// Parses a [VinLookupResult] from the API JSON payload, using [fallbackVin]
  /// if the response omits the `vin` field.
  factory VinLookupResult.fromJson(
    Map<String, dynamic> json, {
    required String fallbackVin,
  }) {
    final parsedVin = JsonParsers.readString(json, 'vin');
    final vehicleMap = JsonParsers.readMap(json['vehicle']);
    final matchedMap = JsonParsers.readMap(json['matched_parts_vehicle']);

    final rawCategories = JsonParsers.readMap(json['parts_by_category']);
    final parsedParts = <String, List<VehiclePart>>{};
    if (rawCategories != null) {
      for (final entry in rawCategories.entries) {
        final items = JsonParsers.readMapList(entry.value)
            .map(VehiclePart.fromJson)
            .toList(growable: false);
        if (items.isNotEmpty) {
          parsedParts[entry.key] = List<VehiclePart>.unmodifiable(items);
        }
      }
    }

    final parsedOilSpecs = JsonParsers.readMapList(json['oil_specs'])
        .map(OilSpec.fromJson)
        .toList(growable: false);
    final parsedServices = JsonParsers.readMapList(json['services'])
        .map(VehicleServiceItem.fromJson)
        .toList(growable: false);
    final parsedVfMatches = JsonParsers.readMapList(json['vf_matches'])
        .map(VfMatch.fromJson)
        .toList(growable: false);

    return VinLookupResult(
      vin: parsedVin.isNotEmpty ? parsedVin.toUpperCase() : fallbackVin,
      vehicle: vehicleMap == null
          ? VehicleInfo.empty
          : VehicleInfo.fromJson(vehicleMap),
      matchedPartsVehicle: matchedMap == null
          ? null
          : MatchedPartsVehicle.fromJson(matchedMap),
      partsByCategory: Map<String, List<VehiclePart>>.unmodifiable(parsedParts),
      oilSpecs: List<OilSpec>.unmodifiable(parsedOilSpecs),
      services: List<VehicleServiceItem>.unmodifiable(parsedServices),
      vfMatches: List<VfMatch>.unmodifiable(parsedVfMatches),
    );
  }

  /// Ordered filter category keys displayed prominently on the spec screen.
  static const List<String> filterCategoryOrder = <String>[
    'oil_filter',
    'air_filter',
    'cabin_filter',
    'fuel_filter',
  ];

  static const List<String> _wiperPositionOrder = <String>[
    'driver',
    'passenger',
    'rear',
  ];

  /// Preferred ordering of common automotive maintenance part categories.
  static const List<String> _preferredCategoryOrder = <String>[
    'oil_filter',
    'air_filter',
    'cabin_filter',
    'wiper',
    'battery',
    'fuel_filter',
  ];

  /// Normalized 17-character VIN for this result.
  final String vin;

  /// Core decoded vehicle attributes.
  final VehicleInfo vehicle;

  /// Optional secondary vehicle record used for parts cross-referencing.
  final MatchedPartsVehicle? matchedPartsVehicle;

  /// Recommended parts grouped by raw category key.
  final Map<String, List<VehiclePart>> partsByCategory;

  /// Recommended motor oil options and sump capacities.
  final List<OilSpec> oilSpecs;

  /// Recommended fluid and maintenance service entries.
  final List<VehicleServiceItem> services;

  /// Product Finder catalog match metadata entries.
  final List<VfMatch> vfMatches;

  /// Returns part category keys sorted with common maintenance items first.
  List<String> get orderedPartCategories {
    final keys = partsByCategory.keys.toList();
    keys.sort((a, b) {
      final indexA = _preferredCategoryOrder.indexOf(a);
      final indexB = _preferredCategoryOrder.indexOf(b);
      if (indexA != -1 && indexB != -1) {
        return indexA.compareTo(indexB);
      }
      if (indexA != -1) {
        return -1;
      }
      if (indexB != -1) {
        return 1;
      }
      return a.compareTo(b);
    });
    return List<String>.unmodifiable(keys);
  }

  /// Filter category keys present in [partsByCategory] in shop-priority order.
  List<String> get orderedFilterCategories {
    return List<String>.unmodifiable(
      filterCategoryOrder.where(
        (key) => (partsByCategory[key]?.isNotEmpty ?? false),
      ),
    );
  }

  /// All wiper blade parts returned for this vehicle.
  List<VehiclePart> get wiperParts =>
      partsByCategory['wiper'] ?? const <VehiclePart>[];

  /// Groups [wiperParts] by position (`driver`, `passenger`, `rear`, others).
  Map<String, List<VehiclePart>> get wipersByPosition {
    final grouped = <String, List<VehiclePart>>{};
    for (final part in wiperParts) {
      final key = part.position.trim().toLowerCase().isEmpty
          ? 'other'
          : part.position.trim().toLowerCase();
      grouped.putIfAbsent(key, () => <VehiclePart>[]).add(part);
    }
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        final indexA = _wiperPositionOrder.indexOf(a);
        final indexB = _wiperPositionOrder.indexOf(b);
        if (indexA != -1 && indexB != -1) {
          return indexA.compareTo(indexB);
        }
        if (indexA != -1) {
          return -1;
        }
        if (indexB != -1) {
          return 1;
        }
        return a.compareTo(b);
      });
    return <String, List<VehiclePart>>{
      for (final key in sortedKeys)
        key: List<VehiclePart>.unmodifiable(grouped[key]!),
    };
  }

  /// Remaining part category keys excluding filters and wipers (e.g. battery).
  List<String> get otherPartCategories {
    return List<String>.unmodifiable(
      orderedPartCategories.where(
        (key) => !filterCategoryOrder.contains(key) && key != 'wiper',
      ),
    );
  }

  /// Groups [services] by their service heading while preserving API order.
  Map<String, List<VehicleServiceItem>> get servicesByName {
    final grouped = <String, List<VehicleServiceItem>>{};
    for (final item in services) {
      final heading = item.service.isEmpty ? 'Other Service' : item.service;
      grouped.putIfAbsent(heading, () => <VehicleServiceItem>[]).add(item);
    }
    return grouped.map(
      (key, value) =>
          MapEntry(key, List<VehicleServiceItem>.unmodifiable(value)),
    );
  }

  /// Ordered unique oil viscosities recommended across [oilSpecs] and [vfMatches].
  List<String> get oilViscosities {
    final seen = <String>{};
    final result = <String>[];
    for (final spec in oilSpecs) {
      if (spec.viscosity.isNotEmpty && seen.add(spec.viscosity)) {
        result.add(spec.viscosity);
      }
    }
    for (final match in vfMatches) {
      if (match.grade.isNotEmpty && seen.add(match.grade)) {
        result.add(match.grade);
      }
    }
    return List<String>.unmodifiable(result);
  }

  /// Ordered unique oil capacities recommended across [oilSpecs] and [vfMatches].
  List<String> get oilCapacities {
    final seen = <String>{};
    final result = <String>[];
    for (final spec in oilSpecs) {
      final formatted = spec.formattedCapacity;
      if (formatted != null && seen.add(formatted)) {
        result.add(formatted);
      }
    }
    for (final match in vfMatches) {
      if (match.capacityQt != null) {
        final formatted = JsonParsers.formatQuarts(match.capacityQt!);
        if (seen.add(formatted)) {
          result.add(formatted);
        }
      }
    }
    return List<String>.unmodifiable(result);
  }

  /// Ordered unique oil formulation labels from [oilSpecs].
  List<String> get oilTypeLabels {
    final seen = <String>{};
    final result = <String>[];
    for (final spec in oilSpecs) {
      final label = spec.oilTypeLabel;
      if (label.isNotEmpty && seen.add(label)) {
        result.add(label);
      }
    }
    return List<String>.unmodifiable(result);
  }

  /// Distinct non-empty catalog source labels across parts, oil, and services.
  List<String> get uniqueSources {
    final seen = <String>{};
    final sources = <String>[];
    for (final parts in partsByCategory.values) {
      for (final part in parts) {
        if (part.source.isNotEmpty && seen.add(part.source)) {
          sources.add(part.source);
        }
      }
    }
    for (final spec in oilSpecs) {
      if (spec.source.isNotEmpty && seen.add(spec.source)) {
        sources.add(spec.source);
      }
    }
    for (final item in services) {
      if (item.source.isNotEmpty && seen.add(item.source)) {
        sources.add(item.source);
      }
    }
    return List<String>.unmodifiable(sources);
  }

  /// Primary recommended oil viscosity grade, if available.
  String? get primaryOilViscosity =>
      oilViscosities.isEmpty ? null : oilViscosities.first;

  /// Primary formatted engine oil capacity in quarts, if available.
  String? get primaryOilCapacityLabel =>
      oilCapacities.isEmpty ? null : oilCapacities.first;

  /// Formats a concise plain-text shop summary suitable for clipboard export.
  String toPlainTextSummary() {
    final buffer = StringBuffer()
      ..writeln(vehicle.displayTitle)
      ..writeln(
        vehicle.engine.isNotEmpty ? 'Engine: ${vehicle.engine}' : 'Engine: N/A',
      )
      ..writeln('VIN: $vin');

    if (oilViscosities.isNotEmpty || oilCapacities.isNotEmpty) {
      final oilParts = <String>[
        if (oilViscosities.isNotEmpty) oilViscosities.join(' / '),
        if (oilCapacities.isNotEmpty) oilCapacities.join(' / '),
        if (oilTypeLabels.isNotEmpty) oilTypeLabels.join(', '),
      ];
      buffer.writeln('Oil: ${oilParts.join(' • ')}');
    }

    if (orderedFilterCategories.isNotEmpty) {
      buffer.writeln('\nFilters:');
      for (final category in orderedFilterCategories) {
        final label = VehiclePart.labelForCategory(category);
        final parts = partsByCategory[category]!
            .map((part) {
              final tier = part.brandTierLabel;
              return tier.isNotEmpty
                  ? '${part.partNumber} ($tier)'
                  : part.partNumber;
            })
            .where((token) => token.isNotEmpty)
            .join(', ');
        buffer.writeln('  $label: $parts');
      }
    }

    if (wipersByPosition.isNotEmpty) {
      buffer.writeln('\nWipers:');
      for (final entry in wipersByPosition.entries) {
        final posLabel = JsonParsers.titleCaseIdentifier(entry.key);
        final first = entry.value.first;
        final size = first.wiperLengthLabel;
        final parts = entry.value
            .map((part) {
              final tier = part.brandTierLabel;
              return tier.isNotEmpty
                  ? '${part.partNumber} ($tier)'
                  : part.partNumber;
            })
            .join(', ');
        final connector = first.armConnectorLabel;
        final details = <String>[
          ?size,
          parts,
          if (connector != null) 'Connector: $connector',
        ];
        buffer.writeln('  $posLabel: ${details.join(' • ')}');
      }
    }

    for (final category in otherPartCategories) {
      final label = VehiclePart.labelForCategory(category);
      buffer.writeln('\n$label:');
      for (final part in partsByCategory[category]!) {
        buffer.writeln(
          '  ${part.partNumber}${part.detail.isNotEmpty ? ' — ${part.detail}' : ''}',
        );
      }
    }

    if (servicesByName.isNotEmpty) {
      buffer.writeln('\nFluids & Services:');
      for (final entry in servicesByName.entries) {
        final items = entry.value
            .map((item) => item.cleanNotes.isNotEmpty ? item.cleanNotes : item.origin)
            .join(' | ');
        buffer.writeln('  ${entry.key}: $items');
      }
    }

    return buffer.toString().trim();
  }
}
