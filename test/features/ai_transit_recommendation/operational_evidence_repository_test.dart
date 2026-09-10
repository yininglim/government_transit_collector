import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_repository.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_calculator.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_calculator.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

void main() {
  test('fetches route performance data exactly once for the period', () async {
    final performanceRepository = FakeRoutePerformanceRepository();
    final start = DateTime.utc(2026, 8, 20);
    final end = DateTime.utc(2026, 8, 27);

    await repository(
      performanceRepository: performanceRepository,
    ).loadEvidence(routeId: 'J15', startUtc: start, endExclusiveUtc: end);

    expect(performanceRepository.loadCalls, 1);
    expect(performanceRepository.routeId, 'J15');
    expect(performanceRepository.startUtc, start);
    expect(performanceRepository.endExclusiveUtc, end);
  });

  test(
    'maps shared historical observations exactly for Peak Operation',
    () async {
      final data = completePerformanceData();
      final peakCalculator = RecordingPeakOperationCalculator();
      final performanceCalculator = RecordingRoutePerformanceCalculator();

      await repository(
        peakCalculator: peakCalculator,
        performanceCalculator: performanceCalculator,
        performanceRepository: FakeRoutePerformanceRepository(data: data),
      ).loadEvidence(
        routeId: 'J15',
        startUtc: DateTime.utc(2026, 8, 20),
        endExclusiveUtc: DateTime.utc(2026, 8, 27),
      );

      expect(performanceCalculator.data, same(data));
      expect(peakCalculator.observations, hasLength(data.observations.length));
      for (var index = 0; index < data.observations.length; index++) {
        final historical = data.observations[index];
        final peak = peakCalculator.observations[index];
        expect(peak.routeId, historical.routeId);
        expect(peak.tripId, historical.tripId);
        expect(peak.vehicleId, historical.vehicleId);
        expect(peak.recordedAt, same(historical.recordedAt));
      }
    },
  );

  test('delegates calculations and combines their exact summaries', () async {
    final peakCalculator = RecordingPeakOperationCalculator();
    final performanceCalculator = RecordingRoutePerformanceCalculator();
    final evidence =
        await repository(
          peakCalculator: peakCalculator,
          performanceCalculator: performanceCalculator,
        ).loadEvidence(
          routeId: 'J15',
          startUtc: DateTime.utc(2026, 8, 20),
          endExclusiveUtc: DateTime.utc(2026, 8, 27),
        );

    expect(peakCalculator.calls, 1);
    expect(performanceCalculator.calls, 1);
    expect(evidence.peakOperationSummary, same(peakCalculator.result));
    expect(
      evidence.routePerformanceSummary,
      same(performanceCalculator.result),
    );
    expect(evidence.route.routeId, 'J15');
    expect(evidence.route.displayName, contains('J15'));
  });

  test('preserves limited and insufficient coverage evidence', () async {
    final performanceRepository = FakeRoutePerformanceRepository(
      data: partialPerformanceData(),
    );
    final evidence =
        await repository(
          performanceRepository: performanceRepository,
        ).loadEvidence(
          routeId: 'J15',
          startUtc: DateTime.utc(2026, 8, 27),
          endExclusiveUtc: DateTime.utc(2026, 8, 28),
        );

    expect(evidence.peakOperationSummary.hasLimitedCoverage, isTrue);
    expect(evidence.peakOperationSummary.hasReliablePeak, isFalse);
    expect(evidence.routePerformanceSummary.completeTrips, isEmpty);
    expect(evidence.routePerformanceSummary.partialTripCount, 1);
    expect(
      evidence.routePerformanceSummary.trips.single.coverageStatus,
      TripCoverageStatus.insufficient,
    );
    expect(evidence.routePerformanceSummary.delayFrequencyPercent, isNull);
    expect(evidence.routePerformanceSummary.scheduleAdherencePercent, isNull);
    expect(evidence.routePerformanceSummary.averageTravelTime, isNull);
  });

  test('preserves equivalent summaries from the shared observations', () async {
    final data = completePerformanceData();
    final start = DateTime.utc(2026, 8, 27);
    final end = DateTime.utc(2026, 8, 28);
    final expectedRoute = const RoutePerformanceCalculator().calculate(data);
    final expectedPeak = const PeakOperationCalculator().calculate(
      observations: data.observations
          .map(
            (item) => PeakOperationObservation(
              routeId: item.routeId,
              tripId: item.tripId,
              vehicleId: item.vehicleId,
              recordedAt: item.recordedAt,
            ),
          )
          .toList(),
      periodStart: start,
      periodEnd: end,
      routeId: 'J15',
    );

    final evidence = await repository(
      performanceRepository: FakeRoutePerformanceRepository(data: data),
    ).loadEvidence(routeId: 'J15', startUtc: start, endExclusiveUtc: end);

    expect(
      evidence.routePerformanceSummary.totalObservations,
      expectedRoute.totalObservations,
    );
    expect(
      evidence.routePerformanceSummary.completeTrips.length,
      expectedRoute.completeTrips.length,
    );
    expect(
      evidence.routePerformanceSummary.averageTravelTime,
      expectedRoute.averageTravelTime,
    );
    expect(
      evidence.routePerformanceSummary.delayFrequencyPercent,
      expectedRoute.delayFrequencyPercent,
    );
    expect(
      evidence.routePerformanceSummary.scheduleAdherencePercent,
      expectedRoute.scheduleAdherencePercent,
    );
    expect(
      evidence.peakOperationSummary.observationCount,
      expectedPeak.observationCount,
    );
    expect(
      evidence.peakOperationSummary.distinctTripOccurrences,
      expectedPeak.distinctTripOccurrences,
    );
    expect(
      evidence.peakOperationSummary.peakBucket?.startMinute,
      expectedPeak.peakBucket?.startMinute,
    );
    expect(
      evidence.peakOperationSummary.averageActivity,
      expectedPeak.averageActivity,
    );
    expect(
      evidence.peakOperationSummary.hasReliablePeak,
      expectedPeak.hasReliablePeak,
    );
    expect(
      evidence.peakOperationSummary.busiestRoute?.routeId,
      expectedPeak.busiestRoute?.routeId,
    );
  });

  test('handles empty shared historical observations', () async {
    final evidence =
        await repository(
          performanceRepository: FakeRoutePerformanceRepository(
            data: const RoutePerformanceData(
              observations: [],
              schedulesByTripId: {},
            ),
          ),
        ).loadEvidence(
          routeId: 'J15',
          startUtc: DateTime.utc(2026, 8, 20),
          endExclusiveUtc: DateTime.utc(2026, 8, 27),
        );

    expect(evidence.routePerformanceSummary.totalObservations, 0);
    expect(evidence.peakOperationSummary.observationCount, 0);
    expect(evidence.peakOperationSummary.hasReliablePeak, isFalse);
  });

  test('wraps a shared historical loading failure', () {
    expect(
      () =>
          repository(
            performanceRepository: FakeRoutePerformanceRepository(
              failure: true,
            ),
          ).loadEvidence(
            routeId: 'J15',
            startUtc: DateTime.utc(2026, 8, 20),
            endExclusiveUtc: DateTime.utc(2026, 8, 27),
          ),
      throwsA(isA<OperationalEvidenceReadException>()),
    );
  });

  test('rejects a route absent from the existing route repository', () {
    expect(
      () => repository().loadEvidence(
        routeId: 'missing',
        startUtc: DateTime.utc(2026, 8, 20),
        endExclusiveUtc: DateTime.utc(2026, 8, 27),
      ),
      throwsA(isA<OperationalEvidenceReadException>()),
    );
  });
}

