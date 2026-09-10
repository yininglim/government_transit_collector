import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_priority.dart';

enum RecommendationManagementFeature { busFrequency, routeBusStop }

enum RecommendationFollowUpStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed');

  const RecommendationFollowUpStatus(this.databaseValue);

  final String databaseValue;

  static RecommendationFollowUpStatus? fromDatabase(Object? value) =>
      switch (value) {
        'pending' => RecommendationFollowUpStatus.pending,
        'in_progress' => RecommendationFollowUpStatus.inProgress,
        'completed' => RecommendationFollowUpStatus.completed,
        _ => null,
      };
}

enum RecommendationReviewStatus {
  pending('pending_review'),
  accepted('accepted'),
  rejected('rejected');

  const RecommendationReviewStatus(this.databaseValue);

  final String databaseValue;

  static RecommendationReviewStatus? fromDatabase(Object? value) =>
      switch (value) {
        'draft' || 'pending_review' => RecommendationReviewStatus.pending,
        'accepted' => RecommendationReviewStatus.accepted,
        'rejected' => RecommendationReviewStatus.rejected,
        _ => null,
      };
}

class SavedRecommendation {
  const SavedRecommendation({
    required this.recommendationId,
    required this.feature,
    required this.routeId,
    required this.routeDisplayLabel,
    required this.actions,
    required this.title,
    required this.rationale,
    required this.limitations,
    required this.evidenceReferences,
    required this.targetStopIds,
    required this.candidateArea,
    required this.status,
    required this.adminNote,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewedAt,
    this.priorityLevel,
    this.priorityReasons = const [],
    this.followUp,
  });

  final String recommendationId;
  final RecommendationManagementFeature feature;
  final String? routeId;
  final String routeDisplayLabel;
  final List<String> actions;
  final String title;
  final String rationale;
  final List<String> limitations;
  final List<String> evidenceReferences;
  final List<String> targetStopIds;
  final Map<String, dynamic>? candidateArea;
  final RecommendationReviewStatus status;
  final String? adminNote;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? reviewedAt;
  final RecommendationPriorityLevel? priorityLevel;
  final List<String> priorityReasons;
  final RecommendationFollowUp? followUp;

  factory SavedRecommendation.fromJson(Map<String, dynamic> json) {
    final snapshot = _map(json['supporting_metrics']);
    final feature = _feature(snapshot['feature_type'], json['recommendation_type']);
    final status = RecommendationReviewStatus.fromDatabase(json['status']);
    final id = _requiredString(json['recommendation_id']);
    final title = _requiredString(json['title']);
    final rationale = _requiredString(json['description']);
    final routeId = _nullableString(json['route_id']) ??
        _nullableString(snapshot['route_id']);
    final priorityLevel = snapshot['priority_rule_version'] == 1
        ? RecommendationPriorityLevel.fromSnapshot(snapshot['priority_level'])
        : null;
    if (feature == null || status == null || id == null || title == null || rationale == null) {
      throw const FormatException('Unsupported saved recommendation row.');
    }
    return SavedRecommendation(
      recommendationId: id,
      feature: feature,
      routeId: routeId,
      routeDisplayLabel:
          _nullableString(snapshot['route_display_label']) ?? routeId ?? title,
      actions: _stringList(
        feature == RecommendationManagementFeature.busFrequency
            ? [snapshot['action']]
            : snapshot['actions'],
      ),
      title: title,
      rationale: rationale,
      limitations: _stringList(snapshot['limitations']),
      evidenceReferences: _stringList(snapshot['evidence_refs']),
      targetStopIds: _stringList(snapshot['target_stop_ids']),
      candidateArea: _nullableMap(snapshot['candidate_area']),
      status: status,
      adminNote: _nullableString(json['admin_notes']),
      createdAt: _date(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: _date(json['updated_at']),
      reviewedAt: _date(json['reviewed_at']),
      priorityLevel: priorityLevel,
      priorityReasons: priorityLevel == null
          ? const []
          : _stringList(snapshot['priority_reasons']),
      followUp: _followUp(json['recommendation_follow_ups']),
    );
  }

  SavedRecommendation copyWith({
    RecommendationReviewStatus? status,
    String? adminNote,
    bool clearAdminNote = false,
    DateTime? updatedAt,
    DateTime? reviewedAt,
    bool clearReviewedAt = false,
    RecommendationFollowUp? followUp,
  }) => SavedRecommendation(
    recommendationId: recommendationId,
    feature: feature,
    routeId: routeId,
    routeDisplayLabel: routeDisplayLabel,
    actions: actions,
    title: title,
    rationale: rationale,
    limitations: limitations,
    evidenceReferences: evidenceReferences,
    targetStopIds: targetStopIds,
    candidateArea: candidateArea,
    status: status ?? this.status,
    adminNote: clearAdminNote ? null : adminNote ?? this.adminNote,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    reviewedAt: clearReviewedAt ? null : reviewedAt ?? this.reviewedAt,
    priorityLevel: priorityLevel,
    priorityReasons: priorityReasons,
    followUp: followUp ?? this.followUp,
  );
}

class RecommendationFollowUp {
  const RecommendationFollowUp({
    required this.followUpId,
    required this.recommendationId,
    required this.actionText,
    required this.dueDate,
    required this.status,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
  });

