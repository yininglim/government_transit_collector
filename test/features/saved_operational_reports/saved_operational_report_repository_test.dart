import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report_repository.dart';

import 'saved_operational_report_model_test.dart';

void main() {
  test('loads and parses deterministically returned reports', () async {
    final source = FakeDataSource([sampleJson(), sampleJson(routeId: null)]);
    final repository = DefaultSavedOperationalReportRepository(
      dataSource: source,
    );

    final reports = await repository.loadReports();

    expect(reports, hasLength(2));
    expect(source.fetchCount, 1);
    expect(
      await repository.loadReport('report-1'),
      isA<SavedOperationalReport>(),
    );
  });

  test(
    'creates a draft Route Performance snapshot with normalized metadata',
    () async {
      final source = FakeDataSource([sampleJson()]);
      final repository = DefaultSavedOperationalReportRepository(
        dataSource: source,
      );

      final created = await repository.createRoutePerformanceReport(
        routeId: 'route-1',
        routeNameSnapshot: 'J30 — Johor Route',
        periodStart: DateTime.utc(2026, 9, 1),
        periodEnd: DateTime.utc(2026, 9, 8),
        title: '  Weekly performance  ',
        adminNotes: '   ',
        resultSnapshot: const {'trips_used_in_metrics': 4},
      );

      expect(source.insertedRouteId, 'route-1');
      expect(source.insertedRouteName, 'J30 — Johor Route');
      expect(source.insertedPeriodStart, '2026-09-01T00:00:00.000Z');
      expect(source.insertedPeriodEnd, '2026-09-08T00:00:00.000Z');
      expect(source.insertedTitle, 'Weekly performance');
      expect(source.insertedNotes, isNull);
      expect(source.insertedSnapshot, {'trips_used_in_metrics': 4});
      expect(created.reportType, SavedOperationalReportType.routePerformance);
      expect(created.status, SavedOperationalReportStatus.draft);
    },
  );

  test('creates a draft All Routes Peak Operation snapshot', () async {
    final source = FakeDataSource([sampleJson(routeId: null)]);
    final repository = DefaultSavedOperationalReportRepository(
      dataSource: source,
    );

    final created = await repository.createPeakOperationReport(
      routeId: null,
      routeNameSnapshot: 'All Routes',
      periodStart: DateTime.utc(2026, 9, 1),
      periodEnd: DateTime.utc(2026, 9, 8),
      title: '  Network peak  ',
      adminNotes: '   ',
      resultSnapshot: const {'total_observations': 12},
    );

    expect(source.insertedRouteId, isNull);
    expect(source.insertedRouteName, 'All Routes');
    expect(source.insertedTitle, 'Network peak');
    expect(source.insertedNotes, isNull);
    expect(source.insertedSnapshot, {'total_observations': 12});
    expect(created.reportType, SavedOperationalReportType.peakOperation);
    expect(created.status, SavedOperationalReportStatus.draft);
  });

  test('update sends only allowed management metadata', () async {
    final source = FakeDataSource([sampleJson()]);
    final repository = DefaultSavedOperationalReportRepository(
      dataSource: source,
    );

    final updated = await repository.updateManagementMetadata(
      reportId: 'report-1',
      title: '  Updated title  ',
      adminNotes: '  Updated notes  ',
      status: SavedOperationalReportStatus.reviewed,
    );

    expect(source.updatedReportId, 'report-1');
    expect(source.updatedTitle, 'Updated title');
    expect(source.updatedNotes, 'Updated notes');
    expect(source.updatedStatus, 'reviewed');
    expect(updated.title, 'Updated title');
    expect(updated.resultSnapshot, sampleJson()['result_snapshot']);
  });

  test('rejects a blank title without calling the data source', () async {
    final source = FakeDataSource([sampleJson()]);
    final repository = DefaultSavedOperationalReportRepository(
      dataSource: source,
    );

    await expectLater(
      repository.updateManagementMetadata(
        reportId: 'report-1',
        title: '   ',
        adminNotes: null,
        status: SavedOperationalReportStatus.draft,
      ),
      throwsA(isA<SavedOperationalReportException>()),
    );
    expect(source.updatedReportId, isNull);
  });

  test('deletes only the requested report ID', () async {
    final source = FakeDataSource([sampleJson()]);
    final repository = DefaultSavedOperationalReportRepository(
      dataSource: source,
    );

    await repository.deleteReport('report-1');

    expect(source.deletedReportId, 'report-1');
  });
}

class FakeDataSource implements SavedOperationalReportDataSource {
  FakeDataSource(this.rows);
  final List<Map<String, dynamic>> rows;
  int fetchCount = 0;
  String? updatedReportId;
  String? updatedTitle;
  String? updatedNotes;
  String? updatedStatus;
  String? deletedReportId;
  String? insertedRouteId;
  String? insertedRouteName;
  String? insertedPeriodStart;
  String? insertedPeriodEnd;
  String? insertedTitle;
  String? insertedNotes;
  Map<String, dynamic>? insertedSnapshot;

  @override
  Future<Map<String, dynamic>> insertRoutePerformanceReport({
    required String routeId,
    required String routeNameSnapshot,
    required String periodStart,
    required String periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  }) async {
    insertedRouteId = routeId;
    insertedRouteName = routeNameSnapshot;
    insertedPeriodStart = periodStart;
    insertedPeriodEnd = periodEnd;
    insertedTitle = title;
    insertedNotes = adminNotes;
    insertedSnapshot = resultSnapshot;
    return {
      ...rows.first,
      'report_type': 'route_performance',
      'route_id': routeId,
      'route_name_snapshot': routeNameSnapshot,
      'period_start': periodStart,
      'period_end': periodEnd,
      'title': title,
      'admin_notes': adminNotes,
      'result_snapshot': resultSnapshot,
      'status': 'draft',
    };
  }

  @override
  Future<Map<String, dynamic>> insertPeakOperationReport({
    required String? routeId,
    required String routeNameSnapshot,
    required String periodStart,
    required String periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  }) async {
    insertedRouteId = routeId;
    insertedRouteName = routeNameSnapshot;
    insertedPeriodStart = periodStart;
    insertedPeriodEnd = periodEnd;
    insertedTitle = title;
    insertedNotes = adminNotes;
    insertedSnapshot = resultSnapshot;
    return {
      ...rows.first,
      'report_type': 'peak_operation',
      'route_id': routeId,
      'route_name_snapshot': routeNameSnapshot,
      'period_start': periodStart,
      'period_end': periodEnd,
      'title': title,
      'admin_notes': adminNotes,
      'result_snapshot': resultSnapshot,
      'status': 'draft',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchReports() async {
    fetchCount++;
    return rows;
  }

  @override
  Future<Map<String, dynamic>> fetchReport(String reportId) async => rows.first;

  @override
  Future<Map<String, dynamic>> updateManagementMetadata({
    required String reportId,
    required String title,
    required String? adminNotes,
    required String status,
  }) async {
    updatedReportId = reportId;
    updatedTitle = title;
    updatedNotes = adminNotes;
    updatedStatus = status;
    return {
      ...rows.first,
      'title': title,
      'admin_notes': adminNotes,
      'status': status,
      'updated_at': '2026-09-10T04:00:00.000Z',
    };
  }

  @override
  Future<void> deleteReport(String reportId) async {
    deletedReportId = reportId;
  }
}
