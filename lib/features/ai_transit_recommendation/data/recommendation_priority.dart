import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';

enum RecommendationPriorityLevel {
  high(1, 'high'),
  medium(3, 'medium'),
  low(5, 'low');

  const RecommendationPriorityLevel(this.databaseValue, this.snapshotValue);

  final int databaseValue;
  final String snapshotValue;

  static RecommendationPriorityLevel? fromSnapshot(Object? value) =>
      switch (value) {
        'high' => RecommendationPriorityLevel.high,
        'medium' => RecommendationPriorityLevel.medium,
        'low' => RecommendationPriorityLevel.low,
        _ => null,
      };
}

class RecommendationPriority {
  const RecommendationPriority({required this.level, required this.reasons});

  final RecommendationPriorityLevel level;
  final List<String> reasons;
}

abstract final class RecommendationPriorityCalculator {
  static RecommendationPriority busFrequency({
    required BusFrequencyRecommendationAction action,
    required BusFrequencyEvidence evidence,
  }) {
    if (action == BusFrequencyRecommendationAction.maintainService) {
      return const RecommendationPriority(
        level: RecommendationPriorityLevel.low,
        reasons: ['Maintain-current-service recommendation'],
      );
    }
    final reasons = <String>['Service change recommended'];
    var supportingSignals = 0;
    if (evidence.operational.routePerformanceSummary.delayedTripCount > 0) {
      supportingSignals++;
      reasons.add('Delayed-trip evidence present');
    }
    final peak = evidence.operational.peakOperationSummary;
    if (peak.hasReliablePeak && peak.observationCount > 0) {
      supportingSignals++;
      reasons.add('Reliable peak-operation evidence present');
    }
    if (evidence.feedback.frequencyRelevantRecordCount > 0) {
      supportingSignals++;
      reasons.add('Relevant frequency feedback present');
    }
    return RecommendationPriority(
      level: supportingSignals >= 2
          ? RecommendationPriorityLevel.high
          : RecommendationPriorityLevel.medium,
      reasons: List.unmodifiable(reasons),
    );
  }

  static RecommendationPriority routeBusStop({
    required List<RouteStopRecommendationAction> actions,
    required DistrictRouteStopEvidence evidence,
  }) {
    final actionable = actions
        .where(
          (action) =>
              action != RouteStopRecommendationAction.insufficientEvidence,
        )
        .toList(growable: false);
    if (actionable.length == 1 &&
        actionable.single ==
            RouteStopRecommendationAction.maintainCurrentConfiguration) {
      return const RecommendationPriority(
        level: RecommendationPriorityLevel.low,
        reasons: ['Maintain-current-configuration recommendation'],
      );
    }
    final reasons = <String>['Route or stop change recommended'];
    var supportingSignals = 0;
    final source = evidence.routeStopEvidence;
    if (source.operational.routePerformanceSummary.delayedTripCount > 0) {
      supportingSignals++;
      reasons.add('Delayed-trip evidence present');
    }
    if (source.feedback.routeStopRelevantRecordCount > 0) {
      supportingSignals++;
      reasons.add('Relevant route or stop feedback present');
    }
    if (actionable.length > 1) {
      supportingSignals++;
      reasons.add('Multiple route or stop improvements recommended');
    }
    return RecommendationPriority(
      level: supportingSignals >= 2
          ? RecommendationPriorityLevel.high
          : RecommendationPriorityLevel.medium,
      reasons: List.unmodifiable(reasons),
    );
  }
}

String recommendationPriorityLabel(RecommendationPriorityLevel priority) =>
    switch (priority) {
      RecommendationPriorityLevel.high => 'High Priority',
      RecommendationPriorityLevel.medium => 'Medium Priority',
      RecommendationPriorityLevel.low => 'Low Priority',
    };
