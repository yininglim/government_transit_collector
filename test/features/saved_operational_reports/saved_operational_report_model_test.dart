import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report.dart';

void main() {
  test(
    'parses report JSON, enums, nullable route, and structured snapshot',
    () {
      final report = SavedOperationalReport.fromJson(sampleJson(routeId: null));

      expect(report.reportType, SavedOperationalReportType.peakOperation);
      expect(report.status, SavedOperationalReportStatus.needsAttention);
      expect(report.routeId, isNull);
      expect(report.resultSnapshot['busiest_route'], 'J30');
      expect(report.resultSnapshot['coverage'], isA<Map>());
      expect(report.createdAt, DateTime.utc(2026, 9, 10, 2));
    },
  );

  test('invalid enum values fail instead of mapping to a valid state', () {
    expect(
      () => SavedOperationalReport.fromJson({
        ...sampleJson(),
        'report_type': 'future_type',
      }),
      throwsFormatException,
    );
    expect(
      () => SavedOperationalReport.fromJson({
        ...sampleJson(),
        'status': 'unknown',
      }),
      throwsFormatException,
    );
  });

  test('snapshot must be a JSON object', () {
    expect(
      () => SavedOperationalReport.fromJson({
        ...sampleJson(),
        'result_snapshot': ['invalid'],
      }),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> sampleJson({String? routeId = 'route-1'}) => {
  'report_id': 'report-1',
  'admin_id': 'admin-1',
  'report_type': 'peak_operation',
  'route_id': routeId,
  'route_name_snapshot': routeId == null ? 'All Routes' : 'J30 — Johor Route',
  'period_start': '2026-09-01T00:00:00.000Z',
  'period_end': '2026-09-08T00:00:00.000Z',
  'title': 'Morning operations',
  'result_snapshot': {
    'busiest_route': 'J30',
    'coverage': {'observations': 42},
  },
  'admin_notes': 'Review next week',
  'status': 'needs_attention',
  'created_at': '2026-09-10T02:00:00.000Z',
  'updated_at': '2026-09-10T03:00:00.000Z',
};
