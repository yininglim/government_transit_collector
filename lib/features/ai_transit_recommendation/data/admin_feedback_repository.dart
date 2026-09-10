import 'package:government_transit_collector/features/bus_feedback/data/feedback_issue_types.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminFeedbackRecord {
  const AdminFeedbackRecord({
    required this.feedbackId,
    required this.routeId,
    required this.tripId,
    required this.stopId,
    required this.issueType,
    required this.comment,
    required this.createdAt,
  });

  factory AdminFeedbackRecord.fromMap(Map<String, dynamic> map) {
    return AdminFeedbackRecord(
      feedbackId: map['feedback_id'] as String,
      routeId: map['route_id'] as String,
      tripId: map['trip_id'] as String?,
      stopId: map['stop_id'] as String,
      issueType: map['issue_type'] as String,
      comment: map['comment'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }

  final String feedbackId;
  final String routeId;
  final String? tripId;
  final String stopId;
  final String issueType;
  List<String> get issueTypes => decodeFeedbackIssueTypes(issueType);
  final String comment;
  final DateTime createdAt;
}

abstract interface class AdminFeedbackDataSource {
  Future<List<AdminFeedbackRecord>> fetchFeedback({
    required String? routeId,
    required String? issueType,
    required DateTime? startUtc,
    required DateTime? endExclusiveUtc,
    required int offset,
    required int limit,
  });
}

abstract interface class AdminFeedbackRepository {
  Future<List<AdminFeedbackRecord>> loadFeedback({
    String? routeId,
    String? issueType,
    DateTime? startUtc,
    DateTime? endExclusiveUtc,
  });
}

class DefaultAdminFeedbackRepository implements AdminFeedbackRepository {
  DefaultAdminFeedbackRepository({AdminFeedbackDataSource? dataSource})
    : _dataSource = dataSource ?? SupabaseAdminFeedbackDataSource();

  static const pageSize = 1000;

  final AdminFeedbackDataSource _dataSource;

  @override
  Future<List<AdminFeedbackRecord>> loadFeedback({
    String? routeId,
    String? issueType,
    DateTime? startUtc,
    DateTime? endExclusiveUtc,
  }) async {
    try {
      final result = <AdminFeedbackRecord>[];
      for (var offset = 0; ; offset += pageSize) {
        final page = await _dataSource.fetchFeedback(
          routeId: routeId,
          issueType: null,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
          offset: offset,
          limit: pageSize,
        );
        result.addAll(
          page.where(
            (record) =>
                (routeId == null || record.routeId == routeId) &&
                (issueType == null || record.issueTypes.contains(issueType)) &&
                (startUtc == null || !record.createdAt.isBefore(startUtc)) &&
                (endExclusiveUtc == null ||
                    record.createdAt.isBefore(endExclusiveUtc)),
          ),
        );
        if (page.length < pageSize) break;
      }
      return result;
    } on AdminFeedbackReadException {
      rethrow;
    } on Object {
      throw const AdminFeedbackReadException(
        'Unable to load feedback for analysis.',
      );
    }
  }
}

class ScreeningAdminFeedbackRepository implements AdminFeedbackRepository {
  ScreeningAdminFeedbackRepository({
    required AdminFeedbackRepository delegate,
    required this.startUtc,
    required this.endExclusiveUtc,
  }) {
    _delegate = delegate;
  }

  late final AdminFeedbackRepository _delegate;
  final DateTime startUtc;
  final DateTime endExclusiveUtc;
  Future<_ScreeningFeedbackPeriod>? _feedbackFuture;

  @override
  Future<List<AdminFeedbackRecord>> loadFeedback({
    String? routeId,
    String? issueType,
    DateTime? startUtc,
    DateTime? endExclusiveUtc,
  }) async {
    if (startUtc != this.startUtc || endExclusiveUtc != this.endExclusiveUtc) {
      throw const AdminFeedbackReadException(
        'The screening period does not match the feedback context.',
      );
    }
    final period = await (_feedbackFuture ??= _loadPeriod());
    final records = routeId == null
        ? period.records
        : period.byRoute[routeId] ?? const <AdminFeedbackRecord>[];
    if (issueType == null) return records.toList(growable: false);
    return records
        .where((record) => record.issueTypes.contains(issueType))
        .toList(growable: false);
  }

  Future<_ScreeningFeedbackPeriod> _loadPeriod() async {
    final records = await _delegate.loadFeedback(
      startUtc: startUtc,
      endExclusiveUtc: endExclusiveUtc,
    );
    final grouped = <String, List<AdminFeedbackRecord>>{};
    for (final record in records) {
      grouped.putIfAbsent(record.routeId, () => []).add(record);
    }
    return _ScreeningFeedbackPeriod(records: records, byRoute: grouped);
  }
}

class _ScreeningFeedbackPeriod {
  const _ScreeningFeedbackPeriod({
    required this.records,
    required this.byRoute,
  });

  final List<AdminFeedbackRecord> records;
  final Map<String, List<AdminFeedbackRecord>> byRoute;
}

class SupabaseAdminFeedbackDataSource implements AdminFeedbackDataSource {
  SupabaseAdminFeedbackDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<AdminFeedbackRecord>> fetchFeedback({
    required String? routeId,
    required String? issueType,
    required DateTime? startUtc,
    required DateTime? endExclusiveUtc,
    required int offset,
    required int limit,
  }) async {
    try {
      var query = _client
          .from('bus_feedback')
          .select(
            'feedback_id, route_id, trip_id, stop_id, issue_type, comment, created_at',
          );
      if (routeId != null) query = query.eq('route_id', routeId);

      if (startUtc != null) {
        query = query.gte('created_at', startUtc.toUtc().toIso8601String());
      }
      if (endExclusiveUtc != null) {
        query = query.lt(
          'created_at',
          endExclusiveUtc.toUtc().toIso8601String(),
        );
      }
      final rows = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map(AdminFeedbackRecord.fromMap).toList(growable: false);
    } on Object {
      throw const AdminFeedbackReadException(
        'Unable to load feedback for analysis.',
      );
    }
  }
}

class AdminFeedbackReadException implements Exception {
  const AdminFeedbackReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
