import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report_repository.dart';

class SavedOperationalReportDetailPage extends StatefulWidget {
  const SavedOperationalReportDetailPage({
    required this.report,
    required this.repository,
    super.key,
  });

  final SavedOperationalReport report;
  final SavedOperationalReportRepository repository;

  @override
  State<SavedOperationalReportDetailPage> createState() =>
      _SavedOperationalReportDetailPageState();
}

class _SavedOperationalReportDetailPageState
    extends State<SavedOperationalReportDetailPage> {
  late SavedOperationalReport _report;
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late SavedOperationalReportStatus _status;
  bool _editing = false;
  bool _saving = false;
  bool _deleting = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _titleController = TextEditingController(text: _report.title);
    _notesController = TextEditingController(text: _report.adminNotes ?? '');
    _status = _report.status;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _titleError = 'Title cannot be blank.');
      return;
    }
    setState(() {
      _saving = true;
      _titleError = null;
    });
    try {
      final updated = await widget.repository.updateManagementMetadata(
        reportId: _report.reportId,
        title: _titleController.text,
        adminNotes: _notesController.text,
        status: _status,
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() {
        _report = updated;
        _restoreFields();
        _editing = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report updated successfully.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _startEditing() {
    _restoreFields();
    setState(() {
      _titleError = null;
      _editing = true;
    });
  }

  void _cancelEditing() {
    FocusScope.of(context).unfocus();
    setState(() {
      _restoreFields();
      _titleError = null;
      _editing = false;
    });
  }

  void _restoreFields() {
    _titleController.text = _report.title;
    _notesController.text = _report.adminNotes ?? '';
    _status = _report.status;
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved report?'),
        content: const Text(
          'This removes the historical report permanently. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.repository.deleteReport(_report.reportId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Operational Report'),
      actions: [
        IconButton(
          tooltip: 'Delete report',
          onPressed: _saving || _deleting ? null : _delete,
          icon: _deleting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            title: 'Management details',
            icon: Icons.edit_note,
            children: _editing
                ? [
                    TextField(
                      key: const Key('report-title-field'),
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        border: const OutlineInputBorder(),
                        errorText: _titleError,
                      ),
                      onChanged: (_) {
                        if (_titleError != null) {
                          setState(() => _titleError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<SavedOperationalReportStatus>(
                      key: const Key('report-status-field'),
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: SavedOperationalReportStatus.values
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(status.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _status = value);
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('report-notes-field'),
                      controller: _notesController,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Admin notes',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          TextButton(
                            key: const Key('cancel-report-metadata'),
                            onPressed: _saving ? null : _cancelEditing,
                            child: const Text('Cancel'),
                          ),
                          FilledButton.icon(
                            key: const Key('save-report-metadata'),
                            onPressed: _saving || _deleting ? null : _save,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('Save changes'),
                          ),
                        ],
                      ),
                    ),
                  ]
                : [
                    _fact('Title', _report.title),
                    _statusFact(_report.status),
                    _fact(
                      'Admin notes',
                      _report.adminNotes?.trim().isNotEmpty == true
                          ? _report.adminNotes!
                          : 'No admin notes.',
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        key: const Key('edit-report-metadata'),
                        onPressed: _deleting ? null : _startEditing,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                    ),
                  ],
          ),
          const SizedBox(height: 12),
          _section(
            title: 'Report source',
            icon: Icons.info_outline,
            children: [_sourceDetails()],
          ),
          const SizedBox(height: 12),
          _section(
            title: 'Result snapshot',
            icon: Icons.assessment_outlined,
            children: [_snapshotContent(_report.resultSnapshot)],
          ),
        ],
      ),
    ),
  );

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 2),
        SelectableText(value),
      ],
    ),
  );

  Widget _statusFact(SavedOperationalReportStatus status) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Status', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Chip(
          key: const Key('report-status-value'),
          avatar: const Icon(Icons.circle, size: 10),
          label: Text(status.label),
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
  );

  Widget _sourceDetails() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 620
          ? (constraints.maxWidth - 16) / 2
          : constraints.maxWidth;
      final items = [
        ('Report type', _report.reportType.label),
        (
          'Route',
          _report.routeId == null ? 'All Routes' : _report.routeNameSnapshot,
        ),
        (
          'Analysis period',
          '${_friendlyDateTime(_report.periodStart)}\n${_friendlyDateTime(_report.periodEnd)}',
        ),
        ('Created', _friendlyDateTime(_report.createdAt)),
        ('Last updated', _friendlyDateTime(_report.updatedAt)),
      ];
      return Wrap(
        spacing: 16,
        runSpacing: 2,
        children: [
          for (final item in items)
            SizedBox(width: width, child: _fact(item.$1, item.$2)),
        ],
      );
    },
  );

  Widget _snapshotContent(Map<String, dynamic> snapshot) {
    if (snapshot.isEmpty) {
      return const Text('No result values were stored in this snapshot.');
    }
    final primaryKeys =
        _report.reportType == SavedOperationalReportType.routePerformance
        ? const [
            'average_travel_time_minutes',
            'delay_frequency_percent',
            'schedule_adherence_percent',
            'trips_used_in_metrics',
          ]
        : const [
            'peak_period',
            'peak_average_active_trips',
            'peak_activity_level',
            'average_activity',
          ];
    final primary = [
      for (final key in primaryKeys)
        if (snapshot.containsKey(key)) (key: key, value: snapshot[key]),
    ];
    final supporting = snapshot.entries
        .where((entry) => !primaryKeys.contains(entry.key))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (primary.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760
                  ? 4
                  : constraints.maxWidth >= 380
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final metric in primary)
                    _metricTile(
                      width: width,
                      label: _snapshotLabel(metric.key),
                      value: _snapshotValue(metric.key, metric.value),
                      icon: _snapshotIcon(metric.key),
                    ),
                ],
              );
            },
          ),
        if (supporting.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            _report.reportType == SavedOperationalReportType.routePerformance
                ? 'Trip coverage and supporting details'
                : 'Supporting details',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var index = 0; index < supporting.length; index++) ...[
                  _supportingRow(
                    _snapshotLabel(supporting[index].key),
                    _snapshotValue(
                      supporting[index].key,
                      supporting[index].value,
                    ),
                  ),
                  if (index != supporting.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _metricTile({
    required double width,
    required String label,
    required String value,
    required IconData icon,
  }) => Container(
    width: width,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 10),
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );

  Widget _supportingRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        Flexible(
          child: SelectableText(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    ),
  );
}

