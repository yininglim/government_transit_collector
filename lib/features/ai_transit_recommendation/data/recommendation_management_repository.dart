import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_priority.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class RecommendationManagementRepository {
  Future<SavedRecommendation> saveBusFrequencyRecommendation({
    required BusFrequencyRouteRecommendationRecord recommendation,
    required String routeDisplayLabel,
    required DateTime periodStart,
    required DateTime periodEnd,
    required BusFrequencyEvidence evidence,
  });

  Future<SavedRecommendation> saveRouteBusStopRecommendation({
    required RouteStopRecommendationRecord recommendation,
    required String routeDisplayLabel,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DistrictRouteStopEvidence evidence,
  });

  Future<List<SavedRecommendation>> loadSavedRecommendations();

  Future<SavedRecommendation> updateRecommendation({
    required SavedRecommendation recommendation,
    required RecommendationReviewStatus status,
    required String? adminNote,
  });

  Future<SavedRecommendation> createFollowUp({
    required SavedRecommendation recommendation,
    required String actionText,
    required DateTime dueDate,
    required String? note,
  });

  Future<SavedRecommendation> updateFollowUp({
    required SavedRecommendation recommendation,
    required String actionText,
    required DateTime dueDate,
    required RecommendationFollowUpStatus status,
    required String? note,
  });

  Future<void> deleteRecommendation(String recommendationId);
}

abstract interface class RecommendationManagementDataSource {
  Future<Map<String, dynamic>> insertRecommendation({
    required Map<String, dynamic> analysisReport,
    required Map<String, dynamic> recommendation,
  });

  Future<List<Map<String, dynamic>>> fetchRecommendations();

  Future<Map<String, dynamic>> updateRecommendation({
    required String recommendationId,
    required String status,
    required String? adminNote,
  });

  Future<Map<String, dynamic>> insertFollowUp({
    required String recommendationId,
    required String actionText,
    required String dueDate,
    required String? note,
  });

  Future<Map<String, dynamic>> updateFollowUp({
    required String followUpId,
    required String actionText,
    required String dueDate,
    required String status,
    required String? note,
    required String? completedAt,
  });

  Future<void> deleteRecommendation(String recommendationId);
}

