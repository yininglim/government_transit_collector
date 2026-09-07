import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_repository.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

void main() {
  test(
    'counts each selected issue once without duplicating relevant reports',
    () async {
      final result =
          await repository(
            feedbackRepository: FakeFeedbackRepository([
              feedback('multi', '["Bus was late", "Bus overcrowded"]'),
            ]),
          ).loadEvidence(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );
      expect(result.feedback.countByIssueType, {
        'Bus was late': 1,
        'Bus overcrowded': 1,
      });
      expect(result.feedback.frequencyRelevantRecords, hasLength(1));
    },
  );

  test(
    'forwards the same route and half-open period to every repository',
    () async {
      final scheduledRepository = FakeScheduledRepository(scheduledEvidence());
      final operationalRepository = FakeOperationalRepository(
        operationalEvidence(),
      );
      final feedbackRepository = FakeFeedbackRepository(const []);

      await repository(
        scheduledRepository: scheduledRepository,
        operationalRepository: operationalRepository,
        feedbackRepository: feedbackRepository,
      ).loadEvidence(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      for (final call in [
        scheduledRepository.call,
        operationalRepository.call,
        feedbackRepository.call,
      ]) {
        expect(call?.routeId, 'J15');
        expect(call?.startUtc, same(periodStart));
        expect(call?.endExclusiveUtc, same(periodEnd));
      }
    },
  );

  test(
    'retains scheduled and operational evidence without recalculation',
    () async {
      final scheduled = scheduledEvidence(
        status: ScheduledServiceEvidenceStatus.incomplete,
        completeDirections: false,
      );
      final operational = operationalEvidence(limited: true);

      final result =
          await repository(
            scheduledRepository: FakeScheduledRepository(scheduled),
            operationalRepository: FakeOperationalRepository(operational),
          ).loadEvidence(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );

      expect(result.scheduledService, same(scheduled));
      expect(result.operational, same(operational));
      expect(
        result.scheduledService.status,
        ScheduledServiceEvidenceStatus.incomplete,
      );
      expect(result.scheduledService.incompleteTripIds, ['trip-missing']);
      expect(result.scheduledService.hasCompleteDirectionData, isFalse);
      expect(
        result.scheduledService.directionGroups.map(
          (group) => group.directionId,
        ),
        [0, 1],
      );
      expect(
        result.operational.peakOperationSummary.hasLimitedCoverage,
        isTrue,
      );
      expect(result.operational.peakOperationSummary.hasReliablePeak, isFalse);
      expect(
        result.operational.routePerformanceSummary.delayFrequencyPercent,
        isNull,
      );
    },
  );

  test(
    'counts actual issue types and preserves repeated and other records',
    () async {
      final records = [
        feedback('one', 'Bus was late'),
        feedback('two', 'Bus was late'),
        feedback('three', 'Bus overcrowded'),
        feedback('four', 'Bus did not arrive'),
        feedback('five', 'Other'),
        feedback('six', 'Unexpected stored value'),
      ];

      final result =
          await repository(
            feedbackRepository: FakeFeedbackRepository(records),
          ).loadEvidence(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );

      expect(result.feedback.totalRecordCount, 6);
      expect(result.feedback.countByIssueType['Bus was late'], 2);
      expect(result.feedback.countByIssueType['Other'], 1);
      expect(result.feedback.countByIssueType['Unexpected stored value'], 1);
      expect(result.feedback.frequencyRelevantRecordCount, 4);
      expect(
        result.feedback.frequencyRelevantRecords.map((item) => item.feedbackId),
        ['one', 'two', 'three', 'four'],
      );
      expect(result.feedback.records, hasLength(6));
    },
  );

  test('zero feedback is valid zero-count evidence', () async {
    final result = await repository().loadEvidence(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );

    expect(result.feedback.records, isEmpty);
    expect(result.feedback.countByIssueType, isEmpty);
    expect(result.feedback.totalRecordCount, 0);
    expect(result.feedback.frequencyRelevantRecordCount, 0);
  });

  test('rejects an empty or reversed analysis period', () {
    expect(
      () => repository().loadEvidence(
        routeId: 'J15',
        startUtc: periodEnd,
        endExclusiveUtc: periodStart,
      ),
      throwsA(isA<BusFrequencyEvidenceReadException>()),
    );
  });
}

final periodStart = DateTime.utc(2026, 8, 20);
final periodEnd = DateTime.utc(2026, 8, 27);

DefaultBusFrequencyEvidenceRepository repository({
  FakeScheduledRepository? scheduledRepository,
  FakeOperationalRepository? operationalRepository,
  FakeFeedbackRepository? feedbackRepository,
}) {
  return DefaultBusFrequencyEvidenceRepository(
    scheduledServiceRepository:
        scheduledRepository ?? FakeScheduledRepository(scheduledEvidence()),
    operationalRepository:
        operationalRepository ??
        FakeOperationalRepository(operationalEvidence()),
    feedbackRepository: feedbackRepository ?? FakeFeedbackRepository(const []),
  );
}

ScheduledServiceEvidence scheduledEvidence({
  ScheduledServiceEvidenceStatus status =
      ScheduledServiceEvidenceStatus.available,
  bool completeDirections = true,
}) {
  return ScheduledServiceEvidence(
    route: route,
    periodStart: periodStart,
    periodEnd: periodEnd,
    directionGroups: const [
      ScheduledDirectionEvidence(
        directionId: 0,
        departures: [],
        headwaysSeconds: [],
        hourlyBuckets: [],
        averageHeadwaySeconds: null,
        medianHeadwaySeconds: null,
        minimumHeadwaySeconds: null,
        maximumHeadwaySeconds: null,
      ),
      ScheduledDirectionEvidence(
        directionId: 1,
        departures: [],
        headwaysSeconds: [],
        hourlyBuckets: [],
        averageHeadwaySeconds: null,
        medianHeadwaySeconds: null,
        minimumHeadwaySeconds: null,
        maximumHeadwaySeconds: null,
      ),
    ],
    incompleteTripIds: status == ScheduledServiceEvidenceStatus.incomplete
        ? const ['trip-missing']
        : const [],
    status: status,
    hasCompleteDirectionData: completeDirections,
  );
}

AiOperationalEvidence operationalEvidence({bool limited = false}) {
  return AiOperationalEvidence(
    route: route,
    periodStart: periodStart,
    periodEnd: periodEnd,
    peakOperationSummary: PeakOperationSummary(
      routeId: 'J15',
      periodStart: periodStart,
      periodEnd: periodEnd,
      observationCount: 0,
      distinctTripOccurrences: 0,
      observedDayCount: 0,
      routesRepresented: 0,
      bucketBreakdown: const [],
      peakBuckets: const [],
      averageActivity: 0,
      activityDifferencePercent: 0,
      dailyActivity: const [],
      routeActivity: const [],
      observedWindowStart: null,
      observedWindowEnd: null,
      hasReliablePeak: false,
      hasLimitedCoverage: limited,
    ),
    routePerformanceSummary: const RoutePerformanceSummary(
      trips: [],
      totalObservations: 0,
      averageTravelTime: null,
      delayedTripCount: 0,
      delayFrequencyPercent: null,
      scheduleAdherencePercent: null,
    ),
  );
}

const route = RoutePerformanceRoute(
  routeId: 'J15',
  shortName: 'J15',
  longName: 'Johor route',
);

AdminFeedbackRecord feedback(String id, String issueType) {
  return AdminFeedbackRecord(
    feedbackId: id,
    routeId: 'J15',
    tripId: null,
    stopId: 'stop-1',
    issueType: issueType,
    comment: '',
    createdAt: periodStart,
  );
}

class RepositoryCall {
  const RepositoryCall(this.routeId, this.startUtc, this.endExclusiveUtc);

  final String routeId;
  final DateTime startUtc;
  final DateTime endExclusiveUtc;
}

class FakeScheduledRepository implements ScheduledServiceEvidenceRepository {
  FakeScheduledRepository(this.result);

  final ScheduledServiceEvidence result;
  RepositoryCall? call;

  @override
  Future<ScheduledServiceEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    call = RepositoryCall(routeId, startUtc, endExclusiveUtc);
    return result;
  }
}

class FakeOperationalRepository implements OperationalEvidenceRepository {
  FakeOperationalRepository(this.result);

  final AiOperationalEvidence result;
  RepositoryCall? call;

  @override
  Future<AiOperationalEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    call = RepositoryCall(routeId, startUtc, endExclusiveUtc);
    return result;
  }
}

class FakeFeedbackRepository implements AdminFeedbackRepository {
  FakeFeedbackRepository(this.result);

  final List<AdminFeedbackRecord> result;
  RepositoryCall? call;

  @override
  Future<List<AdminFeedbackRecord>> loadFeedback({
    String? routeId,
    String? issueType,
    DateTime? startUtc,
    DateTime? endExclusiveUtc,
  }) async {
    call = RepositoryCall(routeId!, startUtc!, endExclusiveUtc!);
    return result;
  }
}
