import 'package:government_transit_collector/features/bus_feedback/data/feedback_issue_types.dart';

class BusFeedback {
  const BusFeedback({
    this.feedbackId,
    required this.userId,
    required this.routeId,
    this.tripId,
    required this.stopId,
    required this.issueType,
    required this.comment,
    required this.createdAt,
    this.serviceDate,
    this.scheduledDepartureSeconds,
    this.routeLabel,
    this.stopName,
  });

  final String? feedbackId;

  final String userId;

  final String routeId;
  final String? tripId;
  final String stopId;

  final String issueType;
  List<String> get issueTypes => decodeFeedbackIssueTypes(issueType);
  final String comment;

  final DateTime createdAt;
  final DateTime? serviceDate;
  final int? scheduledDepartureSeconds;
  final String? routeLabel;
  final String? stopName;

  // The deployed schema calls the report description `comment`. Preserve
  // that mapping for the shared feedback/admin module; this is not a thread.
  String get description => comment;

  String? get serviceDateKey => serviceDate == null
      ? null
      : '${serviceDate!.year.toString().padLeft(4, '0')}-${serviceDate!.month.toString().padLeft(2, '0')}-${serviceDate!.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() {
    return {
      if (feedbackId != null) 'feedback_id': feedbackId,
      'user_id': userId,
      'route_id': routeId,
      'trip_id': tripId,
      'stop_id': stopId,
      'issue_type': issueType,
      'comment': comment,
      'created_at': createdAt.toUtc().toIso8601String(),
      'service_date': serviceDateKey,
      'scheduled_departure_seconds': scheduledDepartureSeconds,
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'route_id': routeId,
      'trip_id': tripId,
      'stop_id': stopId,
      'issue_type': issueType,
      'comment': comment,
    };
  }

  factory BusFeedback.fromMap(Map<String, dynamic> map) {
    return BusFeedback(
      feedbackId: map['feedback_id'] as String?,
      userId: map['user_id'] as String,
      routeId: map['route_id'] as String? ?? '',
      tripId: map['trip_id'] as String?,
      stopId: map['stop_id'] as String? ?? '',
      issueType: map['issue_type'] as String,
      comment: map['comment'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      serviceDate: DateTime.tryParse(map['service_date'] as String? ?? ''),
      scheduledDepartureSeconds: map['scheduled_departure_seconds'] as int?,
      routeLabel:
          map['route_label'] as String? ??
          (map['route_id'] == null ? 'Not recorded' : null),
      stopName:
          map['stop_name'] as String? ??
          (map['stop_id'] == null ? 'Not recorded' : null),
    );
  }
}