String _humanize(String value) {
  final words = value.replaceAll('_', ' ').trim().split(RegExp(r'\s+'));
  return words
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

String _snapshotLabel(String key) => switch (key) {
  'average_travel_time_minutes' => 'Average Travel Time',
  'delay_frequency_percent' => 'Delay Frequency',
  'schedule_adherence_percent' => 'Schedule Adherence',
  'trips_used_in_metrics' => 'Trips Used in Metrics',
  'delayed_trip_count' => 'Delayed Trips',
  'on_time_trip_count' => 'On-Time Trips',
  'partial_trip_occurrences' => 'Partial Trip Occurrences',
  'total_observed_trip_occurrences' => 'Total Observed Trip Occurrences',
  'total_observations' => 'Total Observations',
  'peak_period' => 'Peak Period',
  'peak_average_active_trips' => 'Peak Average Active Trips',
  'peak_activity_level' => 'Peak Activity Level',
  'average_activity' => 'Average Activity',
  'activity_difference_percent' => 'Activity Difference',
  'has_reliable_peak' => 'Reliable Peak',
  'has_limited_coverage' => 'Limited Coverage',
  'distinct_trip_occurrences' => 'Distinct Trip Occurrences',
  'populated_bucket_count' => 'Populated Time Periods',
  'observed_day_count' => 'Observed Days',
  'routes_represented' => 'Routes Represented',
  'observed_window_start' => 'Observed Window Start',
  'observed_window_end' => 'Observed Window End',
  'busiest_route_id' => 'Busiest Route ID',
  'busiest_route_name' => 'Busiest Route',
  'busiest_route_trip_occurrences' => 'Busiest Route Trip Occurrences',
  'peak_bucket_start_minute' => 'Peak Start Minute',
  'peak_bucket_end_minute' => 'Peak End Minute',
  _ => _humanize(key),
};

String _snapshotValue(String key, Object? value) {
  if (value == null) return 'Not available';
  if (value is num) {
    if (key == 'average_travel_time_minutes') {
      return '${value.toStringAsFixed(1)} min';
    }
    if (key.endsWith('_percent')) return '${value.toStringAsFixed(1)}%';
    if (key == 'peak_average_active_trips' || key == 'average_activity') {
      return value.toStringAsFixed(1);
    }
    if (value == value.roundToDouble()) return _integer(value.toInt());
    return value.toStringAsFixed(1);
  }
  if (value is bool) return value ? 'Yes' : 'No';
  if (key == 'peak_activity_level') return _humanize('$value');
  if (key == 'observed_window_start' || key == 'observed_window_end') {
    final parsed = DateTime.tryParse('$value');
    if (parsed != null) return _friendlyDateTime(parsed);
  }
  return _value(value);
}

IconData _snapshotIcon(String key) => switch (key) {
  'average_travel_time_minutes' => Icons.schedule_outlined,
  'delay_frequency_percent' => Icons.warning_amber_outlined,
  'schedule_adherence_percent' => Icons.fact_check_outlined,
  'trips_used_in_metrics' => Icons.directions_bus_outlined,
  'peak_period' => Icons.access_time_filled,
  'peak_average_active_trips' => Icons.route_outlined,
  'peak_activity_level' => Icons.insights_outlined,
  'average_activity' => Icons.query_stats_outlined,
  _ => Icons.analytics_outlined,
};

String _integer(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return value < 0 ? '-$buffer' : '$buffer';
}

String _value(Object? value) {
  if (value == null) return 'Not available';
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num && value == value.roundToDouble()) {
    return _integer(value.toInt());
  }
  if (value is List) return value.map(_value).join(', ');
  if (value is Map) {
    return value.entries
        .map((entry) => '${_humanize('${entry.key}')}: ${_value(entry.value)}')
        .join('\n');
  }
  return '$value';
}

String _friendlyDateTime(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour < 12 ? 'AM' : 'PM';
  return '${value.day} ${months[value.month - 1]} ${value.year}, '
      '$hour:$minute $period';
}
