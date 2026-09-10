import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_priority.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';

import 'recommendation_priority_test_fixtures.dart';

void main() {
  test('maps management statuses to exact database enum values', () {
    expect(RecommendationReviewStatus.pending.databaseValue, 'pending_review');
    expect(RecommendationReviewStatus.accepted.databaseValue, 'accepted');
    expect(RecommendationReviewStatus.rejected.databaseValue, 'rejected');
    expect(
      RecommendationReviewStatus.fromDatabase('draft'),
      RecommendationReviewStatus.pending,
    );
    expect(RecommendationReviewStatus.fromDatabase('implemented'), isNull);
  });

  test('maps Bus Frequency save to existing database values', () async {
    final dataSource = FakeManagementDataSource();
    final repository = DefaultRecommendationManagementRepository(
      dataSource: dataSource,
    );
    final saved = await repository.saveBusFrequencyRecommendation(
      recommendation: const BusFrequencyRouteRecommendationRecord(
        routeId: 'J10',
        action: BusFrequencyRecommendationAction.increasePeakHourFrequency,
        conciseRationale: 'Increase service based on validated evidence.',
        evidenceRefs: ['route.J10.scheduled.summary'],
        limitations: ['Fleet availability is not known.'],
        source: BusFrequencyRecommendationSource.gemini,
      ),
      routeDisplayLabel: 'J10 — City Route',
      periodStart: DateTime.utc(2026, 8, 1),
      periodEnd: DateTime.utc(2026, 8, 31),
      evidence: busPriorityEvidence(),
    );

    expect(dataSource.analysisReport['analysis_type'], 'route_performance');
    expect(dataSource.recommendation['recommendation_type'], 'bus_frequency');
    expect(dataSource.recommendation['route_id'], 'J10');
    expect(dataSource.recommendation['stop_id'], isNull);
    expect(dataSource.recommendation['priority'], 3);
    expect(dataSource.recommendation['status'], 'pending_review');
    expect(dataSource.recommendation['estimated_cost'], isNull);
    final snapshot = dataSource.recommendation['supporting_metrics'] as Map;
    expect(snapshot['feature_type'], 'bus_frequency');
    expect(snapshot['action'], 'increasePeakHourFrequency');
    expect(snapshot['priority_rule_version'], 1);
    expect(snapshot['priority_level'], 'medium');
    expect(snapshot['priority_reasons'], ['Service change recommended']);
    expect(saved.priorityLevel, RecommendationPriorityLevel.medium);
  });

  test('maps one multi-action Route and Stop record to one row', () async {
    final dataSource = FakeManagementDataSource();
    final repository = DefaultRecommendationManagementRepository(
      dataSource: dataSource,
    );
    final saved = await repository.saveRouteBusStopRecommendation(
      recommendation: const RouteStopRecommendationRecord(
        routeId: 'J20',
        actions: [
          RouteStopRecommendationAction.routeImprovement,
          RouteStopRecommendationAction.stopImprovement,
        ],
        conciseRationale: 'Improve the route and its validated target stop.',
        routeOwnedEvidenceRefs: ['route.J20.network'],
        candidateArea: null,
        limitations: ['Implementation design is not included.'],
        targetStopIds: ['S1'],
      ),
      routeDisplayLabel: 'J20 — Cross Town',
      periodStart: DateTime.utc(2026, 8, 1),
      periodEnd: DateTime.utc(2026, 8, 31),
      evidence: routeStopPriorityEvidence(delayedTrips: 1),
    );

    expect(dataSource.insertCount, 1);
    expect(dataSource.recommendation['recommendation_type'], 'route_improvement');
    expect(dataSource.recommendation['stop_id'], isNull);
    final snapshot = dataSource.recommendation['supporting_metrics'] as Map;
    expect(snapshot['actions'], ['routeImprovement', 'stopImprovement']);
    expect(snapshot['target_stop_ids'], ['S1']);
    expect(snapshot['priority_rule_version'], 1);
    expect(snapshot['priority_level'], 'high');
    expect(dataSource.recommendation['priority'], 1);
    expect(saved.priorityLevel, RecommendationPriorityLevel.high);
  });

  test('priority rules are conservative and require multiple signals', () {
    expect(RecommendationPriorityLevel.high.databaseValue, 1);
    expect(RecommendationPriorityLevel.medium.databaseValue, 3);
    expect(RecommendationPriorityLevel.low.databaseValue, 5);
    final maintain = RecommendationPriorityCalculator.busFrequency(
      action: BusFrequencyRecommendationAction.maintainService,
      evidence: busPriorityEvidence(delayedTrips: 5, feedbackCount: 2),
    );
    final medium = RecommendationPriorityCalculator.busFrequency(
      action: BusFrequencyRecommendationAction.decreaseService,
      evidence: busPriorityEvidence(delayedTrips: 1),
    );
    final high = RecommendationPriorityCalculator.busFrequency(
      action: BusFrequencyRecommendationAction.increasePeakHourFrequency,
      evidence: busPriorityEvidence(
        delayedTrips: 1,
        reliablePeak: true,
      ),
    );
    final routeMaintain = RecommendationPriorityCalculator.routeBusStop(
      actions: const [
        RouteStopRecommendationAction.maintainCurrentConfiguration,
      ],
      evidence: routeStopPriorityEvidence(delayedTrips: 2, feedbackCount: 2),
    );
    final routeMedium = RecommendationPriorityCalculator.routeBusStop(
      actions: const [RouteStopRecommendationAction.stopImprovement],
      evidence: routeStopPriorityEvidence(feedbackCount: 1),
    );
    final routeHigh = RecommendationPriorityCalculator.routeBusStop(
      actions: const [
        RouteStopRecommendationAction.routeImprovement,
        RouteStopRecommendationAction.stopImprovement,
      ],
      evidence: routeStopPriorityEvidence(delayedTrips: 1),
    );

    expect(maintain.level, RecommendationPriorityLevel.low);
    expect(medium.level, RecommendationPriorityLevel.medium);
    expect(high.level, RecommendationPriorityLevel.high);
    expect(routeMaintain.level, RecommendationPriorityLevel.low);
    expect(routeMedium.level, RecommendationPriorityLevel.medium);
    expect(routeHigh.level, RecommendationPriorityLevel.high);
  });

  test('loads valid rows and ignores unsupported rows safely', () async {
    final dataSource = FakeManagementDataSource()
      ..rows = [
        row(id: 'valid'),
        {...row(id: 'unsupported'), 'status': 'archived'},
        {...row(id: 'fallback'), 'supporting_metrics': 'invalid'},
      ];
    final repository = DefaultRecommendationManagementRepository(
      dataSource: dataSource,
    );

    final records = await repository.loadSavedRecommendations();

    expect(records.map((record) => record.recommendationId), [
      'fallback',
      'valid',
    ]);
    expect(records.first.feature, RecommendationManagementFeature.busFrequency);
    expect(records.first.priorityLevel, isNull);
  });

  test('parses only versioned valid priority snapshots', () {
    final validMetrics = Map<String, dynamic>.from(
      row(id: 'valid-priority')['supporting_metrics'] as Map,
    )
      ..addAll({
        'priority_rule_version': 1,
        'priority_level': 'low',
        'priority_reasons': ['Maintain-current-service recommendation'],
      });
    final malformedMetrics = Map<String, dynamic>.from(validMetrics)
      ..['priority_level'] = 'urgent';

    final valid = SavedRecommendation.fromJson({
      ...row(id: 'valid-priority'),
      'supporting_metrics': validMetrics,
      'priority': 5,
    });
    final malformed = SavedRecommendation.fromJson({
      ...row(id: 'malformed-priority'),
      'supporting_metrics': malformedMetrics,
      'priority': 1,
    });

    expect(valid.priorityLevel, RecommendationPriorityLevel.low);
    expect(valid.priorityReasons, ['Maintain-current-service recommendation']);
    expect(malformed.priorityLevel, isNull);
    expect(malformed.priorityReasons, isEmpty);
  });
}

