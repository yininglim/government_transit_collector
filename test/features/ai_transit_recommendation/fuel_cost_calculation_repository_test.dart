import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

void main() {
  test(
    'matches departures to each trip variant without averaging distances',
    () async {
      final result =
          await repository(
            evidence(
              trips: [trip('short', 10000), trip('long', 20000)],
              groups: [
                direction(0, [departure('short')]),
                direction(1, [departure('long')]),
              ],
            ),
          ).calculate(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
            referenceDate: referenceDate,
          );

      expect(result.directionGroups.map((group) => group.directionId), [0, 1]);
      expect(
        result.directionGroups.first.departures.single.vehicleKilometres,
        10,
      );
      expect(
        result.directionGroups.last.departures.single.vehicleKilometres,
        20,
      );
      expect(result.scheduledVehicleKilometres, 30);
      expect(result.totalScheduledDepartureCount, 2);
      expect(result.costableScheduledDepartureCount, 2);
    },
  );

  test(
    'calculates separate low and high litre and expenditure scenarios',
    () async {
      final result =
          await repository(
            evidence(
              trips: [trip('trip-a', 100000)],
              groups: [
                direction(0, [departure('trip-a')]),
              ],
              dieselPrice: availablePrice(2.50),
            ),
          ).calculate(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
            referenceDate: referenceDate,
          );

      expect(result.benchmark.lowLitresPerKilometre, 0.2794);
      expect(result.benchmark.highLitresPerKilometre, 0.3695);
      expect(result.lowEstimatedLitres, closeTo(27.94, 0.0000001));
      expect(result.highEstimatedLitres, closeTo(36.95, 0.0000001));
      expect(result.lowEstimatedFuelCostRm, closeTo(69.85, 0.0000001));
      expect(result.highEstimatedFuelCostRm, closeTo(92.375, 0.0000001));
      expect(result.dieselPrice.rmPerLitre, 2.50);
      expect(result.dieselPrice.source.platform, 'data.gov.my');
      expect(result.dieselPrice.effectiveDate, DateTime(2026, 8, 20));
      expect(result.status, FuelCostCalculationStatus.available);
    },
  );

  test(
    'repeated departures each contribute their actual trip distance',
    () async {
      final result =
          await repository(
            evidence(
              trips: [trip('trip-a', 12000), trip('trip-b', 18000)],
              groups: [
                direction(0, [departure('trip-a'), departure('trip-a')]),
                direction(1, [departure('trip-b')]),
              ],
            ),
          ).calculate(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
            referenceDate: referenceDate,
          );

      expect(result.scheduledVehicleKilometres, 42);
      expect(result.costableScheduledDepartureCount, 3);
    },
  );

  test('unmatched and missing-distance departures remain explicit', () async {
    final result =
        await repository(
          evidence(
            trips: [trip('missing-distance', null), trip('costable', 8000)],
            groups: [
              direction(0, [
                departure('unknown'),
                departure('missing-distance'),
                departure('costable'),
              ]),
            ],
          ),
        ).calculate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
          referenceDate: referenceDate,
        );

    expect(result.totalScheduledDepartureCount, 3);
    expect(result.costableScheduledDepartureCount, 1);
    expect(result.uncostableDepartures, hasLength(2));
    expect(result.uncostableDepartures.map((item) => item.distanceStatus), [
      ScheduledDepartureDistanceStatus.tripNotFound,
      ScheduledDepartureDistanceStatus.distanceUnavailable,
    ]);
    expect(result.scheduledVehicleKilometres, 8);
    expect(result.status, FuelCostCalculationStatus.partial);
  });

  test('ambiguous repeated trip identity is not assigned a distance', () async {
    final result =
        await repository(
          evidence(
            trips: [trip('same', 10000), trip('same', 12000)],
            groups: [
              direction(0, [departure('same')]),
            ],
          ),
        ).calculate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
          referenceDate: referenceDate,
        );

    expect(result.scheduledVehicleKilometres, 0);
    expect(result.lowEstimatedLitres, isNull);
    expect(
      result.uncostableDepartures.single.distanceStatus,
      ScheduledDepartureDistanceStatus.tripVariantAmbiguous,
    );
    expect(result.status, FuelCostCalculationStatus.noCostableDepartures);
  });

  test(
    'unavailable diesel price preserves distance and litre evidence',
    () async {
      final result =
          await repository(
            evidence(
              trips: [trip('trip-a', 10000)],
              groups: [
                direction(null, [departure('trip-a')]),
              ],
              dieselPrice: unavailablePrice,
              scheduledStatus: ScheduledServiceEvidenceStatus.incomplete,
              incompleteTripIds: const ['trip-b'],
              completeDirectionData: false,
            ),
          ).calculate(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
            referenceDate: referenceDate,
          );

      expect(result.scheduledVehicleKilometres, 10);
      expect(result.lowEstimatedLitres, closeTo(2.794, 0.0000001));
      expect(result.highEstimatedLitres, closeTo(3.695, 0.0000001));
      expect(result.lowEstimatedFuelCostRm, isNull);
      expect(result.highEstimatedFuelCostRm, isNull);
      expect(result.status, FuelCostCalculationStatus.fuelPriceUnavailable);
      expect(
        result.scheduledServiceStatus,
        ScheduledServiceEvidenceStatus.incomplete,
      );
      expect(result.incompleteTripIds, ['trip-b']);
      expect(result.hasCompleteDirectionData, isFalse);
      expect(result.directionGroups.single.directionId, isNull);
    },
  );

  test('no scheduled departures remains explicit without estimates', () async {
    final result =
        await repository(
          evidence(trips: [trip('trip-a', 10000)], groups: const []),
        ).calculate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
          referenceDate: referenceDate,
        );

    expect(result.totalScheduledDepartureCount, 0);
    expect(result.scheduledVehicleKilometres, 0);
    expect(result.lowEstimatedLitres, isNull);
    expect(result.highEstimatedFuelCostRm, isNull);
    expect(result.status, FuelCostCalculationStatus.noScheduledDepartures);
  });

  test('reuses Part 5A request arguments and evidence once', () async {
    final source = FakeCostEvidenceRepository(
      evidence(trips: const [], groups: const []),
    );
    await DefaultFuelCostCalculationRepository(
      evidenceRepository: source,
    ).calculate(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
      referenceDate: referenceDate,
    );

    expect(source.callCount, 1);
    expect(source.routeId, 'J15');
    expect(source.startUtc, periodStart);
    expect(source.endExclusiveUtc, periodEnd);
    expect(source.referenceDate, referenceDate);
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

const unavailablePrice = DieselPriceEvidence(
  status: DieselPriceEvidenceStatus.unavailable,
  source: fuelPriceSource,
  effectiveDate: null,
  rmPerLitre: null,
);

DieselPriceEvidence availablePrice(double price) {
  return DieselPriceEvidence(
    status: DieselPriceEvidenceStatus.available,
    source: fuelPriceSource,
    effectiveDate: DateTime(2026, 8, 20),
    rmPerLitre: price,
  );
}

DefaultFuelCostCalculationRepository repository(CostEstimationEvidence source) {
  return DefaultFuelCostCalculationRepository(
    evidenceRepository: FakeCostEvidenceRepository(source),
  );
}

CostEstimationEvidence evidence({
  required List<AiRouteTripEvidence> trips,
  required List<ScheduledDirectionEvidence> groups,
  DieselPriceEvidence? dieselPrice,
  ScheduledServiceEvidenceStatus scheduledStatus =
      ScheduledServiceEvidenceStatus.available,
  List<String> incompleteTripIds = const [],
  bool completeDirectionData = true,
}) {
  return CostEstimationEvidence(
    routeId: 'J15',
    referenceDate: referenceDate,
    periodStart: periodStart,
    periodEnd: periodEnd,
    network: AiRouteNetworkEvidence(route: route, trips: trips),
    scheduledService: ScheduledServiceEvidence(
      route: route,
      periodStart: periodStart,
      periodEnd: periodEnd,
      directionGroups: groups,
      incompleteTripIds: incompleteTripIds,
      status: scheduledStatus,
      hasCompleteDirectionData: completeDirectionData,
    ),
    dieselPrice: dieselPrice ?? availablePrice(3),
    unavailableInputs: const {
      UnavailableCostInput.busFuelConsumption,
      UnavailableCostInput.driverStaffCost,
      UnavailableCostInput.maintenanceCost,
      UnavailableCostInput.busAcquisitionCost,
      UnavailableCostInput.busStopConstructionCost,
      UnavailableCostInput.operatingCostPerKilometre,
      UnavailableCostInput.operatingCostPerHour,
    },
  );
}

AiRouteTripEvidence trip(String tripId, double? distanceMetres) {
  return AiRouteTripEvidence(
    tripId: tripId,
    shapeId: '$tripId-shape',
    stops: const [],
    shapePoints: const [],
    routeDistanceMeters: distanceMetres,
  );
}

ScheduledDirectionEvidence direction(
  int? directionId,
  List<ScheduledDepartureEvidence> departures,
) {
  return ScheduledDirectionEvidence(
    directionId: directionId,
    departures: departures,
    headwaysSeconds: const [],
    hourlyBuckets: const [],
    averageHeadwaySeconds: null,
    medianHeadwaySeconds: null,
    minimumHeadwaySeconds: null,
    maximumHeadwaySeconds: null,
  );
}

ScheduledDepartureEvidence departure(String tripId) {
  return ScheduledDepartureEvidence(
    tripId: tripId,
    serviceDate: DateTime(2026, 8, 21),
    departureSeconds: 8 * 3600,
    scheduledAt: DateTime.utc(2026, 8, 21),
    referenceStopId: 'first-stop',
    referenceStopSequence: 1,
  );
}

class FakeCostEvidenceRepository implements CostEstimationEvidenceRepository {
  FakeCostEvidenceRepository(this.result);

  final CostEstimationEvidence result;
  int callCount = 0;
  String? routeId;
  DateTime? startUtc;
  DateTime? endExclusiveUtc;
  DateTime? referenceDate;

  @override
  Future<CostEstimationEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  }) async {
    callCount++;
    this.routeId = routeId;
    this.startUtc = startUtc;
    this.endExclusiveUtc = endExclusiveUtc;
    this.referenceDate = referenceDate;
    return result;
  }
}
