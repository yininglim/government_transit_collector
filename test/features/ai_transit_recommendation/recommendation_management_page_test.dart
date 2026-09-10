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
    await _tapVisible(
      tester,
      find.byKey(const Key('management-feature-busFrequency')),
    );
    expect(find.byKey(const Key('saved-recommendation-older')), findsOneWidget);
    expect(find.byKey(const Key('saved-recommendation-newer')), findsNothing);

    await _tapVisible(tester, find.byKey(const Key('management-feature-all')));
    await _tapVisible(
      tester,
      find.byKey(const Key('management-status-accepted')),
    );
    expect(find.byKey(const Key('saved-recommendation-newer')), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('view-saved-newer')));
    expect(find.text('Saved Recommendation'), findsOneWidget);
    expect(find.text('AI Rationale'), findsOneWidget);
  });

  testWidgets('filters and sorts deterministic priorities', (tester) async {
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
    for (final id in ordered) {
      final card = find.byKey(Key('saved-recommendation-$id'));
      await tester.scrollUntilVisible(
        card,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(card, findsOneWidget);
    }

    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 2400),
      10000,
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const Key('management-feature-busFrequency')),
    );
    await _tapVisible(
      tester,
      find.byKey(const Key('management-status-pending')),
    );
    await _tapVisible(
      tester,
      find.byKey(const Key('management-priority-high')),
    );
    await _scrollToVisible(
      tester,
      find.byKey(const Key('saved-recommendation-high-new')),
    );
    expect(find.byKey(const Key('saved-recommendation-high-new')), findsOneWidget);
    await _scrollToVisible(
      tester,
      find.byKey(const Key('saved-recommendation-high-old')),
    );
    expect(find.byKey(const Key('saved-recommendation-high-old')), findsOneWidget);
    expect(find.byKey(const Key('saved-recommendation-medium')), findsNothing);
    expect(find.byKey(const Key('saved-recommendation-low')), findsNothing);
    expect(find.byKey(const Key('saved-recommendation-legacy')), findsNothing);

    await _tapVisible(
      tester,
      find.byKey(const Key('management-priority-all')),
      scrollDelta: -240,
    );
    await _scrollToVisible(
      tester,
      find.byKey(const Key('saved-recommendation-legacy')),
    );
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
    await _tapVisible(tester, find.byKey(const Key('view-saved-ranked')));
    expect(find.text('Saved Recommendation'), findsOneWidget);

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
    await _tapVisible(tester, find.byKey(const Key('view-saved-record')));
    expect(find.text('Saved Recommendation'), findsOneWidget);
    await _scrollToVisible(tester, find.byKey(const Key('admin-note')));
    await tester.enterText(find.byKey(const Key('admin-note')), 'Reviewed note');
    await _tapVisible(
      tester,
      find.byType(DropdownButtonFormField<RecommendationReviewStatus>),
    );
    await tester.tap(find.text('Accepted').last);
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const Key('save-management-changes')),
    );
    expect(find.text('Accept Recommendation?'), findsOneWidget);
    expect(repository.updatedStatus, isNull);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(repository.updatedStatus, RecommendationReviewStatus.accepted);
    expect(repository.updatedNote, 'Reviewed note');
    expect(find.text('High Priority'), findsOneWidget);

    await _tapVisible(tester, find.byKey(const Key('view-saved-record')));
    expect(find.text('Saved Recommendation'), findsOneWidget);
    await _tapVisible(
      tester,
      find.byKey(const Key('delete-saved-recommendation')),
    );
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
    await _tapVisible(tester, find.byKey(const Key('view-saved-record')));
    expect(find.text('Saved Recommendation'), findsOneWidget);
    await _scrollToVisible(tester, find.byKey(const Key('admin-note')));
    await tester.enterText(find.byKey(const Key('admin-note')), 'Unsaved note');
    await _tapVisible(
      tester,
      find.byKey(const Key('save-management-changes')),
    );

    expect(find.text('Unable to update this recommendation.'), findsOneWidget);
    expect(find.text('Unsaved note'), findsOneWidget);
    expect(find.text('Saved Recommendation'), findsOneWidget);
  });

  testWidgets('cancelling acceptance keeps the recommendation pending', (
    tester,
  ) async {
    final repository = FakeManagementRepository(records: [
      saved(
        'record',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.pending,
        DateTime(2026, 9, 10),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('view-saved-record')));
    await _tapVisible(
      tester,
      find.byType(DropdownButtonFormField<RecommendationReviewStatus>),
    );
    await tester.tap(find.text('Accepted').last);
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const Key('save-management-changes')),
    );

    expect(find.text('Accept Recommendation?'), findsOneWidget);
    expect(repository.updatedStatus, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.updatedStatus, isNull);
    await _scrollToVisible(
      tester,
      find.byType(DropdownButtonFormField<RecommendationReviewStatus>),
      scrollDelta: -240,
    );
    final statusControl =
        find.byType(DropdownButtonFormField<RecommendationReviewStatus>);
    expect(statusControl, findsOneWidget);
    expect(
      find.descendant(of: statusControl, matching: find.text('Pending')),
      findsOneWidget,
    );
  });

  testWidgets('pending recommendation requires confirmation before rejection', (
    tester,
  ) async {
    final repository = FakeManagementRepository(records: [
      saved(
        'record',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.pending,
        DateTime(2026, 9, 10),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('view-saved-record')));
    await _tapVisible(
      tester,
      find.byType(DropdownButtonFormField<RecommendationReviewStatus>),
    );
    await tester.tap(find.text('Rejected').last);
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const Key('save-management-changes')),
    );

    expect(find.text('Reject Recommendation?'), findsOneWidget);
    expect(repository.updatedStatus, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.updatedStatus, isNull);
    await _tapVisible(
      tester,
      find.byType(DropdownButtonFormField<RecommendationReviewStatus>),
      scrollDelta: -240,
    );
    await tester.tap(find.text('Rejected').last);
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const Key('save-management-changes')),
    );
    expect(find.text('Reject Recommendation?'), findsOneWidget);
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(repository.updatedStatus, RecommendationReviewStatus.rejected);
    expect(
      find.descendant(
        of: find.byKey(const Key('saved-recommendation-record')),
        matching: find.text('Rejected'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('final decision keeps Admin Note editable and priority unchanged', (
    tester,
  ) async {
    final repository = FakeManagementRepository(records: [
      saved(
        'record',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.accepted,
        DateTime(2026, 9, 10),
        priority: RecommendationPriorityLevel.high,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('view-saved-record')));
    await _scrollToVisible(tester, find.text('Accepted (Final)'));
    expect(
      find.byType(DropdownButtonFormField<RecommendationReviewStatus>),
      findsNothing,
    );
    await _scrollToVisible(tester, find.byKey(const Key('admin-note')));
    await tester.enterText(find.byKey(const Key('admin-note')), 'Final note');
    await _tapVisible(
      tester,
      find.byKey(const Key('save-management-changes')),
    );

    expect(repository.updatedStatus, RecommendationReviewStatus.accepted);
    expect(repository.updatedNote, 'Final note');
    expect(find.text('High Priority'), findsOneWidget);
  });

  testWidgets('follow-up creation is available only for accepted records', (
    tester,
  ) async {
    final repository = FakeManagementRepository(records: [
      saved(
        'pending',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.pending,
        DateTime(2026, 9, 10),
      ),
      saved(
        'rejected',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.rejected,
        DateTime(2026, 9, 10),
      ),
      saved(
        'accepted',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.accepted,
        DateTime(2026, 9, 10),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const Key('view-saved-pending')));
    expect(find.text('Saved Recommendation'), findsOneWidget);
    await _scrollToVisible(
      tester,
      find.byType(DropdownButtonFormField<RecommendationReviewStatus>),
    );
    expect(
      find.byType(DropdownButtonFormField<RecommendationReviewStatus>),
      findsOneWidget,
    );
    await _scrollToVisible(
      tester,
      find.text(
        'A follow-up action can be created after this recommendation is Accepted.',
      ),
    );
    expect(find.text('Create Follow-up Action'), findsNothing);
    expect(
      find.text(
        'A follow-up action can be created after this recommendation is Accepted.',
      ),
      findsOneWidget,
    );
    await _tapVisible(tester, find.byIcon(Icons.arrow_back));

    await _tapVisible(tester, find.byKey(const Key('view-saved-rejected')));
    expect(find.text('Saved Recommendation'), findsOneWidget);
    await _scrollToVisible(tester, find.text('Rejected (Final)'));
    expect(
      find.byType(DropdownButtonFormField<RecommendationReviewStatus>),
      findsNothing,
    );
    expect(find.text('Follow-up Action'), findsNothing);
    expect(
      find.text(
        'A follow-up action can be created after this recommendation is Accepted.',
      ),
      findsNothing,
    );
    expect(find.text('Create Follow-up Action'), findsNothing);
    await _scrollToVisible(tester, find.byKey(const Key('admin-note')));
    expect(
      tester.widget<TextField>(find.byKey(const Key('admin-note'))).enabled,
      isTrue,
    );
    await _tapVisible(tester, find.byIcon(Icons.arrow_back));

    await _tapVisible(tester, find.byKey(const Key('view-saved-accepted')));
    expect(find.text('Saved Recommendation'), findsOneWidget);
    await _scrollToVisible(tester, find.text('Accepted (Final)'));
    expect(
      find.byType(DropdownButtonFormField<RecommendationReviewStatus>),
      findsNothing,
    );
    await _scrollToVisible(tester, find.byKey(const Key('save-follow-up')));
    expect(find.text('Create Follow-up Action'), findsWidgets);
    await tester.tap(find.byKey(const Key('save-follow-up')));
    await tester.pumpAndSettle();
    expect(find.text('Enter an action or task.'), findsOneWidget);
    expect(find.text('Select a due date.'), findsOneWidget);
    expect(repository.followUpCreateCalls, 0);

    await tester.enterText(
      find.byKey(const Key('follow-up-action')),
      'Review timetable',
    );
    await _tapVisible(tester, find.byKey(const Key('follow-up-due-date')));
    await tester.tap(find.text(DateTime.now().day.toString()).last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('save-follow-up')));
    expect(repository.followUpCreateCalls, 1);
    expect(find.text('Follow-up action created.'), findsOneWidget);
    expect(find.text('Follow-up Status'), findsOneWidget);
  });

  testWidgets('existing follow-up displays and updates independently', (
    tester,
  ) async {
    final followUp = RecommendationFollowUp(
      followUpId: 'follow-up-record',
      recommendationId: 'record',
      actionText: 'Review timetable',
      dueDate: DateTime(2026, 9, 15),
      status: RecommendationFollowUpStatus.pending,
      note: 'Coordinate review',
      createdAt: DateTime(2026, 9, 11),
      updatedAt: DateTime(2026, 9, 11),
      completedAt: null,
    );
    final repository = FakeManagementRepository(records: [
      saved(
        'record',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.rejected,
        DateTime(2026, 9, 10),
        priority: RecommendationPriorityLevel.high,
        followUp: followUp,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Follow-up: Pending'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('view-saved-record')));
    expect(find.text('Saved Recommendation'), findsOneWidget);
    await _scrollToVisible(tester, find.byKey(const Key('follow-up-action')));

    expect(find.text('Review timetable'), findsOneWidget);
    expect(
      find.text(
        'This follow-up is retained for history because the recommendation is no longer Accepted.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('follow-up-action')),
      'Review revised timetable',
    );
    await tester.enterText(
      find.byKey(const Key('follow-up-note')),
      'Updated coordination note',
    );
    await _tapVisible(
      tester,
      find.byType(DropdownButtonFormField<RecommendationFollowUpStatus>),
    );
    await tester.tap(find.text('In Progress').last);
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('save-follow-up')));

    expect(repository.followUpUpdateCalls, 1);
    expect(find.text('Follow-up action updated.'), findsOneWidget);
    await _scrollToVisible(
      tester,
      find.text('High Priority'),
      scrollDelta: -240,
    );
    expect(find.text('High Priority'), findsWidgets);
  });

  testWidgets('delete confirmation mentions an existing follow-up', (
    tester,
  ) async {
    final repository = FakeManagementRepository(records: [
      saved(
        'record',
        RecommendationManagementFeature.busFrequency,
        RecommendationReviewStatus.accepted,
        DateTime(2026, 9, 10),
        followUp: RecommendationFollowUp(
          followUpId: 'follow-up-record',
          recommendationId: 'record',
          actionText: 'Review timetable',
          dueDate: DateTime(2026, 9, 15),
          status: RecommendationFollowUpStatus.completed,
          note: null,
          createdAt: DateTime(2026, 9, 11),
          updatedAt: DateTime(2026, 9, 12),
          completedAt: DateTime(2026, 9, 12),
        ),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: RecommendationManagementPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Follow-up: Completed'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('view-saved-record')));
    expect(find.text('Saved Recommendation'), findsOneWidget);
    await _tapVisible(
      tester,
      find.byKey(const Key('delete-saved-recommendation')),
    );
    expect(
      find.text(
        'This removes the saved recommendation and its follow-up action from Recommendation Management. It does not change the original generated result or any bus service data.',
      ),
      findsOneWidget,
    );
  });
}

Future<void> _tapVisible(
  WidgetTester tester,
  Finder finder, {
  double scrollDelta = 240,
}) async {
  await _scrollToVisible(tester, finder, scrollDelta: scrollDelta);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _scrollToVisible(
  WidgetTester tester,
  Finder finder, {
  double scrollDelta = 240,
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      scrollDelta,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
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
  int followUpCreateCalls = 0;
  int followUpUpdateCalls = 0;

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
  Future<SavedRecommendation> createFollowUp({
    required SavedRecommendation recommendation,
    required String actionText,
    required DateTime dueDate,
    required String? note,
  }) async {
    followUpCreateCalls++;
    return recommendation.copyWith(
      followUp: RecommendationFollowUp(
        followUpId: 'follow-up-${recommendation.recommendationId}',
        recommendationId: recommendation.recommendationId,
        actionText: actionText.trim(),
        dueDate: dueDate,
        status: RecommendationFollowUpStatus.pending,
        note: note?.trim(),
        createdAt: DateTime(2026, 9, 11),
        updatedAt: DateTime(2026, 9, 11),
        completedAt: null,
      ),
    );
  }

  @override
  Future<SavedRecommendation> updateFollowUp({
    required SavedRecommendation recommendation,
    required String actionText,
    required DateTime dueDate,
    required RecommendationFollowUpStatus status,
    required String? note,
  }) async {
    followUpUpdateCalls++;
    final current = recommendation.followUp!;
    return recommendation.copyWith(
      followUp: RecommendationFollowUp(
        followUpId: current.followUpId,
        recommendationId: current.recommendationId,
        actionText: actionText.trim(),
        dueDate: dueDate,
        status: status,
        note: note?.trim(),
        createdAt: current.createdAt,
        updatedAt: DateTime(2026, 9, 12),
        completedAt: status == RecommendationFollowUpStatus.completed
            ? DateTime(2026, 9, 12)
            : null,
      ),
    );
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
  RecommendationFollowUp? followUp,
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
  followUp: followUp,
);
