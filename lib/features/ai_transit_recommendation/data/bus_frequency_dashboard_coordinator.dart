import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';

const busFrequencyDashboardBatchSize = 3;

class BusFrequencyDashboardCandidate {
  const BusFrequencyDashboardCandidate({
    required this.route,
    required this.evidence,
  });

  final RoutePerformanceRoute route;
  final BusFrequencyEvidence evidence;
}

class BusFrequencyDashboardEntry {
  const BusFrequencyDashboardEntry({required this.route, required this.result});

  final RoutePerformanceRoute route;
  final BusFrequencyRecommendationResult result;
}

class BusFrequencyDashboardCoordinator {
  BusFrequencyDashboardCoordinator({
    RoutePerformanceRepository? routeRepository,
    BusFrequencyEvidenceRepository? evidenceRepository,
    BusFrequencyRecommendationRepository? recommendationRepository,
  }) : _routeRepository =
           routeRepository ?? DefaultRoutePerformanceRepository(),
       _evidenceRepository =
           evidenceRepository ?? DefaultBusFrequencyEvidenceRepository(),
       _recommendationRepository =
           recommendationRepository ??
           DefaultBusFrequencyRecommendationRepository();

  final RoutePerformanceRepository _routeRepository;
  final BusFrequencyEvidenceRepository _evidenceRepository;
  final BusFrequencyRecommendationRepository _recommendationRepository;

  Future<List<BusFrequencyDashboardCandidate>> screenCandidates({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    final routes = await _routeRepository.loadRoutes();
    final ordered = [...routes]..sort(_compareRoutes);
    final candidates = <BusFrequencyDashboardCandidate>[];
    for (final route in ordered) {
      try {
        final evidence = await _evidenceRepository.loadEvidence(
          routeId: route.routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        );
        if (isBusFrequencyDashboardEligible(evidence)) {
          candidates.add(
            BusFrequencyDashboardCandidate(route: route, evidence: evidence),
          );
        }
      } on Object {
        continue;
      }
    }
    return candidates;
  }

  Future<List<BusFrequencyDashboardEntry>> analyseBatch({
    required List<BusFrequencyDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    void Function(int completed, int total, BusFrequencyDashboardEntry entry)?
    onCompleted,
  }) async {
    final batch = candidates.take(busFrequencyDashboardBatchSize).toList();
    final entries = <BusFrequencyDashboardEntry>[];
    for (var index = 0; index < batch.length; index++) {
      final candidate = batch[index];
      BusFrequencyRecommendationResult result;
      try {
        result = await _recommendationRepository.generate(
          routeId: candidate.route.routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        );
      } on Object {
        result = const BusFrequencyRecommendationResult(
          status: BusFrequencyRecommendationStatus.temporarilyUnavailable,
          recommendation: null,
          failure: BusFrequencyRecommendationFailure.network,
          evidence: null,
          payload: null,
        );
      }
      final entry = BusFrequencyDashboardEntry(
        route: candidate.route,
        result: result,
      );
      entries.add(entry);
      onCompleted?.call(index + 1, batch.length, entry);
    }
    return entries;
  }

  Future<BusFrequencyDashboardEntry> retry({
    required BusFrequencyDashboardCandidate candidate,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    final result = await _recommendationRepository.generate(
      routeId: candidate.route.routeId,
      startUtc: startUtc,
      endExclusiveUtc: endExclusiveUtc,
    );
    return BusFrequencyDashboardEntry(route: candidate.route, result: result);
  }
}

bool isBusFrequencyDashboardEligible(BusFrequencyEvidence evidence) {
  final scheduled = evidence.scheduledService;
  if (scheduled.scheduledDepartureCount == 0 ||
      scheduled.status == ScheduledServiceEvidenceStatus.noDepartures) {
    return false;
  }
  final hasHeadway = scheduled.directionGroups.any(
    (group) => group.headwaysSeconds.isNotEmpty,
  );
  final hasOperationalEvidence =
      evidence.operational.peakOperationSummary.observationCount > 0 ||
      evidence.operational.routePerformanceSummary.totalObservations > 0;
  final hasRelevantFeedback =
      evidence.feedback.frequencyRelevantRecordCount > 0;
  return hasHeadway || hasOperationalEvidence || hasRelevantFeedback;
}

int _compareRoutes(RoutePerformanceRoute first, RoutePerformanceRoute second) {
  final display = first.displayName.toLowerCase().compareTo(
    second.displayName.toLowerCase(),
  );
  return display != 0 ? display : first.routeId.compareTo(second.routeId);
}
