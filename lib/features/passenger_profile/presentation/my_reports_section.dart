import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback_repository.dart';
import 'package:government_transit_collector/features/bus_feedback/data/feedback_schedule_repository.dart';

class MyReportsSection extends StatefulWidget {
  const MyReportsSection({required this.userId, this.repository, super.key});
  final String userId;
  final BusFeedbackRepository? repository;

  @override
  State<MyReportsSection> createState() => _MyReportsSectionState();
}

class _MyReportsSectionState extends State<MyReportsSection> {
  List<BusFeedback>? _reports;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MyReportsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _reports = null;
      _error = null;
    });
    try {
      final reports =
          await (widget.repository ?? SupabaseBusFeedbackRepository())
              .getMyFeedback();
      if (!mounted || request != _request) return;
      setState(
        () =>
            _reports = reports.where((r) => r.userId == widget.userId).toList(),
      );
    } on Object {
      if (mounted && request == _request) {
        setState(
          () => _error = 'Unable to load your reports. Please try again.',
        );
      }
    }
  }

  String _date(DateTime date) =>
      '${MaterialLocalizations.of(context).formatMediumDate(date)}, ${date.year}';
  String _submitted(DateTime date) {
    final local = transitServiceDateTime(date);
    return '${_date(local)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: false)}';
  }

  void _details(BusFeedback report) {
    final fields = <String, String>{
      'Issue Type': report.issueTypes.join('\n'),
      'Route': report.routeLabel ?? report.routeId,
      'Related Bus Stop':
          '${report.stopName ?? report.stopId} (${report.stopId})',
      'Service Date': report.serviceDate == null
          ? 'Not recorded'
          : _date(report.serviceDate!),
      'Scheduled Departure': report.scheduledDepartureSeconds == null
          ? 'Not recorded'
          : feedbackDepartureLabel(report.scheduledDepartureSeconds!),
      'Description': report.description,
      'Submitted At': _submitted(report.createdAt),
    };
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Details'),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final field in fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.key,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(field.value),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('Retry my reports')),
        ],
      );
    }
    if (_reports == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reports!.isEmpty) {
      return const Text('You have not submitted any reports.');
    }
    return Column(
      children: [
        for (final report in _reports!)
          Card(
            margin: const EdgeInsets.only(top: 8),
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.primary.withValues(alpha: 0.16)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              titleTextStyle: Theme.of(context).textTheme.titleSmall,
              subtitleTextStyle: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.report_problem_outlined,
                      size: 17,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      report.issueTypes.join('\n'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            report.routeLabel ?? report.routeId,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(report.stopName ?? report.stopId),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _reportInformation(
                      Icons.directions_bus_outlined,
                      report.serviceDate != null
                          ? 'Service: ${_date(report.serviceDate!)}${report.scheduledDepartureSeconds == null ? '' : ' · ${feedbackDepartureLabel(report.scheduledDepartureSeconds!)}'}'
                          : 'Service date/time not recorded',
                    ),
                    const SizedBox(height: 3),
                    _reportInformation(
                      Icons.schedule_outlined,
                      'Submitted: ${_submitted(report.createdAt)}',
                    ),
                  ],
                ),
              ),
              isThreeLine: true,
              horizontalTitleGap: 8,
              trailing: Icon(Icons.chevron_right, color: colors.primary),
              onTap: () => _details(report),
            ),
          ),
      ],
    );
  }

  Widget _reportInformation(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 6),
      Expanded(child: Text(text)),
    ],
  );
}
