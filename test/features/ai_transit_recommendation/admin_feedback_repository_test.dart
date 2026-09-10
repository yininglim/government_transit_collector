import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';

void main() {
  test('maps supported feedback fields', () {
    final record = AdminFeedbackRecord.fromMap({
      'feedback_id': 'feedback-1',
      'route_id': 'J15',
      'trip_id': 'trip-1',
      'stop_id': 'stop-1',
      'issue_type': 'Bus was late',
      'comment': 'The bus arrived after the scheduled time.',
      'created_at': '2026-08-27T10:30:00+08:00',
    });

    expect(record.feedbackId, 'feedback-1');
    expect(record.routeId, 'J15');
    expect(record.tripId, 'trip-1');
    expect(record.stopId, 'stop-1');
    expect(record.issueType, 'Bus was late');
    expect(record.comment, 'The bus arrived after the scheduled time.');
    expect(record.createdAt, DateTime.utc(2026, 8, 27, 2, 30));
  });

  test('passes route, issue type, and half-open time filters', () async {
    final source = FakeAdminFeedbackDataSource()
      ..records = [
        feedback(
          routeId: 'J15',
          issueType: '["Bus was late","Bus overcrowded"]',
        ),
        feedback(routeId: 'J10', issueType: 'Bus overcrowded'),
      ];
    final start = DateTime.utc(2026, 8, 1);
    final end = DateTime.utc(2026, 9, 1);

    final records = await DefaultAdminFeedbackRepository(dataSource: source)
        .loadFeedback(
          routeId: 'J15',
          issueType: 'Bus was late',
          startUtc: start,
          endExclusiveUtc: end,
        );

    expect(source.routeId, 'J15');
    expect(source.issueType, isNull);
    expect(source.startUtc, start);
    expect(source.endExclusiveUtc, end);
    expect(records.map((record) => record.feedbackId), ['feedback-J15']);
  });

  test('paginates network-wide feedback reads', () async {
    final source = FakeAdminFeedbackDataSource()..fullFirstPage = true;

    await DefaultAdminFeedbackRepository(dataSource: source).loadFeedback();

    expect(source.offsets, [0, 1000]);
  });

  test('converts source failures to a read exception', () {
    final source = FakeAdminFeedbackDataSource()..failure = true;

    expect(
      () => DefaultAdminFeedbackRepository(dataSource: source).loadFeedback(),
      throwsA(isA<AdminFeedbackReadException>()),
    );
  });

  test(
    'screening shares one period read and partitions exact routes',
    () async {
      final start = DateTime.utc(2026, 8, 1);
      final end = DateTime.utc(2026, 9, 1);
      final delegate = FakeAdminFeedbackRepository([
        feedback(routeId: 'A'),
        feedback(routeId: 'B', issueType: 'Bus overcrowded'),
        feedback(routeId: 'A', issueType: 'Bus overcrowded'),
      ]);
      final repository = ScreeningAdminFeedbackRepository(
        delegate: delegate,
        startUtc: start,
        endExclusiveUtc: end,
      );

      final results = await Future.wait([
        for (final routeId in ['A', 'B', 'C', 'D'])
          repository.loadFeedback(
            routeId: routeId,
            startUtc: start,
            endExclusiveUtc: end,
          ),
      ]);

      expect(delegate.calls, 1);
      expect(delegate.routeIds, [null]);
      expect(results[0].map((record) => record.routeId), ['A', 'A']);
      expect(results[1].map((record) => record.routeId), ['B']);
      expect(results[2], isEmpty);
      expect(results[3], isEmpty);
    },
  );

  test(
    'screening preserves issue filtering and starts fresh per context',
    () async {
      final start = DateTime.utc(2026, 8, 1);
      final end = DateTime.utc(2026, 9, 1);
      final delegate = FakeAdminFeedbackRepository([
        feedback(routeId: 'A', issueType: '["Bus was late","Bus overcrowded"]'),
        feedback(routeId: 'A', issueType: 'Bus overcrowded'),
      ]);

      for (var screening = 0; screening < 2; screening++) {
        final records =
            await ScreeningAdminFeedbackRepository(
              delegate: delegate,
              startUtc: start,
              endExclusiveUtc: end,
            ).loadFeedback(
              routeId: 'A',
              issueType: 'Bus was late',
              startUtc: start,
              endExclusiveUtc: end,
            );
        expect(records.map((record) => record.feedbackId), ['feedback-A']);
      }

      expect(delegate.calls, 2);
    },
  );
}

class FakeAdminFeedbackRepository implements AdminFeedbackRepository {
  FakeAdminFeedbackRepository(this.records);

  final List<AdminFeedbackRecord> records;
  int calls = 0;
  final routeIds = <String?>[];

  @override
  Future<List<AdminFeedbackRecord>> loadFeedback({
    String? routeId,
    String? issueType,
    DateTime? startUtc,
    DateTime? endExclusiveUtc,
  }) async {
    calls++;
    routeIds.add(routeId);
    await Future<void>.delayed(Duration.zero);
    return records;
  }
}

class FakeAdminFeedbackDataSource implements AdminFeedbackDataSource {
  List<AdminFeedbackRecord> records = [];
  bool fullFirstPage = false;
  bool failure = false;
  String? routeId;
  String? issueType;
  DateTime? startUtc;
  DateTime? endExclusiveUtc;
  final offsets = <int>[];

  @override
  Future<List<AdminFeedbackRecord>> fetchFeedback({
    required String? routeId,
    required String? issueType,
    required DateTime? startUtc,
    required DateTime? endExclusiveUtc,
    required int offset,
    required int limit,
  }) async {
    if (failure) throw Exception('failed');
    this.routeId = routeId;
    this.issueType = issueType;
    this.startUtc = startUtc;
    this.endExclusiveUtc = endExclusiveUtc;
    offsets.add(offset);
    if (fullFirstPage && offset == 0) {
      return List.filled(limit, feedback());
    }
    if (fullFirstPage) return const [];
    return offset == 0 ? records : const [];
  }
}

AdminFeedbackRecord feedback({
  String routeId = 'J15',
  String issueType = 'Bus was late',
}) {
  return AdminFeedbackRecord(
    feedbackId: 'feedback-$routeId',
    routeId: routeId,
    tripId: null,
    stopId: 'stop-1',
    issueType: issueType,
    comment: 'Feedback comment',
    createdAt: DateTime.utc(2026, 8, 27),
  );
}
