import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_priority.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/recommendation_management_page.dart';

void main() {
  testWidgets('shows loading and empty states', (tester) async {
    final gate = Completer<List<SavedRecommendation>>();
    final repository = FakeManagementRepository(loadGate: gate);
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    expect(find.text('Loading saved recommendations...'), findsOneWidget);

    gate.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('No Saved Recommendations'), findsOneWidget);
  });

  testWidgets('filters records and opens details', (tester) async {
    final repository = FakeManagementRepository(records: [
      saved(
        'older',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.pending,
        DateTime(2026, 9, 9),
      ),
      saved(
        'newer',
        RecommendationManagementFeature.routeBusStop,
        RecommendationReviewStatus.accepted,
        DateTime(2026, 9, 10),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    final cards = find.byKey(const Key('saved-recommendation-newer'));
    expect(cards, findsOneWidget);
    await tester.tap(find.byKey(const Key('management-feature-busFrequency')));
    await tester.pump();
    expect(find.byKey(const Key('saved-recommendation-older')), findsOneWidget);
    expect(find.byKey(const Key('saved-recommendation-newer')), findsNothing);

    await tester.tap(find.byKey(const Key('management-feature-all')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('management-status-accepted')));
    await tester.pump();
    expect(find.byKey(const Key('saved-recommendation-newer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('view-saved-newer')));
    await tester.pumpAndSettle();
    expect(find.text('Saved Recommendation'), findsOneWidget);
    expect(find.text('AI Rationale'), findsOneWidget);
  });

  testWidgets('filters and sorts deterministic priorities', (tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeManagementRepository(records: [
      saved(
        'low',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.accepted,
        DateTime(2026, 9, 11),
        priority: RecommendationPriorityLevel.low,
      ),
      saved(
        'high-old',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.pending,
        DateTime(2026, 9, 9),
        priority: RecommendationPriorityLevel.high,
      ),
      saved(
        'medium',
        RecommendationManagementFeature.routeBusStop,
        RecommendationReviewStatus.accepted,
        DateTime(2026, 9, 10),
        priority: RecommendationPriorityLevel.medium,
      ),
      saved(
        'high-new',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.pending,
        DateTime(2026, 9, 10),
        priority: RecommendationPriorityLevel.high,
      ),
      saved(
        'legacy',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.pending,
        DateTime(2026, 9, 12),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    final ordered = [
      'high-new',
      'high-old',
      'medium',
      'low',
      'legacy',
    ];
    for (var index = 1; index < ordered.length; index++) {
      expect(
        tester.getTopLeft(
          find.byKey(Key('saved-recommendation-${ordered[index - 1]}')),
        ).dy,
        lessThan(
          tester.getTopLeft(
            find.byKey(Key('saved-recommendation-${ordered[index]}')),
          ).dy,
        ),
      );
    }

    await tester.tap(find.byKey(const Key('management-feature-busFrequency')));
    await tester.tap(find.byKey(const Key('management-status-pending')));
    await tester.tap(find.byKey(const Key('management-priority-high')));
    await tester.pump();
    expect(find.byKey(const Key('saved-recommendation-high-new')), findsOneWidget);
    expect(find.byKey(const Key('saved-recommendation-high-old')), findsOneWidget);
    expect(find.byKey(const Key('saved-recommendation-medium')), findsNothing);
    expect(find.byKey(const Key('saved-recommendation-low')), findsNothing);
    expect(find.byKey(const Key('saved-recommendation-legacy')), findsNothing);

    await tester.tap(find.byKey(const Key('management-priority-all')));
    await tester.pump();
    expect(find.byKey(const Key('saved-recommendation-legacy')), findsOneWidget);
  });

  testWidgets('details show saved priority and reasons', (tester) async {
    final repository = FakeManagementRepository(records: [
      saved(
        'ranked',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.pending,
        DateTime(2026, 9, 10),
        priority: RecommendationPriorityLevel.high,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('view-saved-ranked')));
    await tester.pumpAndSettle();

    expect(find.text('High Priority'), findsWidgets);
    expect(find.text('Priority Reasons'), findsOneWidget);
    expect(find.text('Deterministic reason'), findsOneWidget);
  });

  testWidgets('updates note and status, then deletes with confirmation', (
    tester,
  ) async {
    final repository = FakeManagementRepository(records: [
      saved(
        'record',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.pending,
        DateTime(2026, 9, 10),
        priority: RecommendationPriorityLevel.high,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('view-saved-record')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('admin-note')), 'Reviewed note');
    await tester.tap(find.byType(DropdownButtonFormField<RecommendationReviewStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accepted').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-management-changes')));
    await tester.tap(find.byKey(const Key('save-management-changes')));
    await tester.pumpAndSettle();
    expect(repository.updatedStatus, RecommendationReviewStatus.accepted);
    expect(repository.updatedNote, 'Reviewed note');
    expect(find.text('High Priority'), findsOneWidget);

    await tester.tap(find.byKey(const Key('view-saved-record')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('delete-saved-recommendation')),
    );
    await tester.tap(find.byKey(const Key('delete-saved-recommendation')));
    await tester.pumpAndSettle();
    expect(find.text('Delete saved recommendation?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(repository.deletedId, 'record');
    expect(find.byKey(const Key('saved-recommendation-record')), findsNothing);
  });

  testWidgets('update failure preserves the edited note', (tester) async {
    final repository = FakeManagementRepository(
      records: [
        saved(
          'record',
          RecommendationManagementFeature.busFrequency,
          RecommendationReviewStatus.pending,
          DateTime(2026, 9, 10),
        ),
      ],
      failUpdate: true,
    );
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('view-saved-record')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('admin-note')), 'Unsaved note');
    await tester.ensureVisible(find.byKey(const Key('save-management-changes')));
    await tester.tap(find.byKey(const Key('save-management-changes')));
    await tester.pumpAndSettle();

    expect(find.text('Unable to update this recommendation.'), findsOneWidget);
    expect(find.text('Unsaved note'), findsOneWidget);
    expect(find.text('Saved Recommendation'), findsOneWidget);
  });
}

class FakeManagementRepository implements RecommendationManagementRepository {
  FakeManagementRepository({
    this.records = const [],
    this.loadGate,
    this.failUpdate = false,
  });

  final List<SavedRecommendation> records;
  final Completer<List<SavedRecommendation>>? loadGate;
  final bool failUpdate;
  RecommendationReviewStatus? updatedStatus;
  String? updatedNote;
  String? deletedId;

  @override
  Future<List<SavedRecommendation>> loadSavedRecommendations() =>
      loadGate?.future ?? Future.value(records);

  @override
  Future<SavedRecommendation> updateRecommendation({
    required SavedRecommendation recommendation,
    required RecommendationReviewStatus status,
    required String? adminNote,
  }) async {
    if (failUpdate) {
      throw const RecommendationManagementException('Update failed.');
    }
    updatedStatus = status;
    updatedNote = adminNote;
    return recommendation.copyWith(status: status, adminNote: adminNote);
  }

  @override
  Future<void> deleteRecommendation(String recommendationId) async {
    deletedId = recommendationId;
  }

  @override
  Future<SavedRecommendation> saveBusFrequencyRecommendation({
    required BusFrequencyRouteRecommendationRecord recommendation,
    required String routeDisplayLabel,
    required DateTime periodStart,
    required DateTime periodEnd,
    required BusFrequencyEvidence evidence,
  }) => throw UnimplementedError();

  @override
  Future<SavedRecommendation> saveRouteBusStopRecommendation({
    required RouteStopRecommendationRecord recommendation,
    required String routeDisplayLabel,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DistrictRouteStopEvidence evidence,
  }) => throw UnimplementedError();
}

SavedRecommendation saved(
  String id,
  RecommendationManagementFeature feature,
  RecommendationReviewStatus status,
  DateTime createdAt, {
  RecommendationPriorityLevel? priority,
}) => SavedRecommendation(
  recommendationId: id,
  feature: feature,
  routeId: 'J10',
  routeDisplayLabel: '$id route',
  actions: feature == RecommendationManagementFeature.busFrequency
      ? const ['increasePeakHourFrequency']
      : const ['routeImprovement', 'stopImprovement'],
  title: '$id title',
  rationale: '$id rationale',
  limitations: const ['Planning limitation'],
  evidenceReferences: const ['route.J10.evidence'],
  targetStopIds: const [],
  candidateArea: null,
  status: status,
  adminNote: null,
  createdAt: createdAt,
  updatedAt: createdAt,
  reviewedAt: null,
  priorityLevel: priority,
  priorityReasons: priority == null ? const [] : const ['Deterministic reason'],
);
