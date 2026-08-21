class RecentJourneySearch {
  const RecentJourneySearch({
    this.id,
    required this.originStopId,
    required this.originStopName,
    required this.destinationStopId,
    required this.destinationStopName,
    required this.searchedAt,
  });

  factory RecentJourneySearch.fromMap(Map<String, Object?> map) {
    return RecentJourneySearch(
      id: map['id'] as int?,
      originStopId: map['origin_stop_id'] as String,
      originStopName: map['origin_stop_name'] as String,
      destinationStopId: map['destination_stop_id'] as String,
      destinationStopName: map['destination_stop_name'] as String,
      searchedAt: DateTime.parse(map['searched_at'] as String),
    );
  }

  final int? id;
  final String originStopId;
  final String originStopName;
  final String destinationStopId;
  final String destinationStopName;
  final DateTime searchedAt;

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'origin_stop_id': originStopId,
      'origin_stop_name': originStopName,
      'destination_stop_id': destinationStopId,
      'destination_stop_name': destinationStopName,
      'searched_at': searchedAt.toUtc().toIso8601String(),
    };
  }
}
