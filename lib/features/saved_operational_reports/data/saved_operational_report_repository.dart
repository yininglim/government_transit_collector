import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SavedOperationalReportRepository {
  Future<SavedOperationalReport> createRoutePerformanceReport({
    required String routeId,
    required String routeNameSnapshot,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  });
  Future<SavedOperationalReport> createPeakOperationReport({
    required String? routeId,
    required String routeNameSnapshot,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  });
  Future<List<SavedOperationalReport>> loadReports();
  Future<SavedOperationalReport> loadReport(String reportId);
  Future<SavedOperationalReport> updateManagementMetadata({
    required String reportId,
    required String title,
    required String? adminNotes,
    required SavedOperationalReportStatus status,
  });
  Future<void> deleteReport(String reportId);
}

abstract interface class SavedOperationalReportDataSource {
  Future<Map<String, dynamic>> insertRoutePerformanceReport({
    required String routeId,
    required String routeNameSnapshot,
    required String periodStart,
    required String periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  });
  Future<Map<String, dynamic>> insertPeakOperationReport({
    required String? routeId,
    required String routeNameSnapshot,
    required String periodStart,
    required String periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  });
  Future<List<Map<String, dynamic>>> fetchReports();
  Future<Map<String, dynamic>> fetchReport(String reportId);
  Future<Map<String, dynamic>> updateManagementMetadata({
    required String reportId,
    required String title,
    required String? adminNotes,
    required String status,
  });
  Future<void> deleteReport(String reportId);
}

class DefaultSavedOperationalReportRepository
    implements SavedOperationalReportRepository {
  DefaultSavedOperationalReportRepository({
    SavedOperationalReportDataSource? dataSource,
  }) : _dataSource = dataSource ?? SupabaseSavedOperationalReportDataSource();

  final SavedOperationalReportDataSource _dataSource;

  @override
  Future<SavedOperationalReport> createRoutePerformanceReport({
    required String routeId,
    required String routeNameSnapshot,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw const SavedOperationalReportException('Title cannot be blank.');
    }
    final trimmedNotes = adminNotes?.trim();
    try {
      return SavedOperationalReport.fromJson(
        await _dataSource.insertRoutePerformanceReport(
          routeId: routeId,
          routeNameSnapshot: routeNameSnapshot,
          periodStart: periodStart.toUtc().toIso8601String(),
          periodEnd: periodEnd.toUtc().toIso8601String(),
          title: trimmedTitle,
          adminNotes: trimmedNotes?.isEmpty == true ? null : trimmedNotes,
          resultSnapshot: Map<String, dynamic>.from(resultSnapshot),
        ),
      );
    } on SavedOperationalReportException {
      rethrow;
    } on Object {
      throw const SavedOperationalReportException(
        'Unable to save this Route Performance report.',
      );
    }
  }

  @override
  Future<SavedOperationalReport> createPeakOperationReport({
    required String? routeId,
    required String routeNameSnapshot,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw const SavedOperationalReportException('Title cannot be blank.');
    }
    final trimmedNotes = adminNotes?.trim();
    try {
      return SavedOperationalReport.fromJson(
        await _dataSource.insertPeakOperationReport(
          routeId: routeId,
          routeNameSnapshot: routeNameSnapshot,
          periodStart: periodStart.toUtc().toIso8601String(),
          periodEnd: periodEnd.toUtc().toIso8601String(),
          title: trimmedTitle,
          adminNotes: trimmedNotes?.isEmpty == true ? null : trimmedNotes,
          resultSnapshot: Map<String, dynamic>.from(resultSnapshot),
        ),
      );
    } on SavedOperationalReportException {
      rethrow;
    } on Object {
      throw const SavedOperationalReportException(
        'Unable to save this Peak Operation report.',
      );
    }
  }

  @override
  Future<List<SavedOperationalReport>> loadReports() async {
    try {
      return (await _dataSource.fetchReports())
          .map(SavedOperationalReport.fromJson)
          .toList(growable: false);
    } on SavedOperationalReportException {
      rethrow;
    } on Object {
      throw const SavedOperationalReportException(
        'Unable to load saved operational reports.',
      );
    }
  }

  @override
  Future<SavedOperationalReport> loadReport(String reportId) async {
    try {
      return SavedOperationalReport.fromJson(
        await _dataSource.fetchReport(reportId),
      );
    } on SavedOperationalReportException {
      rethrow;
    } on Object {
      throw const SavedOperationalReportException(
        'Unable to load this saved report.',
      );
    }
  }

  @override
  Future<SavedOperationalReport> updateManagementMetadata({
    required String reportId,
    required String title,
    required String? adminNotes,
    required SavedOperationalReportStatus status,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw const SavedOperationalReportException('Title cannot be blank.');
    }
    final trimmedNotes = adminNotes?.trim();
    try {
      return SavedOperationalReport.fromJson(
        await _dataSource.updateManagementMetadata(
          reportId: reportId,
          title: trimmedTitle,
          adminNotes: trimmedNotes?.isEmpty == true ? null : trimmedNotes,
          status: status.databaseValue,
        ),
      );
    } on SavedOperationalReportException {
      rethrow;
    } on Object {
      throw const SavedOperationalReportException(
        'Unable to update this saved report.',
      );
    }
  }

  @override
  Future<void> deleteReport(String reportId) async {
    try {
      await _dataSource.deleteReport(reportId);
    } on SavedOperationalReportException {
      rethrow;
    } on Object {
      throw const SavedOperationalReportException(
        'Unable to delete this saved report.',
      );
    }
  }
}

