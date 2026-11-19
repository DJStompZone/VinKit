import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinkit_app/models/vin_lookup_exception.dart';
import 'package:vinkit_app/services/stomp_zone_vin_service.dart';

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  RequestOptions? lastOptions;
  int callCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    callCount++;
    lastOptions = options;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Unit tests for [StompZoneVinService].
void main() {
  Dio buildDio(_MockHttpClientAdapter adapter) {
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    return dio;
  }

  group('StompZoneVinService', () {
    test('short-circuits invalid VIN before making HTTP request', () async {
      final adapter = _MockHttpClientAdapter(
        (_) async => ResponseBody.fromString('{}', 200),
      );
      final service = StompZoneVinService(dio: buildDio(adapter));

      await expectLater(
        () => service.lookupVin('INVALID'),
        throwsA(
          isA<VinLookupException>()
              .having((e) => e.kind, 'kind', VinLookupErrorKind.invalidVin)
              .having((e) => e.isRetryable, 'isRetryable', isFalse),
        ),
      );
      expect(adapter.callCount, 0);
    });

    test('decodes valid JSON response and normalizes requested URL', () async {
      final payload = jsonEncode(<String, dynamic>{
        'vehicle': <String, dynamic>{
          'id': 31821,
          'year': 2022,
          'make': 'Ford',
          'model': 'Explorer',
          'trim': 'ST',
          'engine': '3.0L V6 GTDI',
        },
        'parts_by_category': <String, dynamic>{},
        'oil_specs': <dynamic>[],
        'services': <dynamic>[],
        'vf_matches': <dynamic>[],
        'vin': '1FM5K8GCXNGA77516',
      });

      final adapter = _MockHttpClientAdapter(
        (_) async => ResponseBody.fromString(
          payload,
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        ),
      );
      final service = StompZoneVinService(
        baseUrl: 'https://vin.stomp.zone/api/v1/vin/',
        dio: buildDio(adapter),
      );

      final result = await service.lookupVin('1fm5k8gcxnga77516');

      expect(
        adapter.lastOptions?.uri.toString(),
        'https://vin.stomp.zone/api/v1/vin/1FM5K8GCXNGA77516',
      );
      expect(result.vehicle.displayTitle, '2022 Ford Explorer ST');
      expect(result.vin, '1FM5K8GCXNGA77516');
    });

    test('maps HTTP 400 JSON error payload to non-retryable notFound', () async {
      final adapter = _MockHttpClientAdapter(
        (_) async => ResponseBody.fromString(
          jsonEncode(<String, dynamic>{
            'error': 'Could not decode VIN: 1 - Check Digit does not calculate properly',
            'vin': '11111111111111111',
          }),
          400,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        ),
      );
      final service = StompZoneVinService(dio: buildDio(adapter));

      await expectLater(
        () => service.lookupVin('11111111111111111'),
        throwsA(
          isA<VinLookupException>()
              .having((e) => e.kind, 'kind', VinLookupErrorKind.notFound)
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.isRetryable, 'isRetryable', isFalse)
              .having((e) => e.message, 'message', contains('Check Digit')),
        ),
      );
    });

    test('maps HTTP 503 response to retryable serverError', () async {
      final adapter = _MockHttpClientAdapter(
        (_) async => ResponseBody.fromString('Service Unavailable', 503),
      );
      final service = StompZoneVinService(dio: buildDio(adapter));

      await expectLater(
        () => service.lookupVin('1FM5K8GCXNGA77516'),
        throwsA(
          isA<VinLookupException>()
              .having((e) => e.kind, 'kind', VinLookupErrorKind.serverError)
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });

    test('maps Dio receive timeout to retryable timeout', () async {
      final adapter = _MockHttpClientAdapter(
        (options) => Future<ResponseBody>.error(
          DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
          ),
        ),
      );
      final service = StompZoneVinService(dio: buildDio(adapter));

      await expectLater(
        () => service.lookupVin('1FM5K8GCXNGA77516'),
        throwsA(
          isA<VinLookupException>()
              .having((e) => e.kind, 'kind', VinLookupErrorKind.timeout)
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });

    test('maps Dio connection error to retryable network error', () async {
      final adapter = _MockHttpClientAdapter(
        (options) => Future<ResponseBody>.error(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        ),
      );
      final service = StompZoneVinService(dio: buildDio(adapter));

      await expectLater(
        () => service.lookupVin('1FM5K8GCXNGA77516'),
        throwsA(
          isA<VinLookupException>()
              .having((e) => e.kind, 'kind', VinLookupErrorKind.network)
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });
  });
}
