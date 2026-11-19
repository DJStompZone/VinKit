import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:vinkit_app/models/json_parsers.dart';
import 'package:vinkit_app/models/vin_lookup_exception.dart';
import 'package:vinkit_app/models/vin_lookup_result.dart';
import 'package:vinkit_app/services/vin_lookup_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';

/// [VinLookupService] implementation backed by the custom `vin.stomp.zone` API.
class StompZoneVinService implements VinLookupService {
  /// Creates a [StompZoneVinService] targeting [baseUrl].
  ///
  /// An optional [dio] instance may be injected for testing or custom
  /// interceptors; externally provided clients are not closed by [dispose].
  StompZoneVinService({
    String baseUrl = defaultBaseUrl,
    Dio? dio,
    this.validator = const VinValidator(),
  })  : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                sendTimeout: kIsWeb ? null : const Duration(seconds: 10),
                headers: const <String, String>{
                  'Accept': 'application/json',
                },
              ),
            ),
        _ownsDio = dio == null;

  /// Default base endpoint URL for VIN lookups (`GET {defaultBaseUrl}/{VIN}`).
  static const String defaultBaseUrl = 'https://vin.stomp.zone/api/v1/vin';

  final String _baseUrl;
  final Dio _dio;
  final bool _ownsDio;

  /// Validator used to normalize and validate VINs before sending requests.
  final VinValidator validator;

  @override
  Future<VinLookupResult> lookupVin(String vin) async {
    final validation = validator.validate(vin);
    if (!validation.isValid) {
      throw VinLookupException(
        kind: VinLookupErrorKind.invalidVin,
        message: validation.errorMessage ?? 'Invalid VIN.',
      );
    }

    final normalizedVin = validation.normalizedVin;
    final endpoint = '$_baseUrl/$normalizedVin';

    try {
      final response = await _dio.get<Object?>(endpoint);
      final statusCode = response.statusCode ?? 200;
      final payload = _decodeJsonMap(response.data);

      if (statusCode >= 400) {
        throw _exceptionFromErrorPayload(
          statusCode: statusCode,
          payload: payload,
        );
      }

      if (payload == null) {
        throw const VinLookupException(
          kind: VinLookupErrorKind.parseError,
          message: 'Unexpected empty or non-JSON response from VIN service.',
        );
      }

      final errorText = JsonParsers.readString(payload, 'error');
      final result = VinLookupResult.fromJson(
        payload,
        fallbackVin: normalizedVin,
      );

      if (errorText.isNotEmpty && !result.vehicle.hasDetails) {
        throw VinLookupException(
          kind: VinLookupErrorKind.notFound,
          message: errorText,
          statusCode: statusCode,
        );
      }

      return result;
    } on VinLookupException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error);
    } on FormatException catch (error) {
      throw VinLookupException(
        kind: VinLookupErrorKind.parseError,
        message: 'Received malformed JSON while decoding vehicle details.',
        cause: error,
      );
    } catch (error) {
      throw VinLookupException(
        kind: VinLookupErrorKind.unknown,
        message: 'Failed to decode VIN. Please try again.',
        cause: error,
      );
    }
  }

  @override
  void dispose() {
    if (_ownsDio) {
      _dio.close(force: true);
    }
  }

  Map<String, dynamic>? _decodeJsonMap(Object? data) {
    final direct = JsonParsers.readMap(data);
    if (direct != null) {
      return direct;
    }
    if (data is String && data.trim().isNotEmpty) {
      final decoded = jsonDecode(data);
      return JsonParsers.readMap(decoded);
    }
    return null;
  }

  VinLookupException _mapDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return VinLookupException(
          kind: VinLookupErrorKind.timeout,
          message:
              'The request timed out while waiting for the VIN database. Check your connection and retry.',
          cause: error,
        );
      case DioExceptionType.connectionError:
        return VinLookupException(
          kind: VinLookupErrorKind.network,
          message:
              'Unable to reach the VIN server. Check your internet connection and retry.',
          cause: error,
        );
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        Map<String, dynamic>? payload;
        try {
          payload = _decodeJsonMap(error.response?.data);
        } on FormatException {
          payload = null;
        }
        return _exceptionFromErrorPayload(
          statusCode: statusCode,
          payload: payload,
          cause: error,
        );
      case DioExceptionType.badCertificate:
        return VinLookupException(
          kind: VinLookupErrorKind.network,
          message: 'Secure TLS connection to the VIN server failed.',
          cause: error,
        );
      case DioExceptionType.cancel:
        return VinLookupException(
          kind: VinLookupErrorKind.unknown,
          message: 'The VIN lookup request was canceled.',
          cause: error,
        );
      case DioExceptionType.unknown:
        return VinLookupException(
          kind: VinLookupErrorKind.network,
          message:
              'Network error occurred while looking up this VIN. Please try again.',
          cause: error,
        );
    }
  }

  VinLookupException _exceptionFromErrorPayload({
    required int? statusCode,
    required Map<String, dynamic>? payload,
    Object? cause,
  }) {
    final serverMessage = payload == null
        ? ''
        : JsonParsers.readString(payload, 'error').isNotEmpty
            ? JsonParsers.readString(payload, 'error')
            : JsonParsers.readString(payload, 'message');

    if (statusCode != null && statusCode >= 500) {
      return VinLookupException(
        kind: VinLookupErrorKind.serverError,
        statusCode: statusCode,
        message: serverMessage.isNotEmpty
            ? serverMessage
            : 'The VIN server encountered an internal error ($statusCode). Please retry.',
        cause: cause,
      );
    }

    if (statusCode == 400 || statusCode == 404 || statusCode == 422) {
      return VinLookupException(
        kind: VinLookupErrorKind.notFound,
        statusCode: statusCode,
        message: serverMessage.isNotEmpty
            ? serverMessage
            : 'No vehicle match was found for this VIN.',
        cause: cause,
      );
    }

    return VinLookupException(
      kind: VinLookupErrorKind.unknown,
      statusCode: statusCode,
      message: serverMessage.isNotEmpty
          ? serverMessage
          : 'Unexpected response from VIN server (HTTP ${statusCode ?? 'unknown'}).',
      cause: cause,
    );
  }
}