class SupabaseSavedOperationalReportDataSource
    implements SavedOperationalReportDataSource {
  SupabaseSavedOperationalReportDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const table = 'saved_operational_reports';
  final SupabaseClient _client;

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
    final adminId = _client.auth.currentUser?.id;
    if (adminId == null) {
      throw const SavedOperationalReportException(
        'Please sign in as an administrator to save this report.',
      );
    }
    return Map<String, dynamic>.from(
      await _client
          .from(table)
          .insert({
            'admin_id': adminId,
            'report_type':
                SavedOperationalReportType.routePerformance.databaseValue,
            'route_id': routeId,
            'route_name_snapshot': routeNameSnapshot,
            'period_start': periodStart,
            'period_end': periodEnd,
            'title': title,
            'result_snapshot': resultSnapshot,
            'admin_notes': adminNotes,
            'status': SavedOperationalReportStatus.draft.databaseValue,
          })
          .select()
          .single(),
    );
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
    final adminId = _client.auth.currentUser?.id;
    if (adminId == null) {
      throw const SavedOperationalReportException(
        'Please sign in as an administrator to save this report.',
      );
    }
    return Map<String, dynamic>.from(
      await _client
          .from(table)
          .insert({
            'admin_id': adminId,
            'report_type':
                SavedOperationalReportType.peakOperation.databaseValue,
            'route_id': routeId,
            'route_name_snapshot': routeNameSnapshot,
            'period_start': periodStart,
            'period_end': periodEnd,
            'title': title,
            'result_snapshot': resultSnapshot,
            'admin_notes': adminNotes,
            'status': SavedOperationalReportStatus.draft.databaseValue,
          })
          .select()
          .single(),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchReports() async {
    final rows = await _client
        .from(table)
        .select()
        .order('created_at', ascending: false)
        .order('report_id');
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> fetchReport(String reportId) async =>
      Map<String, dynamic>.from(
        await _client.from(table).select().eq('report_id', reportId).single(),
      );

  @override
  Future<Map<String, dynamic>> updateManagementMetadata({
    required String reportId,
    required String title,
    required String? adminNotes,
    required String status,
  }) async => Map<String, dynamic>.from(
    await _client
        .from(table)
        .update({'title': title, 'admin_notes': adminNotes, 'status': status})
        .eq('report_id', reportId)
        .select()
        .single(),
  );

  @override
  Future<void> deleteReport(String reportId) async {
    await _client.from(table).delete().eq('report_id', reportId);
  }
}

class SavedOperationalReportException implements Exception {
  const SavedOperationalReportException(this.message);
  final String message;

  @override
  String toString() => message;
}
