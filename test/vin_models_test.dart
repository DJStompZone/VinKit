import 'package:flutter_test/flutter_test.dart';
import 'package:vinkit_app/models/vin_lookup_result.dart';

/// Unit tests for domain JSON parsing and presentation helpers.
void main() {
  group('VinLookupResult.fromJson', () {
    test('parses 2022 Ford Explorer ST payload with parts, oil specs, and services', () {
      final json = <String, dynamic>{
        'vehicle': <String, dynamic>{
          'id': 31821,
          'year': 2022,
          'make': 'Ford',
          'model': 'Explorer',
          'trim': 'ST',
          'engine': '3.0L V6 GTDI',
        },
        'matched_parts_vehicle': null,
        'parts_by_category': <String, dynamic>{
          'wiper': <Map<String, dynamic>>[
            <String, dynamic>{
              'category': 'wiper',
              'position': 'driver',
              'brand': 'Valvoline (BEAM BLADE)',
              'part_number': '836539',
              'detail': 'FRONT LEFT | 26 in.; Arm Connector: PT 15; Original (OEM): Beam',
              'source': 'Valvoline Catalog',
              'verified': true,
            },
          ],
          'oil_filter': <Map<String, dynamic>>[
            <String, dynamic>{
              'category': 'oil_filter',
              'position': '',
              'brand': 'Valvoline (STANDARD)',
              'part_number': 'VO-115',
              'detail': 'Engine Oil Filter',
              'source': 'Valvoline Catalog',
              'verified': true,
            },
          ],
          'air_filter': <Map<String, dynamic>>[
            <String, dynamic>{
              'category': 'air_filter',
              'position': '',
              'brand': 'Valvoline',
              'part_number': 'VA-224',
              'detail': 'Engine Air Filter',
              'source': 'Valvoline Catalog',
              'verified': true,
            },
          ],
        },
        'oil_specs': <Map<String, dynamic>>[
          <String, dynamic>{
            'origin': 'Valvoline',
            'viscosity': '5W-30',
            'oil_type': 'synthetic',
            'capacity_qt': 6,
            'spec_notes': 'Restore & Protect Full Synthetic SAE 5W-30 Motor Oil | Capacity 6 US quarts',
            'source': 'Valvoline Product Finder',
            'verified': true,
          },
          <String, dynamic>{
            'origin': 'Valvoline',
            'viscosity': '5W-30',
            'oil_type': 'synthetic_blend',
            'capacity_qt': 5.5,
            'spec_notes': 'Synthetic Blend',
            'source': 'Valvoline Product Finder',
            'verified': true,
          },
        ],
        'services': <Map<String, dynamic>>[
          <String, dynamic>{
            'service': 'Transferbox',
            'interval_mi': null,
            'interval_mo': null,
            'origin': 'Valvoline',
            'notes': 'DEXRON VI/MERCON LV (ATF)',
            'source': 'Valvoline Product Finder',
            'verified': true,
          },
          <String, dynamic>{
            'service': 'Transferbox',
            'interval_mi': 60000,
            'interval_mo': 48,
            'origin': 'Valvoline',
            'notes': 'Extended Protection ATF',
            'source': 'Valvoline Product Finder',
            'verified': true,
          },
        ],
        'vf_matches': <Map<String, dynamic>>[
          <String, dynamic>{
            'engine_id': '5e755200bc0042b0',
            'match_score': 144,
            'match_type': 'exact_displacement',
            'make': 'Ford',
            'model_raw': 'Explorer, U625 (2019- )',
            'engine_raw': 'Explorer 3.0 EcoBoost AWD (298 KW) (2020 - )',
            'region': '',
            'year_from': 2020,
            'year_to': 2027,
            'displacement_l': 3,
            'grade': '5W-30',
            'capacity_qt': 6,
          },
        ],
        'vin': '1FM5K8GCXNGA77516',
      };

      final result = VinLookupResult.fromJson(
        json,
        fallbackVin: '1FM5K8GCXNGA77516',
      );

      expect(result.vin, '1FM5K8GCXNGA77516');
      expect(result.vehicle.displayTitle, '2022 Ford Explorer ST');
      expect(result.vehicle.engine, '3.0L V6 GTDI');
      expect(result.matchedPartsVehicle, isNull);
      expect(
        result.orderedPartCategories,
        <String>['oil_filter', 'air_filter', 'wiper'],
      );
      expect(
        result.partsByCategory['wiper']!.single.detailSegments,
        <String>[
          'FRONT LEFT | 26 in.',
          'Arm Connector: PT 15',
          'Original (OEM): Beam',
        ],
      );
      expect(result.partsByCategory['wiper']!.single.positionLabel, 'Driver');
      expect(result.primaryOilViscosity, '5W-30');
      expect(result.primaryOilCapacityLabel, '6 qt');
      expect(result.oilSpecs[1].formattedCapacity, '5.5 qt');
      expect(result.oilSpecs[1].oilTypeLabel, 'Synthetic Blend');
      expect(result.servicesByName['Transferbox'], hasLength(2));
      expect(result.servicesByName['Transferbox']!.first.formattedInterval, isNull);
      expect(
        result.servicesByName['Transferbox']![1].formattedInterval,
        '60000 mi / 48 mo',
      );
      expect(result.vfMatches.single.displacementL, 3.0);
    });

    test('parses matched_parts_vehicle and uses fallbackVin when omitted', () {
      final json = <String, dynamic>{
        'vehicle': <String, dynamic>{
          'id': 0,
          'year': 2003,
          'make': 'Honda',
          'model': 'Accord',
          'trim': 'EX-V6',
          'engine': '3.0L V6 J30A4',
        },
        'matched_parts_vehicle': <String, dynamic>{
          'id': 18814,
          'year': 2003,
          'make': 'Honda',
          'model': 'ACCORD',
          'trim': '',
          'engine': 'V6 3.0L 2997cc',
          'match_score': 132,
          'match_type': 'canonical_exact_disp',
        },
        'parts_by_category': <String, dynamic>{},
        'oil_specs': <dynamic>[],
        'services': <dynamic>[],
        'vf_matches': <dynamic>[],
      };

      final result = VinLookupResult.fromJson(
        json,
        fallbackVin: '1HGCM82633A004352',
      );

      expect(result.vin, '1HGCM82633A004352');
      expect(result.vehicle.displayTitle, '2003 Honda Accord EX-V6');
      expect(result.matchedPartsVehicle, isNotNull);
      expect(result.matchedPartsVehicle!.matchType, 'canonical_exact_disp');
      expect(result.matchedPartsVehicle!.matchScore, 132);
    });
  });
}
