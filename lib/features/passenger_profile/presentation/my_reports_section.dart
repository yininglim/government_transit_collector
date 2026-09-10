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
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
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
              title: Text(report.issueTypes.join('\n')),
              subtitle: Text(
                [
                  '${report.routeLabel ?? report.routeId} · ${report.stopName ?? report.stopId}',
                  if (report.serviceDate != null)
                    'Service: ${_date(report.serviceDate!)}${report.scheduledDepartureSeconds == null ? '' : ' · ${feedbackDepartureLabel(report.scheduledDepartureSeconds!)}'}'
                  else
                    'Service date/time not recorded',
                  'Submitted: ${_submitted(report.createdAt)}',
                ].join('\n'),
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _details(report),
            ),
          ),
      ],
    );
  }
}
