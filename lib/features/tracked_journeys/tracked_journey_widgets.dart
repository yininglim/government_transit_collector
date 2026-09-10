import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback_repository.dart';
import 'package:government_transit_collector/features/bus_feedback/data/feedback_reference_repository.dart';
import 'package:government_transit_collector/features/bus_feedback/presentation/bus_feedback_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/selected_journey_tracker_page.dart';
import 'tracked_journey.dart';
import 'tracked_journey_repository.dart';

Future<bool> startPassengerJourney(
  BuildContext context,
  TrackedJourneyRepository repository,
  TrackedJourneySnapshot snapshot,
) async {
  final active = await repository.active();
  if (!context.mounted) return false;
  String? replaceId;
  if (active != null &&
      jsonEncode(active.snapshot.toJson()) != jsonEncode(snapshot.toJson())) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start this journey instead?'),
        content: const Text(
          'Your current active journey will be marked cancelled. It will not appear in My Trips.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Current Journey'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start New Journey'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
    replaceId = active.id;
  }
  await repository.start(snapshot, replaceId: replaceId);
  return true;
}

class TrackedJourneySummary extends StatelessWidget {
  const TrackedJourneySummary({super.key, required this.snapshot});
  final TrackedJourneySnapshot snapshot;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(snapshot.routeLabel, style: Theme.of(context).textTheme.titleMedium),
      Text('${snapshot.originName} → ${snapshot.destinationName}'),
      const SizedBox(height: 6),
      Text(
        '${formatServiceDaySeconds(snapshot.recommendation.departureSeconds)} → ${formatServiceDaySeconds(snapshot.recommendation.arrivalSeconds)}',
      ),
      Text(
        snapshot.recommendation.transferCount == 0 ? 'Direct' : '1 transfer',
      ),
    ],
  );
}

class ActiveJourneySection extends StatefulWidget {
  const ActiveJourneySection({
    super.key,
    required this.repository,
    this.now,
    this.trackerBuilder,
  });
  final TrackedJourneyRepository repository;
  final DateTime Function()? now;
  final Widget Function(SelectedJourneyTracking)? trackerBuilder;
  @override
  State<ActiveJourneySection> createState() => _ActiveJourneySectionState();
}

class _ActiveJourneySectionState extends State<ActiveJourneySection>
    with WidgetsBindingObserver {
  TrackedJourney? _journey;
  String? _error;
  bool _busy = false, _notYet = false;
  int _request = 0;
  Timer? _arrivalTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.repository.addListener(_load);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    _arrivalTimer?.cancel();
    widget.repository.removeListener(_load);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final row = await widget.repository.active();
      if (!mounted || request != _request) return;
      final owned =
          row?.userId == widget.repository.userId && row?.status == 'active'
          ? row
          : null;
      setState(() {
        if (_journey?.id != owned?.id) _notYet = false;
        _journey = owned;
        _error = null;
      });
      _arrivalTimer?.cancel();
      if (owned != null) {
        final remaining = owned.snapshot.expectedArrival.difference(
          (widget.now ?? DateTime.now)().toUtc(),
        );
        if (remaining > Duration.zero) {
          _arrivalTimer = Timer(remaining, () {
            if (mounted) setState(() {});
          });
        }
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'Unable to load active journey.');
      }
    }
  }

  Future<void> _finish(bool completed) async {
    final journey = _journey;
    if (_busy || journey == null) return;
    if (!completed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel tracking?'),
          content: const Text(
            'This journey will not appear in completed My Trips.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Tracking'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel Tracking'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.finish(journey.id, completed: completed);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update journey. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final journey = _journey;
    if (_error != null) {
      return TextButton(onPressed: _load, child: Text('$_error Retry'));
    }
    if (journey == null) return const SizedBox.shrink();
    return Card(
      key: const Key('active-journey'),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'YOUR ACTIVE JOURNEY',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 10),
            TrackedJourneySummary(snapshot: journey.snapshot),
            const SizedBox(height: 8),
            const Text('● Journey tracking active'),
            if (journey.needsConfirmation((widget.now ?? DateTime.now)())) ...[
              const SizedBox(height: 12),
              Text(
                _notYet
                    ? 'Still travelling? Complete this journey when you arrive.'
                    : 'Have you completed this journey?',
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _notYet = true),
                    child: const Text('Not Yet'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : () => _finish(true),
                    child: const Text('Completed'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            widget.trackerBuilder?.call(
                              journey.snapshot.tracking,
                            ) ??
                            SelectedJourneyTrackerPage(
                              journey: journey.snapshot.tracking,
                              realtimeRepository:
                                  DataGovMyRealtimeVehicleRepository(),
                              journeyMapRepository: GtfsJourneyMapRepository(),
                            ),
                      ),
                    ),
              child: const Text('Continue Tracking'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _finish(false),
              child: const Text('Cancel Tracking'),
            ),
          ],
        ),
      ),
    );
  }
}

class MyTripsSection extends StatefulWidget {
  const MyTripsSection({
    super.key,
    required this.repository,
    required this.onPlanAgain,
    this.feedbackRepository,
    this.referenceRepository,
  });
  final TrackedJourneyRepository repository;
  final ValueChanged<RecentJourneySearch> onPlanAgain;
  final BusFeedbackRepository? feedbackRepository;
  final FeedbackReferenceRepository? referenceRepository;
  @override
  State<MyTripsSection> createState() => _MyTripsSectionState();
}

class _MyTripsSectionState extends State<MyTripsSection> {
  List<TrackedJourney>? _trips;
  bool _error = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.repository.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final trips = await widget.repository.completed();
      if (mounted && request == _request) {
        setState(() {
          _trips = trips
              .where(
                (t) =>
                    t.userId == widget.repository.userId &&
                    t.status == 'completed',
              )
              .toList();
          _error = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = true);
    }
  }

  void _report(TrackedJourneySnapshot snapshot) {
    final legs = snapshot.tracking.legs;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BusFeedbackPage(
          repository:
              widget.feedbackRepository ?? SupabaseBusFeedbackRepository(),
          referenceRepository:
              widget.referenceRepository ??
              SupabaseFeedbackReferenceRepository(),
          travelDate: snapshot.serviceDate,
          journeyOptions: [
            for (var i = 0; i < legs.length; i++)
              FeedbackJourneyOption(
                label: legs.length == 1 ? 'Direct Bus' : 'Leg ${i + 1}',
                routeId: legs[i].routeId,
                routeLabel: legs[i].routeName,
                tripId: legs[i].tripId,
                boardingStop: FeedbackStop(
                  id: legs[i].fromStopId,
                  name: legs[i].fromStopName,
                ),
                departureSeconds: i == 0
                    ? snapshot.recommendation.departureSeconds
                    : (snapshot.recommendation as TransferJourneyRecommendation)
                          .secondDepartureSeconds,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return TextButton(
        onPressed: _load,
        child: const Text('Unable to load My Trips. Retry'),
      );
    }
    if (_trips == null) return const Center(child: CircularProgressIndicator());
    if (_trips!.isEmpty) {
      return const Text('Your completed tracked journeys will appear here.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final trip in _trips!)
          Padding(
            key: ValueKey('completed-trip-${trip.id}'),
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(trip.snapshot.serviceDate),
                ),
                const SizedBox(height: 6),
                TrackedJourneySummary(snapshot: trip.snapshot),
                const Text('Completed'),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          widget.onPlanAgain(trip.snapshot.planAgain),
                      child: const Text('Plan Again'),
                    ),
                    TextButton(
                      onPressed: () => _report(trip.snapshot),
                      child: const Text('Report Problem'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
