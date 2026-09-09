enum SavedOperationalReportType {
  routePerformance('route_performance', 'Route Performance'),
  peakOperation('peak_operation', 'Peak Operation');

  const SavedOperationalReportType(this.databaseValue, this.label);

  final String databaseValue;
  final String label;

  static SavedOperationalReportType parse(Object? value) => values.firstWhere(
    (item) => item.databaseValue == value,
    orElse: () => throw FormatException('Unknown report type: $value'),
  );
}

enum SavedOperationalReportStatus {
  draft('draft', 'Draft'),
  reviewed('reviewed', 'Reviewed'),
  needsAttention('needs_attention', 'Needs Attention'),
  resolved('resolved', 'Resolved');

  const SavedOperationalReportStatus(this.databaseValue, this.label);

  final String databaseValue;
  final String label;

  static SavedOperationalReportStatus parse(Object? value) => values.firstWhere(
    (item) => item.databaseValue == value,
    orElse: () => throw FormatException('Unknown report status: $value'),
  );
}

class SavedOperationalReport {
  const SavedOperationalReport({
    required this.reportId,
    required this.adminId,
    required this.reportType,
    required this.routeId,
    required this.routeNameSnapshot,
    required this.periodStart,
    required this.periodEnd,
    required this.title,
    required this.resultSnapshot,
    required this.adminNotes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String reportId;
  final String adminId;
  final SavedOperationalReportType reportType;
  final String? routeId;
  final String routeNameSnapshot;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String title;
  final Map<String, dynamic> resultSnapshot;
  final String? adminNotes;
  final SavedOperationalReportStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory SavedOperationalReport.fromJson(Map<String, dynamic> json) {
    final snapshot = json['result_snapshot'];
    if (snapshot is! Map) {
      throw const FormatException('Report snapshot must be a JSON object.');
    }
    return SavedOperationalReport(
      reportId: _requiredString(json, 'report_id'),
      adminId: _requiredString(json, 'admin_id'),
      reportType: SavedOperationalReportType.parse(json['report_type']),
      routeId: _nullableString(json, 'route_id'),
      routeNameSnapshot: _requiredString(json, 'route_name_snapshot'),
      periodStart: _date(json, 'period_start'),
      periodEnd: _date(json, 'period_end'),
      title: _requiredString(json, 'title'),
      resultSnapshot: Map<String, dynamic>.from(snapshot),
      adminNotes: _nullableString(json, 'admin_notes'),
      status: SavedOperationalReportStatus.parse(json['status']),
      createdAt: _date(json, 'created_at'),
      updatedAt: _date(json, 'updated_at'),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('Missing or invalid $key.');
    }
    return value;
  }

  static String? _nullableString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('Invalid $key.');
    return value;
  }

  static DateTime _date(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) throw FormatException('Missing or invalid $key.');
    return DateTime.parse(value);
  }
}