  final String followUpId;
  final String recommendationId;
  final String actionText;
  final DateTime dueDate;
  final RecommendationFollowUpStatus status;
  final String? note;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  factory RecommendationFollowUp.fromJson(Map<String, dynamic> json) {
    final followUpId = _requiredString(json['follow_up_id']);
    final recommendationId = _requiredString(json['recommendation_id']);
    final actionText = _requiredString(json['action_text']);
    final dueDate = _date(json['due_date']);
    final status = RecommendationFollowUpStatus.fromDatabase(
      json['follow_up_status'],
    );
    final createdAt = _date(json['created_at']);
    if (followUpId == null ||
        recommendationId == null ||
        actionText == null ||
        dueDate == null ||
        status == null ||
        createdAt == null) {
      throw const FormatException('Unsupported recommendation follow-up row.');
    }
    return RecommendationFollowUp(
      followUpId: followUpId,
      recommendationId: recommendationId,
      actionText: actionText,
      dueDate: dueDate,
      status: status,
      note: _nullableString(json['follow_up_notes']),
      createdAt: createdAt,
      updatedAt: _date(json['updated_at']),
      completedAt: _date(json['completed_at']),
    );
  }
}

RecommendationManagementFeature? _feature(Object? snapshot, Object? type) =>
    switch (snapshot) {
      'bus_frequency' => RecommendationManagementFeature.busFrequency,
      'route_bus_stop' => RecommendationManagementFeature.routeBusStop,
      _ => switch (type) {
        'bus_frequency' => RecommendationManagementFeature.busFrequency,
        'stop_suitability' || 'route_improvement' =>
          RecommendationManagementFeature.routeBusStop,
        _ => null,
      },
    };

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

Map<String, dynamic>? _nullableMap(Object? value) {
  final result = _map(value);
  return result.isEmpty ? null : result;
}

String? _requiredString(Object? value) {
  final result = _nullableString(value);
  return result?.isEmpty == true ? null : result;
}

String? _nullableString(Object? value) =>
    value is String ? value.trim() : null;

List<String> _stringList(Object? value) {
  final values = value is List ? value : const [];
  return values
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

RecommendationFollowUp? _followUp(Object? value) {
  final Object? raw;
  if (value is Map) {
    raw = value;
  } else if (value is List && value.isNotEmpty && value.first is Map) {
    raw = value.first;
  } else {
    raw = null;
  }
  if (raw is! Map) return null;
  try {
    return RecommendationFollowUp.fromJson(
      raw.map((key, item) => MapEntry(key.toString(), item)),
    );
  } on FormatException {
    return null;
  }
}

String recommendationFeatureLabel(RecommendationManagementFeature feature) =>
    switch (feature) {
      RecommendationManagementFeature.busFrequency => 'Bus Frequency',
      RecommendationManagementFeature.routeBusStop => 'Route & Bus Stop',
    };

String recommendationStatusLabel(RecommendationReviewStatus status) =>
    switch (status) {
      RecommendationReviewStatus.pending => 'Pending',
      RecommendationReviewStatus.accepted => 'Accepted',
      RecommendationReviewStatus.rejected => 'Rejected',
    };

String recommendationFollowUpStatusLabel(RecommendationFollowUpStatus status) =>
    switch (status) {
      RecommendationFollowUpStatus.pending => 'Pending',
      RecommendationFollowUpStatus.inProgress => 'In Progress',
      RecommendationFollowUpStatus.completed => 'Completed',
    };

String recommendationActionLabel(String action) => switch (action) {
  'increasePeakHourFrequency' => 'Increase Peak-Hour Frequency',
  'maintainService' => 'Maintain Service',
  'decreaseService' => 'Decrease Service',
  'routeImprovement' => 'Route Improvement',
  'stopImprovement' => 'Stop Improvement',
  'additionalStopCoverage' => 'Additional Stop Coverage',
  'maintainCurrentConfiguration' => 'Maintain Current Configuration',
  _ => 'Other Recommendation',
};
