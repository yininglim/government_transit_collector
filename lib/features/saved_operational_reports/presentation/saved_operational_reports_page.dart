import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report_repository.dart';
import 'package:government_transit_collector/features/saved_operational_reports/presentation/saved_operational_report_detail_page.dart';

class SavedOperationalReportsPage extends StatefulWidget {
  const SavedOperationalReportsPage({this.repository, super.key});

  final SavedOperationalReportRepository? repository;

  @override
  State<SavedOperationalReportsPage> createState() =>
      _SavedOperationalReportsPageState();
}

class _SavedOperationalReportsPageState
    extends State<SavedOperationalReportsPage> {
  late final SavedOperationalReportRepository _repository;
  List<SavedOperationalReport> _reports = const [];
  SavedOperationalReportType? _type;
  SavedOperationalReportStatus? _status;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? DefaultSavedOperationalReportRepository();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _refreshing = refresh && _reports.isNotEmpty;
      _loading = !refresh || _reports.isEmpty;
      _error = null;
    });
    try {
      final reports = await _repository.loadReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
        _refreshing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = error.toString();
      });
    }
  }

  List<SavedOperationalReport> get _visibleReports => _reports
      .where((report) => _type == null || report.reportType == _type)
      .where((report) => _status == null || report.status == _status)
      .toList(growable: false);

  Future<void> _open(SavedOperationalReport report) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SavedOperationalReportDetailPage(
          report: report,
          repository: _repository,
        ),
      ),
    );
    if (!mounted) return;
    if (deleted == true) {
      setState(() {
        _reports = _reports
            .where((item) => item.reportId != report.reportId)
            .toList(growable: false);
      });
    } else {
      await _load(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Saved Operational Reports'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading || _refreshing
              ? null
              : () => _load(refresh: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null && _reports.isEmpty)
            _errorState()
          else
            RefreshIndicator(
              onRefresh: () => _load(refresh: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Historical analysis snapshots',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Review and manage reports saved from operational analysis.',
                  ),
                  const SizedBox(height: 16),
                  _filters(),
                  const SizedBox(height: 16),
                  if (_error != null) _inlineError(),
                  if (_reports.isEmpty)
                    _emptyState()
                  else if (_visibleReports.isEmpty)
                    _filteredEmptyState()
                  else
                    ..._visibleReports.map(_reportCard),
                ],
              ),
            ),
          if (_refreshing)
            const LinearProgressIndicator(key: Key('reports-refresh-progress')),
        ],
      ),
    ),
  );

  Widget _filters() => LayoutBuilder(
    builder: (context, constraints) {
      final type = DropdownButtonFormField<SavedOperationalReportType?>(
        key: const Key('report-type-filter'),
        initialValue: _type,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Report Type',
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('All')),
          ...SavedOperationalReportType.values.map(
            (value) => DropdownMenuItem(value: value, child: Text(value.label)),
          ),
        ],
        onChanged: (value) => setState(() => _type = value),
      );
      final status = DropdownButtonFormField<SavedOperationalReportStatus?>(
        key: const Key('report-status-filter'),
        initialValue: _status,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Status',
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('All')),
          ...SavedOperationalReportStatus.values.map(
            (value) => DropdownMenuItem(value: value, child: Text(value.label)),
          ),
        ],
        onChanged: (value) => setState(() => _status = value),
      );
      if (constraints.maxWidth < 600) {
        return Column(children: [type, const SizedBox(height: 12), status]);
      }
      return Row(
        children: [
          Expanded(child: type),
          const SizedBox(width: 12),
          Expanded(child: status),
        ],
      );
    },
  );

  Widget _reportCard(SavedOperationalReport report) => Card(
    key: ValueKey('report-${report.reportId}'),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(report),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_typeIcon(report.reportType)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(report.reportType.label),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(report.status.label)),
                Chip(
                  avatar: const Icon(Icons.route, size: 18),
                  label: Text(_routeLabel(report)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Period: ${_dateRange(report.periodStart, report.periodEnd)}'),
            Text('Saved: ${_dateTime(report.createdAt)}'),
          ],
        ),
      ),
    ),
  );

  Widget _emptyState() => _stateCard(
    key: const Key('saved-reports-empty'),
    icon: Icons.inventory_2_outlined,
    title: 'No saved operational reports',
    message:
        'Reports will appear here after an admin saves a Route Performance or Peak Operation analysis.',
  );

  Widget _filteredEmptyState() => _stateCard(
    key: const Key('saved-reports-filtered-empty'),
    icon: Icons.filter_alt_off_outlined,
    title: 'No matching reports',
    message: 'Try changing the report type or status filter.',
  );

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 8),
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    ),
  );

  Widget _inlineError() => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: const Icon(Icons.error_outline),
      title: Text(_error!),
      trailing: TextButton(
        onPressed: () => _load(refresh: true),
        child: const Text('Retry'),
      ),
    ),
  );

  Widget _stateCard({
    required Key key,
    required IconData icon,
    required String title,
    required String message,
  }) => Card(
    key: key,
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, size: 52),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

IconData _typeIcon(SavedOperationalReportType type) => switch (type) {
  SavedOperationalReportType.routePerformance => Icons.analytics_outlined,
  SavedOperationalReportType.peakOperation => Icons.query_stats,
};

String _routeLabel(SavedOperationalReport report) =>
    report.routeId == null ? 'All Routes' : report.routeNameSnapshot;

String _dateRange(DateTime start, DateTime end) =>
    '${_date(start)} – ${_date(end)}';

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _dateTime(DateTime value) =>
    '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
