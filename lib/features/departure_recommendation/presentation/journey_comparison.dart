import 'package:flutter/material.dart';
import '../data/timetable_recommendation_repository.dart';
import '../../bus_feedback/data/bus_feedback.dart';

Map<String, int> recentJourneyIssues(
  List<BusFeedback> reports,
  JourneyRecommendation journey,
  DateTime now,
) {
  final routes = switch (journey) {
    DirectJourneyRecommendation j => {j.routeId},
    TransferJourneyRecommendation j => {j.firstRouteId, j.secondRouteId},
  };
  final counts = <String, int>{};
  for (final report in reports) {
    final age = now.toUtc().difference(report.createdAt.toUtc());
    if (!routes.contains(report.routeId) ||
        age.isNegative ||
        age > const Duration(days: 7)) {
      continue;
    }
    for (final issue in report.issueTypes) {
      counts.update(issue, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}

class JourneyComparison extends StatelessWidget {
  const JourneyComparison({super.key, required this.journeys});
  final List<JourneyRecommendation> journeys;

  Widget _journey(
    BuildContext context,
    JourneyRecommendation journey,
    bool best,
  ) {
    final route = switch (journey) {
      DirectJourneyRecommendation j =>
        '${j.routeShortName ?? j.routeId} \u00b7 Direct',
      TransferJourneyRecommendation j =>
        '${j.firstRouteShortName ?? j.firstRouteId} \u2192 ${j.secondRouteShortName ?? j.secondRouteId} \u00b7 1 transfer',
    };
    return Container(
      key: best ? const Key('comparison-best-choice') : null,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: best
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (best)
            Text('BEST CHOICE', style: Theme.of(context).textTheme.labelLarge),
          Text(route, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${formatServiceDaySeconds(journey.departureSeconds)} \u2192 ${formatServiceDaySeconds(journey.arrivalSeconds)}',
          ),
          Text(formatDurationMinutes(journey.durationSeconds)),
          if (journey case TransferJourneyRecommendation j)
            Text(
              'Transfer at ${j.transferStopName} \u00b7 ${formatDurationMinutes(j.transferWaitSeconds)} wait',
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (journeys.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        title: const Text('Journey Comparison'),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          _journey(context, journeys.first, true),
          if (journeys.length > 1) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('ALTERNATIVES'),
              ),
            ),
            for (final journey in selectJourneyAlternatives(
              journeys,
              limit: 4,
            ).skip(1))
              _journey(context, journey, false),
          ],
        ],
      ),
    );
  }
}