class DefaultRecommendationManagementRepository
    implements RecommendationManagementRepository {
  DefaultRecommendationManagementRepository({
    RecommendationManagementDataSource? dataSource,
    DateTime Function()? now,
  }) : _dataSource = dataSource ?? SupabaseRecommendationManagementDataSource(),
       _now = now ?? DateTime.now;

  final RecommendationManagementDataSource _dataSource;
  final DateTime Function() _now;

  @override
  Future<SavedRecommendation> saveBusFrequencyRecommendation({
    required BusFrequencyRouteRecommendationRecord recommendation,
    required String routeDisplayLabel,
    required DateTime periodStart,
    required DateTime periodEnd,
    required BusFrequencyEvidence evidence,
  }) async {
    if (recommendation.action ==
        BusFrequencyRecommendationAction.insufficientEvidence) {
      throw const RecommendationManagementException(
        'Only actionable recommendations can be saved.',
      );
    }
    final action = recommendation.action.name;
    final priority = RecommendationPriorityCalculator.busFrequency(
      action: recommendation.action,
      evidence: evidence,
    );
    final snapshot = {
      'management_schema_version': 1,
      'management_source': 'ai_transit_recommendation',
      'feature_type': 'bus_frequency',
      'route_id': recommendation.routeId,
      'route_display_label': routeDisplayLabel,
      'action': action,
      'evidence_refs': recommendation.evidenceRefs,
      'limitations': recommendation.limitations,
      'analysis_period_start': periodStart.toUtc().toIso8601String(),
      'analysis_period_end': periodEnd.toUtc().toIso8601String(),
      'priority_rule_version': 1,
      'priority_level': priority.level.snapshotValue,
      'priority_reasons': priority.reasons,
    };
    return _save(
      analysisType: 'route_performance',
      recommendationType: 'bus_frequency',
      routeId: recommendation.routeId,
      title: '${_busFrequencyTitle(recommendation.action)} — $routeDisplayLabel',
      rationale: recommendation.conciseRationale,
      periodStart: periodStart,
      periodEnd: periodEnd,
      snapshot: snapshot,
      priority: priority.level.databaseValue,
    );
  }

  @override
  Future<SavedRecommendation> saveRouteBusStopRecommendation({
    required RouteStopRecommendationRecord recommendation,
    required String routeDisplayLabel,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DistrictRouteStopEvidence evidence,
  }) async {
    final actionable = recommendation.actions
        .where((action) => action != RouteStopRecommendationAction.insufficientEvidence)
        .toList(growable: false);
    if (actionable.isEmpty) {
      throw const RecommendationManagementException(
        'Only actionable recommendations can be saved.',
      );
    }
    final candidateArea = recommendation.candidateArea;
    final priority = RecommendationPriorityCalculator.routeBusStop(
      actions: actionable,
      evidence: evidence,
    );
    final snapshot = {
      'management_schema_version': 1,
      'management_source': 'ai_transit_recommendation',
      'feature_type': 'route_bus_stop',
      'route_id': recommendation.routeId,
      'route_display_label': routeDisplayLabel,
      'actions': actionable.map((action) => action.name).toList(),
      'evidence_refs': recommendation.routeOwnedEvidenceRefs,
      'limitations': recommendation.limitations,
      'target_stop_ids': recommendation.targetStopIds,
      if (candidateArea != null)
        'candidate_area': {
          'route_id': candidateArea.routeId,
          'from_stop_id': candidateArea.fromStopId,
          'from_stop_name': candidateArea.fromStopName,
          'to_stop_id': candidateArea.toStopId,
          'to_stop_name': candidateArea.toStopName,
          'area_description': candidateArea.areaDescription,
        },
      'analysis_period_start': periodStart.toUtc().toIso8601String(),
      'analysis_period_end': periodEnd.toUtc().toIso8601String(),
      'priority_rule_version': 1,
      'priority_level': priority.level.snapshotValue,
      'priority_reasons': priority.reasons,
    };
    final routeImprovement = actionable.contains(
      RouteStopRecommendationAction.routeImprovement,
    );
    return _save(
      analysisType: 'stop_suitability',
      recommendationType: routeImprovement ||
              actionable.every(
                (action) =>
                    action == RouteStopRecommendationAction.maintainCurrentConfiguration,
              )
          ? 'route_improvement'
          : 'stop_suitability',
      routeId: recommendation.routeId,
      title: 'Route & stop recommendation — $routeDisplayLabel',
      rationale: recommendation.conciseRationale,
      periodStart: periodStart,
      periodEnd: periodEnd,
      snapshot: snapshot,
      priority: priority.level.databaseValue,
    );
  }

  Future<SavedRecommendation> _save({
    required String analysisType,
    required String recommendationType,
    required String routeId,
    required String title,
    required String rationale,
    required DateTime periodStart,
    required DateTime periodEnd,
    required Map<String, dynamic> snapshot,
    required int priority,
  }) async {
    final completedAt = DateTime.now().toUtc().toIso8601String();
    try {
      return SavedRecommendation.fromJson(
        await _dataSource.insertRecommendation(
          analysisReport: {
            'analysis_type': analysisType,
            'title': title,
            'route_id': routeId,
            'period_start': periodStart.toUtc().toIso8601String(),
            'period_end': periodEnd.toUtc().toIso8601String(),
            'status': 'completed',
            'input_parameters': {
              'management_source': 'ai_transit_recommendation',
            },
            'summary_metrics': snapshot,
            'summary_text': rationale,
            'method_or_model': 'Validated AI transit recommendation',
            'completed_at': completedAt,
          },
          recommendation: {
            'recommendation_type': recommendationType,
            'route_id': routeId,
            'stop_id': null,
            'title': title,
            'description': rationale,
            'priority': priority,
            'supporting_metrics': snapshot,
            'estimated_cost': null,
            'currency': null,
            'status': RecommendationReviewStatus.pending.databaseValue,
          },
        ),
      );
    } on RecommendationManagementException {
      rethrow;
    } on Object {
      throw const RecommendationManagementException(
        'Unable to save this recommendation.',
      );
    }
  }

  @override
  Future<List<SavedRecommendation>> loadSavedRecommendations() async {
    try {
      final records = <SavedRecommendation>[];
      for (final row in await _dataSource.fetchRecommendations()) {
        try {
          records.add(SavedRecommendation.fromJson(row));
        } on FormatException {
          continue;
        }
      }
      records.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return records;
    } on RecommendationManagementException {
      rethrow;
    } on Object {
      throw const RecommendationManagementException(
        'Unable to load saved recommendations.',
      );
    }
  }

  @override
  Future<SavedRecommendation> updateRecommendation({
    required SavedRecommendation recommendation,
    required RecommendationReviewStatus status,
    required String? adminNote,
  }) async {
    if (recommendation.status != RecommendationReviewStatus.pending &&
        status != recommendation.status) {
      throw const RecommendationManagementException(
        'This recommendation decision is final and cannot be changed.',
      );
    }
    final note = adminNote?.trim();
    try {
      final updated = SavedRecommendation.fromJson(
        await _dataSource.updateRecommendation(
          recommendationId: recommendation.recommendationId,
          status: status.databaseValue,
          adminNote: note == null || note.isEmpty ? null : note,
        ),
      );
      return updated.copyWith(followUp: recommendation.followUp);
    } on RecommendationManagementException {
      rethrow;
    } on Object {
      throw const RecommendationManagementException(
        'Unable to update this recommendation.',
      );
    }
  }

  @override
  Future<SavedRecommendation> createFollowUp({
    required SavedRecommendation recommendation,
    required String actionText,
    required DateTime dueDate,
    required String? note,
  }) async {
    if (recommendation.status != RecommendationReviewStatus.accepted) {
      throw const RecommendationManagementException(
        'Only accepted recommendations can have a follow-up action.',
      );
    }
    if (recommendation.followUp != null) {
      throw const RecommendationManagementException(
        'This recommendation already has a follow-up action.',
      );
    }
    final task = _requiredFollowUpAction(actionText);
    final date = _dateOnly(dueDate);
    if (date.isBefore(_dateOnly(_now()))) {
      throw const RecommendationManagementException(
        'Due date cannot be earlier than today.',
      );
    }
    try {
      final followUp = RecommendationFollowUp.fromJson(
        await _dataSource.insertFollowUp(
          recommendationId: recommendation.recommendationId,
          actionText: task,
          dueDate: _databaseDate(date),
          note: _nullableTrimmed(note),
        ),
      );
      return recommendation.copyWith(followUp: followUp);
    } on RecommendationManagementException {
      rethrow;
    } on Object {
      throw const RecommendationManagementException(
        'Unable to create this follow-up action.',
      );
    }
  }

  @override
  Future<SavedRecommendation> updateFollowUp({
    required SavedRecommendation recommendation,
    required String actionText,
    required DateTime dueDate,
    required RecommendationFollowUpStatus status,
    required String? note,
  }) async {
    final existing = recommendation.followUp;
    if (existing == null) {
      throw const RecommendationManagementException(
        'No follow-up action is available to update.',
      );
    }
    final task = _requiredFollowUpAction(actionText);
    final date = _dateOnly(dueDate);
    final completedAt = status == RecommendationFollowUpStatus.completed
        ? (existing.completedAt ?? _now()).toUtc().toIso8601String()
        : null;
    try {
      final followUp = RecommendationFollowUp.fromJson(
        await _dataSource.updateFollowUp(
          followUpId: existing.followUpId,
          actionText: task,
          dueDate: _databaseDate(date),
          status: status.databaseValue,
          note: _nullableTrimmed(note),
          completedAt: completedAt,
        ),
      );
      return recommendation.copyWith(followUp: followUp);
    } on RecommendationManagementException {
      rethrow;
    } on Object {
      throw const RecommendationManagementException(
        'Unable to update this follow-up action.',
      );
    }
  }

  @override
  Future<void> deleteRecommendation(String recommendationId) async {
    try {
      await _dataSource.deleteRecommendation(recommendationId);
    } on RecommendationManagementException {
      rethrow;
    } on Object {
      throw const RecommendationManagementException(
        'Unable to delete this recommendation.',
      );
    }
  }
}

