import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/journey_map/presentation/route_map_page.dart';
import 'package:government_transit_collector/features/passenger_location/data/boarding_stop_distance.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location_service.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/arrival_estimator.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/journey_progress_calculator.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/journey_stage_detector.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_realtime_matcher.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_tracker_controller.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';

typedef SelectedJourneyMapBuilder =
    Widget Function(
      JourneyMapData data,
      List<RealtimeVehicleMarkerData> realtimeMarkers,
      PassengerLocation? passengerLocation,
    );

class SelectedJourneyTrackerPage extends StatefulWidget {
  const SelectedJourneyTrackerPage({
    required this.journey,
    required this.realtimeRepository,
    required this.journeyMapRepository,
    this.tripProgressRepository,
    this.passengerLocationService,
    this.pollingInterval = realtimePollingInterval,
    this.mapBuilder,
    this.now,
    super.key,
  });

  final SelectedJourneyTracking journey;
  final RealtimeVehicleRepository realtimeRepository;
  final JourneyMapRepository journeyMapRepository;
  final TripProgressRepository? tripProgressRepository;
  final PassengerLocationService? passengerLocationService;
  final Duration pollingInterval;
  final SelectedJourneyMapBuilder? mapBuilder;
  final DateTime Function()? now;

  @override
  State<SelectedJourneyTrackerPage> createState() =>
      _SelectedJourneyTrackerPageState();
}

