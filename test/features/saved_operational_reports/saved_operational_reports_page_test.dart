import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/admin_home/presentation/admin_home_page.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report_repository.dart';
import 'package:government_transit_collector/features/saved_operational_reports/presentation/saved_operational_report_detail_page.dart';
import 'package:government_transit_collector/features/saved_operational_reports/presentation/saved_operational_reports_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'saved_operational_report_model_test.dart';

void main() {
  testWidgets('admin home opens Saved Operational Reports', (tester) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomePage(
          profile: const AppProfile(
            userId: 'admin',
            fullName: 'Admin',
            role: 'admin',
            email: 'admin@example.com',
          ),
          repository: AuthRepository(client: client),
          savedOperationalReportRepository: FakeRepository(const []),
        ),
      ),
    );
    await tester.tap(find.text('Saved Operational Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Historical analysis snapshots'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
  });

  testWidgets('shows explanatory empty state without an add action', (
    tester,
  ) async {
    await pumpPage(tester, FakeRepository(const []));
    expect(find.text('No saved operational reports'), findsOneWidget);
    expect(find.textContaining('after an admin saves'), findsOneWidget);
    expect(find.textContaining('Add Report'), findsNothing);
  });

  testWidgets('renders report labels, route scopes, dates, and filtering', (
    tester,
  ) async {
    await pumpPage(tester, FakeRepository(reports()));
    expect(find.text('Route Performance'), findsWidgets);
    expect(find.text('Peak Operation'), findsWidgets);
    expect(find.text('All Routes'), findsOneWidget);
    expect(find.text('Needs Attention'), findsWidgets);

    await tester.tap(find.byKey(const Key('report-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Route Performance').last);
    await tester.pumpAndSettle();
    expect(find.text('Network peak report'), findsNothing);
    expect(find.text('Route travel report'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reviewed').last);
    await tester.pumpAndSettle();
    expect(find.text('Route travel report'), findsOneWidget);
  });

  testWidgets('detail presents source and generic structured snapshot', (
    tester,
  ) async {
    await pumpPage(tester, FakeRepository(reports()));
    await tester.tap(find.text('Network peak report'));
    await tester.pumpAndSettle();
    expect(find.text('admin-1'), findsNothing);
    final snapshotHeading = find.descendant(
      of: find.byType(SavedOperationalReportDetailPage),
      matching: find.text('Result snapshot'),
    );
    final detailList = find
        .descendant(
          of: find.descendant(
            of: find.byType(SavedOperationalReportDetailPage),
            matching: find.byType(ListView),
          ),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Report source'),
      200,
      scrollable: detailList,
    );
    expect(find.text('Report source'), findsOneWidget);
    expect(find.text('All Routes'), findsOneWidget);
    expect(find.textContaining('1 Sep 2026, 12:00 AM'), findsOneWidget);
    await tester.scrollUntilVisible(
      snapshotHeading,
      300,
      scrollable: detailList,
    );
    expect(find.text('Busiest Route'), findsOneWidget);
    expect(find.text('J30'), findsOneWidget);
    expect(find.text('3:30 PM – 4:00 PM'), findsOneWidget);
    expect(find.text('54.8'), findsOneWidget);
    expect(find.text('Custom Signal'), findsOneWidget);
    expect(find.text('Administrator note'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing);
  });

  testWidgets('route snapshot promotes and formats operational metrics', (
    tester,
  ) async {
    await pumpPage(tester, FakeRepository(reports()));
    await tester.tap(find.text('Route travel report'));
    await tester.pumpAndSettle();
    final snapshotHeading = find.descendant(
      of: find.byType(SavedOperationalReportDetailPage),
      matching: find.text('Result snapshot'),
    );
    final detailList = find
        .descendant(
          of: find.descendant(
            of: find.byType(SavedOperationalReportDetailPage),
            matching: find.byType(ListView),
          ),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      snapshotHeading,
      300,
      scrollable: detailList,
    );

    expect(find.text('Average Travel Time'), findsOneWidget);
    expect(find.text('54.8 min'), findsOneWidget);
    expect(find.text('84.5%'), findsOneWidget);
    expect(find.text('62.4%'), findsOneWidget);
    expect(find.text('2,288'), findsOneWidget);
    expect(find.text('Trip coverage and supporting details'), findsOneWidget);
  });

  testWidgets('detail opens in read-only management view', (tester) async {
    await pumpPage(tester, FakeRepository(reports()));
    await tester.tap(find.text('Network peak report'));
    await tester.pumpAndSettle();

    expect(find.text('Network peak report'), findsOneWidget);
    expect(find.text('Needs Attention'), findsOneWidget);
    expect(find.text('Review next week'), findsOneWidget);
    expect(find.byKey(const Key('edit-report-metadata')), findsOneWidget);
    expect(find.byKey(const Key('report-title-field')), findsNothing);
    expect(find.byKey(const Key('report-status-field')), findsNothing);
    expect(find.byKey(const Key('report-notes-field')), findsNothing);
    expect(find.byKey(const Key('save-report-metadata')), findsNothing);
  });

  testWidgets('edits title, notes, and status and validates blank title', (
    tester,
  ) async {
    final repository = FakeRepository(reports());
    await pumpPage(tester, repository);
    await tester.tap(find.text('Network peak report'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-report-metadata')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('report-title-field')))
          .controller!
          .text,
      'Network peak report',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('report-notes-field')))
          .controller!
          .text,
      'Review next week',
    );

    await tester.enterText(find.byKey(const Key('report-title-field')), '   ');
    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.drag(
      find.descendant(
        of: find.byType(SavedOperationalReportDetailPage),
        matching: find.byType(ListView),
      ),
      const Offset(0, -320),
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save-report-metadata')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Save changes').hitTestable());
    await tester.pump();
    expect(find.text('Title cannot be blank.'), findsOneWidget);
    expect(repository.updateCount, 0);

    await tester.enterText(
      find.byKey(const Key('report-title-field')),
      'Reviewed network peak',
    );
    await tester.enterText(
      find.byKey(const Key('report-notes-field')),
      'Approved for planning',
    );
    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('report-status-field'))),
      alignment: 0.5,
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('report-status-field')).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reviewed').last);
    await tester.pumpAndSettle();
    await tester.drag(
      find.descendant(
        of: find.byType(SavedOperationalReportDetailPage),
        matching: find.byType(ListView),
      ),
      const Offset(0, -320),
    );
    await tester.pump();
    await tester.tap(find.text('Save changes').hitTestable());
    await tester.pumpAndSettle();

    expect(repository.updateCount, 1);
    expect(repository.lastTitle, 'Reviewed network peak');
    expect(repository.lastNotes, 'Approved for planning');
    expect(repository.lastStatus, SavedOperationalReportStatus.reviewed);
    expect(find.text('Report updated successfully.'), findsOneWidget);
    expect(find.text('Reviewed network peak'), findsOneWidget);
    expect(find.text('Approved for planning'), findsOneWidget);
    expect(find.byKey(const Key('report-title-field')), findsNothing);
    expect(find.byKey(const Key('save-report-metadata')), findsNothing);
  });

  testWidgets('Cancel discards edits without updating the repository', (
    tester,
  ) async {
    final repository = FakeRepository(reports());
    await pumpPage(tester, repository);
    await tester.tap(find.text('Network peak report'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-report-metadata')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('report-title-field')),
      'Unsaved title',
    );
    await tester.enterText(
      find.byKey(const Key('report-notes-field')),
      'Unsaved notes',
    );
    await tester.ensureVisible(find.byKey(const Key('cancel-report-metadata')));
    await tester.tap(find.byKey(const Key('cancel-report-metadata')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.descendant(
        of: find.byType(SavedOperationalReportDetailPage),
        matching: find.byType(ListView),
      ),
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();

    expect(repository.updateCount, 0);
    expect(find.text('Network peak report'), findsOneWidget);
    expect(find.text('Review next week'), findsOneWidget);
    expect(find.text('Unsaved title'), findsNothing);
    expect(find.text('Unsaved notes'), findsNothing);
    expect(find.byKey(const Key('report-title-field')), findsNothing);
  });

  testWidgets('read-only view describes empty admin notes', (tester) async {
    final report = SavedOperationalReport.fromJson({
      ...sampleJson(routeId: null),
      'report_id': 'empty-notes',
      'title': 'No notes report',
      'admin_notes': null,
    });
    await pumpPage(tester, FakeRepository([report]));
    await tester.tap(find.text('No notes report'));
    await tester.pumpAndSettle();

    expect(find.text('No admin notes.'), findsOneWidget);
  });

  testWidgets('confirms deletion and removes report from the list', (
    tester,
  ) async {
    final repository = FakeRepository([reports().first]);
    await pumpPage(tester, repository);
    await tester.tap(find.text('Network peak report'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete report'));
    await tester.pumpAndSettle();
    expect(find.text('Delete saved report?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.deletedId, 'peak');
    expect(find.text('No saved operational reports'), findsOneWidget);
  });

  testWidgets('load and delete failures preserve a recoverable UI', (
    tester,
  ) async {
    await pumpPage(tester, FakeRepository(const [], loadFailure: true));
    expect(find.text('Unable to load reports for test.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    final repository = FakeRepository([reports().first], deleteFailure: true);
    await pumpPage(tester, repository);
    await tester.tap(find.text('Network peak report'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete report'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Unable to delete report for test.'),
      findsOneWidget,
    );
    expect(find.text('Operational Report'), findsOneWidget);
  });

  testWidgets('narrow portrait and landscape layouts do not overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 700);
    await pumpPage(tester, FakeRepository(reports()));
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(700, 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Network peak report'));
    await tester.pumpAndSettle();
    expect(find.text('Management details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> pumpPage(
  WidgetTester tester,
  SavedOperationalReportRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SavedOperationalReportsPage(
        key: UniqueKey(),
        repository: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<SavedOperationalReport> reports() => [
  SavedOperationalReport.fromJson({
    ...sampleJson(routeId: null),
    'report_id': 'peak',
    'title': 'Network peak report',
    'result_snapshot': {
      'peak_period': '3:30 PM – 4:00 PM',
      'peak_average_active_trips': 54.7833333333333,
      'peak_activity_level': 'high',
      'average_activity': 31.25,
      'activity_difference_percent': 75.306,
      'total_observations': 2288,
      'distinct_trip_occurrences': 412,
      'observed_day_count': 7,
      'routes_represented': 21,
      'busiest_route_name': 'J30',
      'custom_signal': 'Administrator note',
    },
  }),
  SavedOperationalReport.fromJson({
    ...sampleJson(),
    'report_id': 'route',
    'report_type': 'route_performance',
    'title': 'Route travel report',
    'status': 'reviewed',
    'result_snapshot': {
      'average_travel_time_minutes': 54.7833333333333,
      'delay_frequency_percent': 84.5360824742268,
      'schedule_adherence_percent': 62.4299938320557,
      'trips_used_in_metrics': 2288,
      'delayed_trip_count': 1934,
      'on_time_trip_count': 354,
      'partial_trip_occurrences': 18,
      'total_observed_trip_occurrences': 2306,
      'total_observations': 44000,
    },
  }),
];

class FakeRepository implements SavedOperationalReportRepository {
  FakeRepository(
    List<SavedOperationalReport> reports, {
    this.loadFailure = false,
    this.deleteFailure = false,
  }) : _reports = List.of(reports);

  List<SavedOperationalReport> _reports;
  final bool loadFailure;
  final bool deleteFailure;
  int updateCount = 0;
  String? lastTitle;
  String? lastNotes;
  SavedOperationalReportStatus? lastStatus;
  String? deletedId;

  @override
  Future<SavedOperationalReport> createRoutePerformanceReport({
    required String routeId,
    required String routeNameSnapshot,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  }) => throw UnimplementedError();

  @override
  Future<SavedOperationalReport> createPeakOperationReport({
    required String? routeId,
    required String routeNameSnapshot,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  }) => throw UnimplementedError();

  @override
  Future<List<SavedOperationalReport>> loadReports() async {
    if (loadFailure) {
      throw const SavedOperationalReportException(
        'Unable to load reports for test.',
      );
    }
    return List.of(_reports);
  }

  @override
  Future<SavedOperationalReport> loadReport(String reportId) async =>
      _reports.firstWhere((report) => report.reportId == reportId);

  @override
  Future<SavedOperationalReport> updateManagementMetadata({
    required String reportId,
    required String title,
    required String? adminNotes,
    required SavedOperationalReportStatus status,
  }) async {
    updateCount++;
    lastTitle = title;
    lastNotes = adminNotes;
    lastStatus = status;
    final old = await loadReport(reportId);
    final updated = SavedOperationalReport(
      reportId: old.reportId,
      adminId: old.adminId,
      reportType: old.reportType,
      routeId: old.routeId,
      routeNameSnapshot: old.routeNameSnapshot,
      periodStart: old.periodStart,
      periodEnd: old.periodEnd,
      title: title,
      resultSnapshot: old.resultSnapshot,
      adminNotes: adminNotes,
      status: status,
      createdAt: old.createdAt,
      updatedAt: old.updatedAt.add(const Duration(minutes: 1)),
    );
    _reports = _reports
        .map((report) => report.reportId == reportId ? updated : report)
        .toList(growable: false);
    return updated;
  }

  @override
  Future<void> deleteReport(String reportId) async {
    if (deleteFailure) {
      throw const SavedOperationalReportException(
        'Unable to delete report for test.',
      );
    }
    deletedId = reportId;
    _reports = _reports
        .where((report) => report.reportId != reportId)
        .toList(growable: false);
  }
}