DefaultOperationalEvidenceRepository repository({
  PeakOperationCalculator? peakCalculator,
  FakeRoutePerformanceRepository? performanceRepository,
  RoutePerformanceCalculator? performanceCalculator,
}) {
  return DefaultOperationalEvidenceRepository(
    peakOperationCalculator: peakCalculator ?? const PeakOperationCalculator(),
    routePerformanceRepository:
        performanceRepository ?? FakeRoutePerformanceRepository(),
    routePerformanceCalculator:
        performanceCalculator ?? const RoutePerformanceCalculator(),
  );
}

class FakeRoutePerformanceRepository implements RoutePerformanceRepository {
  FakeRoutePerformanceRepository({
    RoutePerformanceData? data,
    this.failure = false,
  }) : data = data ?? completePerformanceData();

  final RoutePerformanceData data;
  final bool failure;
  int loadCalls = 0;
  String? routeId;
  DateTime? startUtc;
  DateTime? endExclusiveUtc;

  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() async => const [
    RoutePerformanceRoute(
      routeId: 'J15',
      shortName: 'J15',
      longName: 'Johor route',
    ),
  ];

  @override
  Future<RoutePerformanceData> loadRoutePerformance({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    loadCalls++;
    if (failure) throw Exception('network');
    this.routeId = routeId;
    this.startUtc = startUtc;
    this.endExclusiveUtc = endExclusiveUtc;
    return data;
  }
}

class RecordingPeakOperationCalculator extends PeakOperationCalculator {
  int calls = 0;
  PeakOperationSummary? result;
  List<PeakOperationObservation> observations = const [];