class _SelectedJourneyTrackerPageState extends State<SelectedJourneyTrackerPage>
    with WidgetsBindingObserver {
  late final RealtimeTrackerController _controller;
  late List<RealtimeVehicleMarkerData?> _currentByLeg;
  late List<RealtimeVehicleMarkerData?> _lastKnownByLeg;
  late List<JourneyProgressCalculator?> _progressCalculators;
  late List<JourneyProgressState?> _progressByLeg;
  late List<Object?> _progressErrors;
  late List<bool> _progressLoading;
  late List<RealtimeMovementHistory> _movementHistoryByLeg;
  late List<ArrivalEstimate?> _arrivalEstimateByLeg;
  static const _arrivalEstimator = ArrivalEstimator();
  late final PassengerLocationService _passengerLocationService;
  PassengerLocationResult _passengerLocationResult =
      const PassengerLocationResult.loading();
  var _passengerLocationRequestInFlight = false;
  Object? _observedSnapshot;
  JourneyMapData? _mapData;
  Object? _mapError;
  var _selectedLeg = 0;
  var _journeyStage = JourneyStageResult.initial();
  var _followsCurrentStage = true;
  final _expandedUpcomingLegs = <int>{};
  final _expandedPassedLegs = <int>{};
  var _mapDisplayMode = JourneyMapDisplayMode.wholeJourney;
  final _journeyMapKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentByLeg = List.filled(widget.journey.legs.length, null);
    _lastKnownByLeg = List.filled(widget.journey.legs.length, null);
    _progressCalculators = List.filled(widget.journey.legs.length, null);
    _progressByLeg = List.filled(widget.journey.legs.length, null);
    _progressErrors = List.filled(widget.journey.legs.length, null);
    _progressLoading = List.filled(widget.journey.legs.length, true);
    _movementHistoryByLeg = [
      for (var index = 0; index < widget.journey.legs.length; index++)
        RealtimeMovementHistory(),
    ];
    _arrivalEstimateByLeg = List.filled(widget.journey.legs.length, null);
    _passengerLocationService =
        widget.passengerLocationService ?? ForegroundPassengerLocationService();
    _controller = RealtimeTrackerController(
      repository: widget.realtimeRepository,
      pollingInterval: widget.pollingInterval,
    )..addListener(_onControllerChanged);
    _loadMap();
    _loadAllProgressData();
    _refreshPassengerLocation();
    _controller.startPolling();
  }

  Future<void> _refreshPassengerLocation() async {
    if (_passengerLocationRequestInFlight || !mounted) return;
    _passengerLocationRequestInFlight = true;
    setState(() {
      _passengerLocationResult = PassengerLocationResult.loading(
        _passengerLocationResult.location,
      );
    });
    PassengerLocationResult result;
    try {
      result = await _passengerLocationService.getCurrentLocation();
    } on Object {
      result = const PassengerLocationResult.unknownError();
    } finally {
      _passengerLocationRequestInFlight = false;
    }
    if (!mounted) return;
    setState(() => _passengerLocationResult = result);
  }

  Future<void> _loadAllProgressData() async {
    await Future.wait([
      for (var index = 0; index < widget.journey.legs.length; index++)
        _loadProgressData(index),
    ]);
  }

  Future<void> _loadProgressData(int index) async {
    if (mounted) {
      setState(() {
        _progressLoading[index] = true;
        _progressErrors[index] = null;
      });
    }
    try {
      final repository =
          widget.tripProgressRepository ?? GtfsTripProgressRepository();
      final data = await repository.loadTrip(widget.journey.legs[index].tripId);
      if (!mounted) return;
      setState(() {
        final leg = widget.journey.legs[index];
        _progressCalculators[index] = JourneyProgressCalculator(
          data,
          selectedOriginStopId: leg.fromStopId,
          selectedDestinationStopId: leg.toStopId,
        );
        _progressLoading[index] = false;
        _updateProgressForLeg(index);
        _updateArrivalForLeg(index);
        _updateJourneyStage();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _progressErrors[index] = error;
        _progressLoading[index] = false;
      });
    }
  }

  Future<void> _loadMap() async {
    setState(() {
      _mapData = null;
      _mapError = null;
    });
    try {
      final data = await widget.journeyMapRepository.loadJourney(
        widget.journey.recommendation,
      );
      if (mounted) setState(() => _mapData = data);
    } on Object catch (error) {
      if (mounted) setState(() => _mapError = error);
    }
  }

  void _onControllerChanged() {
    final snapshot = _controller.snapshot;
    if (snapshot != null && !identical(snapshot, _observedSnapshot)) {
      final match = matchSelectedJourneyVehicles(
        journey: widget.journey,
        vehicles: snapshot.vehicles,
      );
      _currentByLeg = match.byLeg.map(_markerFor).toList(growable: false);
      for (var index = 0; index < _currentByLeg.length; index++) {
        final current = _currentByLeg[index];
        if (current != null) {
          _lastKnownByLeg[index] = current;
          _updateProgressForLeg(index);
        }
        _updateArrivalForLeg(index);
      }
      _updateJourneyStage();
      _observedSnapshot = snapshot;
    }
    if (mounted) setState(() {});
  }

  void _updateProgressForLeg(int index) {
    final marker = _currentByLeg[index];
    final calculator = _progressCalculators[index];
    if (marker == null || calculator == null) return;
    _progressByLeg[index] = calculator.calculate(
      vehicleCoordinate: MapCoordinate(marker.latitude, marker.longitude),
      timestamp: marker.vehicle.timestamp,
      previous: _progressByLeg[index],
    );
  }

  void _updateArrivalForLeg(int index) {
    final progress = _progressByLeg[index];
    final calculator = _progressCalculators[index];
    final marker = _currentByLeg[index];
    final nextStop = progress?.nextStop ?? _fallbackNextStop(index);
    if (marker != null &&
        progress?.availability == JourneyProgressAvailability.available &&
        progress?.busProgressMeters != null &&
        marker.vehicle.timestamp != null) {
      _movementHistoryByLeg[index].add(
        RealtimeMovementSample(
          tripId: marker.vehicle.tripId ?? '',
          vehicleId: marker.vehicle.vehicleId,
          routeProgressMeters: progress!.busProgressMeters!,
          timestamp: marker.vehicle.timestamp!,
          latitude: marker.latitude,
          longitude: marker.longitude,
        ),
      );
    }
    final nextStopProgress = calculator?.stopProgress
        .where((item) => item.stop.stopId == nextStop?.stopId)
        .firstOrNull
        ?.progressMeters;
    final scheduledArrival = _scheduledArrivalFor(index, nextStop);
    final currentInstant =
        marker?.vehicle.timestamp ?? (widget.now ?? DateTime.now)();
    final transitNow = transitServiceDateTime(currentInstant);
    final comparableNow = DateTime(
      transitNow.year,
      transitNow.month,
      transitNow.day,
      transitNow.hour,
      transitNow.minute,
      transitNow.second,
    );
    _arrivalEstimateByLeg[index] = _arrivalEstimator.estimate(
      nextStop: nextStop,
      currentProgressMeters: progress?.busProgressMeters,
      nextStopProgressMeters: nextStopProgress,
      samples: _movementHistoryByLeg[index].samples,
      currentTransitTime: comparableNow,
      scheduledArrival: scheduledArrival,
      realtimeVehicleAvailable: marker != null,
      routeProjectionReliable:
          progress?.availability == JourneyProgressAvailability.available,
      previous: _arrivalEstimateByLeg[index],
    );
  }

  DateTime? _scheduledArrivalFor(int index, TrackedTripStop? stop) {
    final seconds =
        stop?.scheduledArrivalSeconds ?? stop?.scheduledDepartureSeconds;
    if (seconds == null) return null;
    final serviceDate = widget.journey.legs[index].scheduledDeparture;
    return DateTime(
      serviceDate.year,
      serviceDate.month,
      serviceDate.day,
    ).add(Duration(seconds: seconds));
  }

  TrackedTripStop? _fallbackNextStop(int index) {
    final stops = _progressCalculators[index]?.data.stops;
    if (stops == null || stops.isEmpty) return null;
    final ordered = [...stops]
      ..sort((left, right) => left.stopSequence.compareTo(right.stopSequence));
    final fromIndex = ordered.indexWhere(
      (stop) => stop.stopId == widget.journey.legs[index].fromStopId,
    );
    if (fromIndex < 0) return null;
    return ordered[(fromIndex + 1).clamp(0, ordered.length - 1)];
  }

  void _updateJourneyStage() {
    final next = detectJourneyStage(
      journey: widget.journey,
      previous: _journeyStage,
      exactVehicleAvailableByLeg: [
        for (final marker in _currentByLeg) marker != null,
      ],
      progressByLeg: _progressByLeg,
    );
    if (next.stage == _journeyStage.stage &&
        next.activeLegIndex == _journeyStage.activeLegIndex) {
      return;
    }
    _journeyStage = next;
    if (_followsCurrentStage) _selectedLeg = next.activeLegIndex;
  }

  RealtimeVehicleMarkerData? _markerFor(RealtimeVehiclePosition? vehicle) {
    if (vehicle == null) return null;
    final markers = buildRealtimeVehicleMarkers([vehicle]);
    return markers.isEmpty ? null : markers.single;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.startPolling(fetchImmediately: true);
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _controller.stopPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _formatUpdated(DateTime? value) {
    if (value == null) return 'Not provided';
    final local = transitServiceDateTime(value);
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second ${local.hour >= 12 ? 'PM' : 'AM'}';
  }

  String get _status {
    if (_controller.snapshot == null && _controller.initialError != null) {
      return 'Unable to refresh realtime vehicle data.';
    }
    if (_controller.refreshWarning != null) {
      return _lastKnownByLeg[_selectedLeg] == null
          ? 'Unable to refresh realtime vehicle data.'
          : _controller.refreshWarning!;
    }
    if (_currentByLeg[_selectedLeg] != null) return 'Live tracking active';
    if (_lastKnownByLeg[_selectedLeg] != null) {
      return 'Live vehicle position is temporarily unavailable — showing last known position';
    }
    return 'Waiting for realtime vehicle data for this trip.';
  }

  @override
  Widget build(BuildContext context) {
    final overview = _buildOverview();
    final details = _buildDetails();
    final map = _buildMap();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Journey'),
        actions: [
          IconButton(
            key: const Key('refresh-selected-journey'),
            onPressed: _controller.isRefreshing ? null : _controller.refresh,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > constraints.maxHeight) {
              return Row(
                children: [
                  SizedBox(
                    width: constraints.maxWidth.clamp(300, 380).toDouble(),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          overview,
                          const SizedBox(height: 16),
                          details,
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: map),
                ],
              );
            }
            final mapHeight = (constraints.maxHeight * 0.48).clamp(
              300.0,
              420.0,
            );
            return CustomScrollView(
              key: const Key('selected-tracker-scroll'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  sliver: SliverToBoxAdapter(child: overview),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: mapHeight, child: map),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(child: details),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOverview() {
    final routeLabel = widget.journey.legs
        .map((leg) => leg.routeName)
        .join(' → ');
    return Column(
      key: const Key('selected-journey-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(routeLabel, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          '${widget.journey.originStopName} → '
          '${widget.journey.destinationStopName}',
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            if (widget.journey.transferStopName case final transfer?)
              Text('Transfer · $transfer'),
            Text(
              'Scheduled · ${_formatTime(widget.journey.scheduledDeparture)}'
              ' → ${_formatTime(widget.journey.scheduledArrival)}',
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildJourneyStageSummary(),
        if (widget.journey.isTransfer) ...[
          const SizedBox(height: 10),
          SegmentedButton<int>(
            key: const Key('selected-leg-selector'),
            segments: [
              for (var index = 0; index < widget.journey.legs.length; index++)
                ButtonSegment(
                  value: index,
                  label: Text(
                    'Leg ${index + 1} · ${widget.journey.legs[index].routeName}'
                    '${index == _journeyStage.activeLegIndex ? ' · Current' : ''}',
                  ),
                ),
            ],
            selected: {_selectedLeg},
            onSelectionChanged: (selection) {
              setState(() {
                _selectedLeg = selection.single;
                _followsCurrentStage =
                    _selectedLeg == _journeyStage.activeLegIndex;
              });
            },
          ),
          if (!_followsCurrentStage)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('follow-current-stage'),
                onPressed: () {
                  setState(() {
                    _selectedLeg = _journeyStage.activeLegIndex;
                    _followsCurrentStage = true;
                  });
                },
                icon: const Icon(Icons.near_me),
                label: const Text('Follow Current Stage'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildDetails() {
    final activeLeg = widget.journey.legs[_selectedLeg];
    final current = _currentByLeg[_selectedLeg];
    final displayed = current ?? _lastKnownByLeg[_selectedLeg];
    return Column(
      key: const Key('selected-journey-details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.journey.isTransfer)
          Text(
            'Viewing ${activeLeg.routeName}'
            '${_selectedLeg == _journeyStage.activeLegIndex ? ' · Current leg' : ''}',
          ),
        const SizedBox(height: 6),
        Text(
          _status,
          key: const Key('selected-tracking-status'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (_controller.snapshot != null)
          Text(
            'API checked ${_formatUpdated(_controller.lastSuccessfulRefreshAt)}',
            key: const Key('selected-live-update-indicator'),
          ),
        if (_controller.isRefreshing && _controller.snapshot != null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: LinearProgressIndicator(key: Key('selected-refreshing')),
          ),
        if (_controller.isInitialLoading) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (displayed != null) ...[
          const SizedBox(height: 8),
          Row(
            key: const Key('live-bus-summary'),
            children: [
              const Icon(Icons.directions_bus, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_displayValue(displayed.vehicle.vehicleId)} · '
                  'Updated ${_formatUpdated(displayed.vehicle.timestamp)}'
                  '${current == null ? ' · Last known' : ''}',
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _buildProgressSummary(currentIsLive: current != null),
        const SizedBox(height: 10),
        _buildArrivalSummary(),
        const SizedBox(height: 12),
        _buildPassengerLocationSummary(activeLeg),
      ],
    );
  }

  Widget _buildJourneyStageSummary() {
    final active = widget.journey.legs[_journeyStage.activeLegIndex];
    final transfer = widget.journey.transferStopName;
    final destination = widget.journey.destinationStopName;
    final activeNextStop =
        _progressByLeg[_journeyStage.activeLegIndex]?.nextStop;
    final (primary, secondary) = switch (_journeyStage.stage) {
      JourneyStage.waitingForFirstLeg => (
        'Waiting to board ${active.routeName}',
        'At ${active.fromStopName}',
      ),
      JourneyStage.trackingFirstLeg => (
        'Tracking ${active.routeName}',
        'Next: ${activeNextStop?.stopName ?? (widget.journey.isTransfer ? transfer : destination)}',
      ),
      JourneyStage.approachingTransfer => (
        'Approaching transfer at $transfer',
        'Next bus: ${widget.journey.legs[1].routeName}',
      ),
      JourneyStage.waitingForSecondLeg => (
        'Transfer at $transfer',
        'Waiting for ${widget.journey.legs[1].routeName}',
      ),
      JourneyStage.trackingSecondLeg => (
        'Tracking ${active.routeName}',
        'Next: ${activeNextStop?.stopName ?? destination}',
      ),
      JourneyStage.approachingDestination => (
        'Approaching $destination',
        'Stay on ${active.routeName}',
      ),
      JourneyStage.completed => (
        'Arrived at $destination',
        'Journey completed',
      ),
    };
    return Card(
      key: const Key('current-journey-stage'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Journey',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(primary, style: Theme.of(context).textTheme.titleMedium),
            Text(secondary),
          ],
        ),
      ),
    );
  }

  Widget _buildPassengerLocationSummary(SelectedJourneyLeg activeLeg) {
    final result = _passengerLocationResult;
    final location = result.location;
    final boardingCoordinate = _boardingStopCoordinate(activeLeg);
    final distance = location == null || boardingCoordinate == null
        ? null
        : passengerDistanceToStopMeters(location, boardingCoordinate);
    return Column(
      key: const Key('passenger-location-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Your Location',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Spacer(),
            TextButton.icon(
              key: const Key('refresh-passenger-location'),
              onPressed: _passengerLocationRequestInFlight
                  ? null
                  : _refreshPassengerLocation,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        Text('Boarding stop: ${activeLeg.fromStopName}'),
        const SizedBox(height: 4),
        switch (result.status) {
          PassengerLocationStatus.notRequested => const Text(
            'Location permission is required.',
          ),
          PassengerLocationStatus.loading => const Row(
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Expanded(child: Text('Getting your location...')),
            ],
          ),
          PassengerLocationStatus.permissionDenied => const Text(
            'Location permission was denied.',
          ),
          PassengerLocationStatus.permissionDeniedForever => const Text(
            'Location permission is permanently denied.',
          ),
          PassengerLocationStatus.servicesDisabled => const Text(
            'Location services are disabled.',
          ),
          PassengerLocationStatus.positionTimeout => const Text(
            'Location request timed out. Please send a location from the '
            'emulator or try again.',
          ),
          PassengerLocationStatus.noLastKnownPosition => const Text(
            'Location timed out and no previous location is available.',
          ),
          PassengerLocationStatus.providerUnavailable => const Text(
            'The Android location provider is currently unavailable.',
          ),
          PassengerLocationStatus.platformError => const Text(
            'Android could not provide a location. Please check the emulator '
            'location controls.',
          ),
          PassengerLocationStatus.unknownError => const Text(
            'An unexpected location error occurred.',
          ),
          PassengerLocationStatus.available => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (distance != null)
                Text(
                  'Straight-line distance: approximately '
                  '${formatApproximateDistance(distance)} from boarding stop',
                  key: const Key('boarding-stop-distance'),
                )
              else
                const Text('Boarding-stop coordinates are unavailable.'),
              if (result.isLastKnown)
                const Text(
                  'Using last-known location; it may be stale.',
                  key: Key('last-known-passenger-location'),
                ),
              if (location != null &&
                  hasPoorPassengerLocationAccuracy(location))
                const Text('Approximate location (limited GPS accuracy)'),
            ],
          ),
        },
        if (result.status == PassengerLocationStatus.permissionDeniedForever)
          TextButton(
            key: const Key('open-location-app-settings'),
            onPressed: _passengerLocationService.openAppSettings,
            child: const Text('Open App Settings'),
          ),
        if (result.status == PassengerLocationStatus.servicesDisabled)
          TextButton(
            key: const Key('open-location-settings'),
            onPressed: _passengerLocationService.openLocationSettings,
            child: const Text('Open Location Settings'),
          ),
      ],
    );
  }

  MapCoordinate? _boardingStopCoordinate(SelectedJourneyLeg activeLeg) {
    final stops = _progressCalculators[_selectedLeg]?.data.stops;
    if (stops == null) return null;
    for (final stop in stops) {
      if (stop.stopId == activeLeg.fromStopId) return stop.coordinate;
    }
    return null;
  }

  Widget _buildProgressSummary({required bool currentIsLive}) {
    if (_progressLoading[_selectedLeg]) {
      return const Column(
        key: Key('route-progress-loading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Route progress'),
          SizedBox(height: 8),
          LinearProgressIndicator(),
        ],
      );
    }
    if (_progressErrors[_selectedLeg] != null) {
      return Column(
        key: const Key('route-progress-error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Unable to load route progress information.'),
          TextButton(
            key: const Key('retry-route-progress'),
            onPressed: () => _loadProgressData(_selectedLeg),
            child: const Text('Retry progress'),
          ),
        ],
      );
    }
    final progress = _progressByLeg[_selectedLeg];
    if (progress == null) {
      return const Text(
        'Live route progress will appear when this trip has realtime vehicle data.',
        key: Key('route-progress-waiting'),
      );
    }
    if (progress.availability == JourneyProgressAvailability.shapeUnavailable) {
      return const Text(
        'Route shape is unavailable, so live progress cannot be estimated.',
        key: Key('route-progress-shape-unavailable'),
      );
    }
    if (progress.availability == JourneyProgressAvailability.offRoute) {
      return const Text(
        'Live vehicle position is temporarily outside the expected route.',
        key: Key('route-progress-off-route'),
      );
    }
    final passedExpanded = _expandedPassedLegs.contains(_selectedLeg);
    final upcomingExpanded = _expandedUpcomingLegs.contains(_selectedLeg);
    final completed = passedExpanded
        ? progress.completedStops
        : progress.completedStops.reversed.take(2).toList().reversed.toList();
    final upcoming = upcomingExpanded
        ? progress.upcomingStops
        : progress.upcomingStops.take(3).toList();
    return Column(
      key: const Key('route-progress-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Route progress',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Spacer(),
            if (progress.progressFraction case final fraction?)
              Text('${(fraction * 100).round()}%'),
          ],
        ),
        if (progress.progressFraction case final fraction?) ...[
          const SizedBox(height: 4),
          LinearProgressIndicator(value: fraction),
        ],
        if (!currentIsLive)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Last known route progress'),
          ),
        if (progress.nearestStop case final nearest?) ...[
          const SizedBox(height: 8),
          Text('Near: ${nearest.stopName}'),
        ],
        if (progress.nextStop case final next?)
          Text('Next stop: ${next.stopName}'),
        if (completed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Passed', style: Theme.of(context).textTheme.labelMedium),
          for (final stop in completed) Text('✓ ${stop.stopName}'),
          if (progress.completedStops.length > 2)
            TextButton(
              key: const Key('toggle-passed-stops'),
              onPressed: () {
                setState(() {
                  if (passedExpanded) {
                    _expandedPassedLegs.remove(_selectedLeg);
                  } else {
                    _expandedPassedLegs.add(_selectedLeg);
                  }
                });
              },
              child: Text(
                passedExpanded ? 'Hide passed stops' : 'View passed stops',
              ),
            ),
        ],
        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Upcoming Stops',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          for (var index = 0; index < upcoming.length; index++)
            Text('${index + 1}. ${upcoming[index].stopName}'),
          if (progress.upcomingStops.length > 3)
            TextButton(
              key: const Key('toggle-upcoming-stops'),
              onPressed: () {
                setState(() {
                  if (upcomingExpanded) {
                    _expandedUpcomingLegs.remove(_selectedLeg);
                  } else {
                    _expandedUpcomingLegs.add(_selectedLeg);
                  }
                });
              },
              child: Text(
                upcomingExpanded
                    ? 'Show fewer upcoming stops'
                    : 'View all upcoming stops',
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildArrivalSummary() {
    if (_journeyStage.stage == JourneyStage.completed) {
      return const Text('Arrived', key: Key('arrival-estimate-completed'));
    }
    final estimate = _arrivalEstimateByLeg[_selectedLeg];
    final nextStop =
        estimate?.nextStop ?? _progressByLeg[_selectedLeg]?.nextStop;
    if (nextStop == null) {
      return const Text(
        'Arrival estimate unavailable',
        key: Key('arrival-estimate-unavailable'),
      );
    }
    final isDestination =
        nextStop.stopId == widget.journey.legs[_selectedLeg].toStopId;
    final scheduled = estimate?.scheduledArrival;
    return Column(
      key: const Key('arrival-estimate-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isDestination ? 'Destination' : 'Next Stop',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Text(nextStop.stopName),
        const SizedBox(height: 4),
        if (estimate?.source == ArrivalEstimateSource.realtimeAdjusted &&
            estimate?.estimatedArrivalDuration != null)
          Text(
            'Estimated arrival ${formatApproximateArrivalDuration(estimate!.estimatedArrivalDuration!)}',
            key: const Key('realtime-arrival-estimate'),
            style: Theme.of(context).textTheme.titleMedium,
          )
        else
          const Text(
            'Live estimate unavailable',
            key: Key('live-arrival-unavailable'),
          ),
        if (scheduled != null)
          Text(
            'Scheduled arrival ${_formatTime(scheduled)}',
            key: const Key('scheduled-next-stop-arrival'),
          ),
        if (estimate?.generatedFromVehicleTimestamp case final updated?)
          Text('Updated ${_formatUpdated(updated)}'),
      ],
    );
  }

  Widget _buildMap() {
    final displayed =
        _currentByLeg[_selectedLeg] ?? _lastKnownByLeg[_selectedLeg];
    final markers = displayed == null
        ? const <RealtimeVehicleMarkerData>[]
        : [displayed];
    if (_mapError != null) {
      final fallbackMap =
          markers.isEmpty && _passengerLocationResult.location == null
          ? const SizedBox.shrink()
          : widget.mapBuilder?.call(
                  const JourneyMapData(stops: [], legs: []),
                  markers,
                  _passengerLocationResult.location,
                ) ??
                JourneyRouteMap(
                  key: _journeyMapKey,
                  data: const JourneyMapData(stops: [], legs: []),
                  realtimeMarkers: markers,
                  passengerLocation: _passengerLocationResult.location,
                  activeLegIndex: _selectedLeg,
                  showCameraControls: true,
                  busLabel: widget.journey.legs[_selectedLeg].routeName,
                  displayMode: _mapDisplayMode,
                  onDisplayModeChanged: (mode) {
                    if (mounted) setState(() => _mapDisplayMode = mode);
                  },
                );
      return Stack(
        children: [
          Positioned.fill(child: fallbackMap),
          Center(
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Planned route is currently unavailable.'),
                    TextButton(
                      key: const Key('retry-selected-route'),
                      onPressed: _loadMap,
                      child: const Text('Retry route'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    final data = _mapData;
    if (data == null) return const Center(child: CircularProgressIndicator());
    return widget.mapBuilder?.call(
          data,
          markers,
          _passengerLocationResult.location,
        ) ??
        JourneyRouteMap(
          key: _journeyMapKey,
          data: data,
          realtimeMarkers: markers,
          passengerLocation: _passengerLocationResult.location,
          activeLegIndex: _selectedLeg,
          showCameraControls: true,
          busLabel: widget.journey.legs[_selectedLeg].routeName,
          displayMode: _mapDisplayMode,
          onDisplayModeChanged: (mode) {
            if (mounted) setState(() => _mapDisplayMode = mode);
          },
        );
  }

  String _displayValue(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : 'Not provided';
}
