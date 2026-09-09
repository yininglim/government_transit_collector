import 'package:flutter/material.dart';
import '../../bus_feedback/data/bus_feedback.dart';
import '../../realtime_vehicle/data/gtfs_realtime_decoder.dart';

/// Malaysia has a fixed UTC+8 offset, independent of the device timezone.
DateTime malaysiaHomeTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 8));

List<BusFeedback> homeReportsToday(
  List<BusFeedback> reports,
  String userId,
  DateTime now,
) {
  final today = malaysiaHomeTime(now);
  return reports.where((report) {
    final date = malaysiaHomeTime(report.createdAt);
    return report.userId == userId &&
        !report.createdAt.isAfter(now) &&
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
  }).toList();
}

class HomeTransitInsights extends StatelessWidget {
  const HomeTransitInsights({
    super.key,
    required this.now,
    required this.userId,
    required this.reports,
    required this.snapshot,
  });

  final DateTime now;
  final String userId;
  final List<BusFeedback>? reports;
  final RealtimeFeedSnapshot? snapshot;

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final today = reports == null
        ? null
        : homeReportsToday(reports!, userId, now);
    final categories = <String, int>{};
    for (final report in today ?? <BusFeedback>[]) {
      for (final issue in report.issueTypes.toSet()) {
        categories.update(issue, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final timestamp = snapshot?.feedTimestamp;
    final validTime =
        timestamp != null &&
        timestamp.millisecondsSinceEpoch > 0 &&
        !timestamp.isAfter(now);
    final local = validTime ? malaysiaHomeTime(timestamp) : null;
    String two(int value) => value.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(context, "Today's Transit", [
          const Text('Service Status: Unavailable'),
          Text(
            snapshot == null
                ? 'Data Status: Data unavailable'
                : snapshot!.vehicles.isEmpty
                ? 'Data Status: No vehicle observations in feed'
                : 'Data Status: Vehicle feed received',
          ),
          Text(
            local == null
                ? 'Feed update time unavailable'
                : 'Feed updated: ${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)} MYT (UTC+8)',
          ),
          Text(
            today == null
                ? 'Your reports today: Data unavailable'
                : 'Your reports today: ${today.length}',
          ),
        ]),
        _section(context, 'Community Today', [
          const Text('Your reports submitted today · Malaysia time'),
          const SizedBox(height: 6),
          if (today == null)
            const Text('Report data unavailable')
          else if (today.isEmpty)
            const Text('No reports from you today')
          else ...[
            for (final category in categories.entries)
              Text('${category.key}: ${category.value}'),
            if (categories.isEmpty) const Text('Report categories unavailable'),
          ],
        ]),
      ],
    );
  }
}
