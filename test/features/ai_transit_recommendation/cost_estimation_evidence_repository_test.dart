import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_price_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'official request selects level Peninsular diesel by reference date',
    () async {
      late Uri requested;
      final source = DataGovMyFuelPriceDataSource(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            '[{"series_type":"level","date":"2024-06-10","diesel":3.35}]',
            200,
          );
        }),
      );

      final records = await source.fetchFuelPrices(DateTime(2024, 6, 12));

      expect(requested.toString(), startsWith(dataGovMyFuelPriceEndpoint));
      expect(requested.queryParameters['id'], 'fuelprice');
      expect(requested.queryParameters['filter'], 'level@series_type');
      expect(requested.queryParameters['include'], 'series_type,date,diesel');
      expect(requested.queryParameters['sort'], '-date');
      expect(requested.queryParameters['limit'], '1');
      expect(requested.queryParameters['date_end'], '2024-06-12@date');
      expect(records.single.seriesType, 'level');
      expect(records.single.dieselRmPerLitre, 3.35);
    },
  );

  test(
    'selects latest applicable level record and excludes future records',
    () async {
      final result = await DefaultFuelPriceRepository(
        dataSource: FakeFuelPriceDataSource([
          record('2024-06-13', 3.35),
          record('2024-06-06', 2.15),
          record('2024-05-30', 2.10),
          record('2024-06-12', -0.05, seriesType: 'change_weekly'),
        ]),
      ).loadDieselPrice(DateTime(2024, 6, 12));

      expect(result.status, DieselPriceEvidenceStatus.available);
      expect(result.effectiveDate, DateTime(2024, 6, 6));
      expect(result.rmPerLitre, 2.15);
    },
  );

  test('preserves official fuel-price provenance', () async {
    final result = await DefaultFuelPriceRepository(
      dataSource: FakeFuelPriceDataSource([record('2026-08-20', 2.95)]),
    ).loadDieselPrice(DateTime(2026, 8, 27));

    expect(result.source.platform, 'data.gov.my');
    expect(result.source.publisher, 'Ministry of Finance Malaysia');
    expect(result.source.datasetId, 'fuelprice');
    expect(result.source.datasetName, 'Petrol & Diesel Prices');
  });

  test('API failure leaves diesel price unavailable', () async {
    final result = await DefaultFuelPriceRepository(
      dataSource: FailingFuelPriceDataSource(),
    ).loadDieselPrice(DateTime(2026, 8, 27));

    expect(result.status, DieselPriceEvidenceStatus.unavailable);
    expect(result.effectiveDate, isNull);
    expect(result.rmPerLitre, isNull);
  });

  test('no applicable record does not fabricate a diesel price', () async {
    final result = await DefaultFuelPriceRepository(
      dataSource: FakeFuelPriceDataSource([record('2026-08-28', 3.0)]),
    ).loadDieselPrice(DateTime(2026, 8, 27));

    expect(result.status, DieselPriceEvidenceStatus.noApplicableRecord);
    expect(result.rmPerLitre, isNull);
  });

  test(
    'retains route variants and scheduled evidence while inputs stay missing',
    () async {
      final network = AiRouteNetworkEvidence(
        route: route,
        trips: [trip('trip-a', 12000), trip('trip-b', 15000)],
      );
      final scheduled = scheduledEvidence();
      final result =
          await DefaultCostEstimationEvidenceRepository(
            routeNetworkRepository: FakeRouteNetworkRepository(network),
            scheduledServiceRepository: FakeScheduledRepository(scheduled),
            fuelPriceRepository: FakeFuelPriceRepository(
              const DieselPriceEvidence(
                status: DieselPriceEvidenceStatus.available,
                source: fuelPriceSource,
                effectiveDate: null,
                rmPerLitre: 2.95,
              ),
            ),
          ).loadEvidence(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
            referenceDate: DateTime(2026, 8, 27, 18),
          );

      expect(result.network, same(network));
      expect(result.scheduledService, same(scheduled));
      expect(result.network.trips.map((item) => item.routeDistanceMeters), [
        12000,
        15000,
      ]);
      expect(
        result.unavailableInputs,
        contains(UnavailableCostInput.busFuelConsumption),
      );
      expect(
        result.unavailableInputs,
        containsAll(UnavailableCostInput.values),
      );
      expect(result.referenceDate, DateTime(2026, 8, 27));
    },
  );

  test('forwards route period and reference date unchanged', () async {
    final networkRepository = FakeRouteNetworkRepository(
      AiRouteNetworkEvidence(route: route, trips: const []),
    );
    final scheduledRepository = FakeScheduledRepository(scheduledEvidence());
    final fuelRepository = FakeFuelPriceRepository(
      const DieselPriceEvidence(
        status: DieselPriceEvidenceStatus.unavailable,
        source: fuelPriceSource,
        effectiveDate: null,
        rmPerLitre: null,
      ),
    );
    await DefaultCostEstimationEvidenceRepository(
      routeNetworkRepository: networkRepository,
      scheduledServiceRepository: scheduledRepository,
      fuelPriceRepository: fuelRepository,
    ).loadEvidence(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
      referenceDate: referenceDate,
    );

    expect(networkRepository.routeId, 'J15');
    expect(scheduledRepository.routeId, 'J15');
    expect(scheduledRepository.startUtc, periodStart);
    expect(scheduledRepository.endExclusiveUtc, periodEnd);
    expect(fuelRepository.referenceDate, referenceDate);
  });
}