class FakeManagementDataSource implements RecommendationManagementDataSource {
  Map<String, dynamic> analysisReport = {};
  Map<String, dynamic> recommendation = {};
  List<Map<String, dynamic>> rows = [];
  int insertCount = 0;

  @override
  Future<Map<String, dynamic>> insertRecommendation({
    required Map<String, dynamic> analysisReport,
    required Map<String, dynamic> recommendation,
  }) async {
    insertCount++;
    this.analysisReport = analysisReport;
    this.recommendation = recommendation;
    return {
      ...recommendation,
      'recommendation_id': 'saved-$insertCount',
      'created_at': '2026-09-10T00:00:00Z',
      'updated_at': '2026-09-10T00:00:00Z',
      'reviewed_at': null,
      'admin_notes': null,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRecommendations() async => rows;

  @override
  Future<Map<String, dynamic>> updateRecommendation({
    required String recommendationId,
    required String status,
    required String? adminNote,
  }) async => {
    ...row(id: recommendationId),
    'status': status,
    'admin_notes': adminNote,
  };

  @override
  Future<void> deleteRecommendation(String recommendationId) async {}
}

Map<String, dynamic> row({required String id}) => {
  'recommendation_id': id,
  'recommendation_type': 'bus_frequency',
  'route_id': 'J10',
  'title': 'Increase frequency — J10',
  'description': 'Validated rationale.',
  'status': 'pending_review',
  'admin_notes': null,
  'reviewed_at': null,
  'created_at': id == 'fallback'
      ? '2026-09-11T00:00:00Z'
      : '2026-09-10T00:00:00Z',
  'updated_at': '2026-09-10T00:00:00Z',
  'supporting_metrics': {
    'feature_type': 'bus_frequency',
    'route_display_label': 'J10 — City Route',
    'action': 'increasePeakHourFrequency',
    'evidence_refs': ['route.J10.scheduled.summary'],
  },
};
