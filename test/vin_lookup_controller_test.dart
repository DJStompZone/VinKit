import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinkit_app/models/vehicle_info.dart';
import 'package:vinkit_app/models/vin_lookup_exception.dart';
import 'package:vinkit_app/models/vin_lookup_result.dart';
import 'package:vinkit_app/models/vin_lookup_state.dart';
import 'package:vinkit_app/services/vin_lookup_controller.dart';
import 'package:vinkit_app/services/vin_lookup_service.dart';

class _StubVinService implements VinLookupService {
  _StubVinService(this.handler);

  final Future<VinLookupResult> Function(String vin) handler;
  int calls = 0;

  @override
  Future<VinLookupResult> lookupVin(String vin) {
    calls++;
    return handler(vin);
  }

  @override
  void dispose() {}
}

VinLookupResult _sampleResult(String vin) {
  return VinLookupResult(
    vin: vin,
    vehicle: const VehicleInfo(
      id: 31821,
      year: 2022,
      make: 'Ford',
      model: 'Explorer',
      trim: 'ST',
      engine: '3.0L V6 GTDI',
    ),
    partsByCategory: const {},
    oilSpecs: const [],
    services: const [],
    vfMatches: const [],
  );
}

/// Unit tests for [VinLookupController].
void main() {
  group('VinLookupController', () {
    test('transitions from idle to loading to success', () async {
      final completer = Completer<VinLookupResult>();
      final service = _StubVinService((_) => completer.future);
      final controller = VinLookupController(service: service);

      expect(controller.state, isA<VinLookupIdle>());

      final future = controller.lookupVin('1FM5K8GCXNGA77516');
      expect(controller.state, isA<VinLookupLoading>());

      completer.complete(_sampleResult('1FM5K8GCXNGA77516'));
      await future;

      expect(controller.state, isA<VinLookupSuccess>());
      final success = controller.state as VinLookupSuccess;
      expect(success.result.vehicle.displayTitle, '2022 Ford Explorer ST');
      controller.dispose();
    });

    test('fails client-side without invoking service on invalid VIN', () async {
      final service = _StubVinService((vin) async => _sampleResult(vin));
      final controller = VinLookupController(service: service);

      await controller.lookupVin('SHORTVIN');

      expect(service.calls, 0);
      expect(controller.state, isA<VinLookupFailure>());
      final failure = controller.state as VinLookupFailure;
      expect(failure.error.kind, VinLookupErrorKind.invalidVin);
      controller.dispose();
    });

    test('retry re-runs last VIN lookup after transient failure', () async {
      var attempt = 0;
      final service = _StubVinService((vin) async {
        attempt++;
        if (attempt == 1) {
          throw const VinLookupException(
            kind: VinLookupErrorKind.network,
            message: 'Offline',
          );
        }
        return _sampleResult(vin);
      });
      final controller = VinLookupController(service: service);

      await controller.lookupVin('1FM5K8GCXNGA77516');
      expect(controller.state, isA<VinLookupFailure>());

      await controller.retry();
      expect(controller.state, isA<VinLookupSuccess>());
      expect(service.calls, 2);
      controller.dispose();
    });

    test('reset discards in-flight request completions', () async {
      final completer = Completer<VinLookupResult>();
      final service = _StubVinService((_) => completer.future);
      final controller = VinLookupController(service: service);

      final future = controller.lookupVin('1FM5K8GCXNGA77516');
      expect(controller.state, isA<VinLookupLoading>());

      controller.reset();
      expect(controller.state, isA<VinLookupIdle>());

      completer.complete(_sampleResult('1FM5K8GCXNGA77516'));
      await future;

      expect(controller.state, isA<VinLookupIdle>());
      controller.dispose();
    });
  });
}
