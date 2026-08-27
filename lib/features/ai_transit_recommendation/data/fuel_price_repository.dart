import 'dart:async';
import 'dart:convert';

import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_models.dart';
import 'package:http/http.dart' as http;

const dataGovMyFuelPriceEndpoint = 'https://api.data.gov.my/data-catalogue/';

class FuelPriceRecord {
  const FuelPriceRecord({
    required this.seriesType,
    required this.effectiveDate,
    required this.dieselRmPerLitre,
  });

  final String seriesType;
  final DateTime effectiveDate;
  final double dieselRmPerLitre;
}

abstract interface class FuelPriceDataSource {
  Future<List<FuelPriceRecord>> fetchFuelPrices(DateTime referenceDate);
}

abstract interface class FuelPriceRepository {
  Future<DieselPriceEvidence> loadDieselPrice(DateTime referenceDate);
}

class DefaultFuelPriceRepository implements FuelPriceRepository {
  DefaultFuelPriceRepository({FuelPriceDataSource? dataSource})
    : _dataSource = dataSource ?? DataGovMyFuelPriceDataSource();

  final FuelPriceDataSource _dataSource;

  @override
  Future<DieselPriceEvidence> loadDieselPrice(DateTime referenceDate) async {
    final requestedDate = _dateOnly(referenceDate);
    try {
      final records = await _dataSource.fetchFuelPrices(requestedDate);
      final applicable =
          records
              .where(
                (record) =>
                    record.seriesType == 'level' &&
                    !record.effectiveDate.isAfter(requestedDate),
              )
              .toList()
            ..sort(
              (left, right) =>
                  right.effectiveDate.compareTo(left.effectiveDate),
            );
      if (applicable.isEmpty) {
        return const DieselPriceEvidence(
          status: DieselPriceEvidenceStatus.noApplicableRecord,
          source: fuelPriceSource,
          effectiveDate: null,
          rmPerLitre: null,
        );
      }
      final record = applicable.first;
      return DieselPriceEvidence(
        status: DieselPriceEvidenceStatus.available,
        source: fuelPriceSource,
        effectiveDate: record.effectiveDate,
        rmPerLitre: record.dieselRmPerLitre,
      );
    } on FuelPriceFormatException {
      return const DieselPriceEvidence(
        status: DieselPriceEvidenceStatus.unusable,
        source: fuelPriceSource,
        effectiveDate: null,
        rmPerLitre: null,
      );
    } on Object {
      return const DieselPriceEvidence(
        status: DieselPriceEvidenceStatus.unavailable,
        source: fuelPriceSource,
        effectiveDate: null,
        rmPerLitre: null,
      );
    }
  }
}

class DataGovMyFuelPriceDataSource implements FuelPriceDataSource {
  DataGovMyFuelPriceDataSource({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration requestTimeout;

  @override
  Future<List<FuelPriceRecord>> fetchFuelPrices(DateTime referenceDate) async {
    try {
      final uri = Uri.parse(dataGovMyFuelPriceEndpoint).replace(
        queryParameters: {
          'id': 'fuelprice',
          'filter': 'level@series_type',
          'include': 'series_type,date,diesel',
          'sort': '-date',
          'limit': '1',
          'date_end': '${_formatDate(referenceDate)}@date',
        },
      );
      final response = await _client.get(uri).timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FuelPriceReadException(
          'Fuel-price service returned HTTP ${response.statusCode}.',
        );
      }
      return parseFuelPriceResponse(response.body);
    } on FuelPriceFormatException {
      rethrow;
    } on FuelPriceReadException {
      rethrow;
    } on TimeoutException {
      throw const FuelPriceReadException('The fuel-price request timed out.');
    } on Object {
      throw const FuelPriceReadException(
        'Unable to retrieve official fuel-price data.',
      );
    }
  }
}

List<FuelPriceRecord> parseFuelPriceResponse(String body) {
  try {
    final rows = jsonDecode(body) as List<dynamic>;
    return rows
        .map((value) {
          final row = value as Map<String, dynamic>;
          final seriesType = row['series_type'] as String;
          final effectiveDate = DateTime.parse(row['date'] as String);
          final diesel = (row['diesel'] as num).toDouble();
          if (seriesType.isEmpty || !diesel.isFinite || diesel < 0) {
            throw const FormatException();
          }
          return FuelPriceRecord(
            seriesType: seriesType,
            effectiveDate: _dateOnly(effectiveDate),
            dieselRmPerLitre: diesel,
          );
        })
        .toList(growable: false);
  } on FuelPriceFormatException {
    rethrow;
  } on Object {
    throw const FuelPriceFormatException(
      'The fuel-price response is unusable.',
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class FuelPriceReadException implements Exception {
  const FuelPriceReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FuelPriceFormatException implements Exception {
  const FuelPriceFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