final periodStart = DateTime.utc(2026, 8, 20);
final periodEnd = DateTime.utc(2026, 8, 27);
final referenceDate = DateTime(2026, 8, 27);

const route = RoutePerformanceRoute(
  routeId: 'J15',
  shortName: 'J15',
  longName: 'Johor Bahru route',
);

FuelPriceRecord record(
  String date,
  double price, {
  String seriesType = 'level',
}) {
  return FuelPriceRecord(
    seriesType: seriesType,
    effectiveDate: DateTime.parse(date),
    dieselRmPerLitre: price,
  );
}

AiRouteTripEvidence trip(String tripId, double distance) {
  return AiRouteTripEvidence(
    tripId: tripId,
    shapeId: '$tripId-shape',
    stops: const [],
    shapePoints: const [],
    routeDistanceMeters: distance,
  );
}

ScheduledServiceEvidence scheduledEvidence() {
  return ScheduledServiceEvidence(
    route: route,
    periodStart: periodStart,
    periodEnd: periodEnd,
    directionGroups: const [],
    incompleteTripIds: const [],
    status: ScheduledServiceEvidenceStatus.noDepartures,
    hasCompleteDirectionData: true,
  );
}

class FakeFuelPriceDataSource implements FuelPriceDataSource {
  FakeFuelPriceDataSource(this.records);

  final List<FuelPriceRecord> records;

  @override
  Future<List<FuelPriceRecord>> fetchFuelPrices(DateTime referenceDate) async =>
      records;
}

class FailingFuelPriceDataSource implements FuelPriceDataSource {
  @override
  Future<List<FuelPriceRecord>> fetchFuelPrices(DateTime referenceDate) {
    throw const FuelPriceReadException('unavailable');
  }
}

class FakeRouteNetworkRepository implements RouteNetworkEvidenceRepository {
  FakeRouteNetworkRepository(this.result);

  final AiRouteNetworkEvidence result;
  String? routeId;

  @override
  Future<AiRouteNetworkEvidence> loadRoute(String routeId) async {
    this.routeId = routeId;
    return result;
  }
}

class FakeScheduledRepository implements ScheduledServiceEvidenceRepository {
  FakeScheduledRepository(this.result);

  final ScheduledServiceEvidence result;
  String? routeId;
  DateTime? startUtc;
  DateTime? endExclusiveUtc;

  @override
  Future<ScheduledServiceEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    this.routeId = routeId;
    this.startUtc = startUtc;
    this.endExclusiveUtc = endExclusiveUtc;
    return result;
  }
}

class FakeFuelPriceRepository implements FuelPriceRepository {
  FakeFuelPriceRepository(this.result);

  final DieselPriceEvidence result;
  DateTime? referenceDate;

  @override
  Future<DieselPriceEvidence> loadDieselPrice(DateTime referenceDate) async {
    this.referenceDate = referenceDate;
    return result;
  }
}