class SupabaseRecommendationManagementDataSource
    implements RecommendationManagementDataSource {
  SupabaseRecommendationManagementDataSource({SupabaseClient? client})
    : _injectedClient = client;

  final SupabaseClient? _injectedClient;
  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  @override
  Future<Map<String, dynamic>> insertRecommendation({
    required Map<String, dynamic> analysisReport,
    required Map<String, dynamic> recommendation,
  }) async {
    final adminId = _requireAdminSession();
    final parent = Map<String, dynamic>.from(
      await _client
          .from('analysis_reports')
          .insert({...analysisReport, 'requested_by': adminId})
          .select('analysis_report_id')
          .single(),
    );
    final reportId = parent['analysis_report_id'] as String;
    try {
      return Map<String, dynamic>.from(
        await _client
            .from('ai_recommendations')
            .insert({...recommendation, 'analysis_report_id': reportId})
            .select()
            .single(),
      );
    } on Object {
      await _client
          .from('analysis_reports')
          .delete()
          .eq('analysis_report_id', reportId);
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRecommendations() async {
    _requireAdminSession();
    final rows = await _client
        .from('ai_recommendations')
        .select('*, recommendation_follow_ups(*)')
        .order('created_at', ascending: false)
        .order('recommendation_id');
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> insertFollowUp({
    required String recommendationId,
    required String actionText,
    required String dueDate,
    required String? note,
  }) async {
    final adminId = _requireAdminSession();
    return Map<String, dynamic>.from(
      await _client
          .from('recommendation_follow_ups')
          .insert({
            'recommendation_id': recommendationId,
            'action_text': actionText,
            'due_date': dueDate,
            'follow_up_status': RecommendationFollowUpStatus.pending.databaseValue,
            'follow_up_notes': note,
            'created_by': adminId,
          })
          .select()
          .single(),
    );
  }

  @override
  Future<Map<String, dynamic>> updateFollowUp({
    required String followUpId,
    required String actionText,
    required String dueDate,
    required String status,
    required String? note,
    required String? completedAt,
  }) async {
    _requireAdminSession();
    return Map<String, dynamic>.from(
      await _client
          .from('recommendation_follow_ups')
          .update({
            'action_text': actionText,
            'due_date': dueDate,
            'follow_up_status': status,
            'follow_up_notes': note,
            'completed_at': completedAt,
          })
          .eq('follow_up_id', followUpId)
          .select()
          .single(),
    );
  }

  @override
  Future<Map<String, dynamic>> updateRecommendation({
    required String recommendationId,
    required String status,
    required String? adminNote,
  }) async {
    final adminId = _requireAdminSession();
    final reviewed = status != RecommendationReviewStatus.pending.databaseValue;
    return Map<String, dynamic>.from(
      await _client
          .from('ai_recommendations')
          .update({
            'status': status,
            'admin_notes': adminNote,
            'reviewed_by': reviewed ? adminId : null,
            'reviewed_at': reviewed ? DateTime.now().toUtc().toIso8601String() : null,
          })
          .eq('recommendation_id', recommendationId)
          .select()
          .single(),
    );
  }

  @override
  Future<void> deleteRecommendation(String recommendationId) async {
    _requireAdminSession();
    await _client
        .from('ai_recommendations')
        .delete()
        .eq('recommendation_id', recommendationId);
  }

  String _requireAdminSession() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const RecommendationManagementException(
        'Please sign in as an administrator to manage recommendations.',
      );
    }
    return userId;
  }
}

class RecommendationManagementException implements Exception {
  const RecommendationManagementException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _busFrequencyTitle(BusFrequencyRecommendationAction action) =>
    switch (action) {
      BusFrequencyRecommendationAction.increasePeakHourFrequency =>
        'Increase frequency',
      BusFrequencyRecommendationAction.maintainService => 'Maintain service',
      BusFrequencyRecommendationAction.decreaseService => 'Decrease service',
      BusFrequencyRecommendationAction.insufficientEvidence =>
        'Frequency recommendation',
    };

String _requiredFollowUpAction(String value) {
  final result = value.trim();
  if (result.isEmpty) {
    throw const RecommendationManagementException('Enter an action or task.');
  }
  return result;
}

String? _nullableTrimmed(String? value) {
  final result = value?.trim();
  return result == null || result.isEmpty ? null : result;
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

String _databaseDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