  @override
  PeakOperationSummary calculate({
    required List<PeakOperationObservation> observations,
    required DateTime periodStart,
    required DateTime periodEnd,
    String? routeId,
  }) {
    calls++;
    this.observations = observations;
    return result = super.calculate(
      observations: observations,
      periodStart: periodStart,
      periodEnd: periodEnd,
      routeId: routeId,
    );
  }
}

class RecordingRoutePerformanceCalculator extends RoutePerformanceCalculator {
  int calls = 0;
  RoutePerformanceSummary? result;
  RoutePerformanceData? data;

  @override
  RoutePerformanceSummary calculate(RoutePerformanceData data) {
    calls++;
    this.data = data;
    return result = super.calculate(data);
  }
}

RoutePerformanceData completePerformanceData() {
  final start = DateTime.utc(2026, 8, 27);
  return RoutePerformanceData(
    observations: [
      observation(start, 1, 103),
      observation(start.add(const Duration(minutes: 15)), 1.05, 103.05),
      observation(start.add(const Duration(minutes: 30)), 1.1, 103.1),
    ],
    schedulesByTripId: const {
      'trip-1': ScheduledTripReference(
        tripId: 'trip-1',
        startSeconds: 8 * 3600,
        endSeconds: 8 * 3600 + 30 * 60,
        startLatitude: 1,
        startLongitude: 103,
        endLatitude: 1.1,
        endLongitude: 103.1,
      ),
    },
  );
}

RoutePerformanceData partialPerformanceData() {
  return RoutePerformanceData(
    observations: [observation(DateTime.utc(2026, 8, 27), 1, 103)],
    schedulesByTripId: const {
      'trip-1': ScheduledTripReference(
        tripId: 'trip-1',
        startSeconds: 8 * 3600,
        endSeconds: 8 * 3600 + 30 * 60,
        startLatitude: 1,
        startLongitude: 103,
        endLatitude: 1.1,
        endLongitude: 103.1,
      ),
    },
  );
}

HistoricalVehicleObservation observation(
  DateTime recordedAt,
  double latitude,
  double longitude,
) {
  return HistoricalVehicleObservation(
    routeId: 'J15',
    tripId: 'trip-1',
    vehicleId: 'bus-1',
    recordedAt: recordedAt,
    latitude: latitude,
    longitude: longitude,
  );
}
