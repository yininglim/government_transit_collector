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
  });

  final String? feedbackId;

  final String userId;

  final String routeId;
  final String? tripId;
  final String stopId;

  final String issueType;
  final String comment;

  final DateTime createdAt;

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

  factory BusFeedback.fromMap(
      Map<String, dynamic> map,
      ) {
    return BusFeedback(
      feedbackId:
      map['feedback_id'] as String?,
      userId:
      map['user_id'] as String,
      routeId:
      map['route_id'] as String,
      tripId:
      map['trip_id'] as String?,
      stopId:
      map['stop_id'] as String,
      issueType:
      map['issue_type'] as String,
      comment:
      map['comment'] as String,
      createdAt: DateTime.parse(
        map['created_at'] as String,
      ),
    );
  }
}