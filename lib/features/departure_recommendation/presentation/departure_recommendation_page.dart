import 'dart:async';
import 'package:government_transit_collector/features/journey_reminders/journey_reminder.dart';
import 'package:government_transit_collector/features/journey_reminders/reminder_controller.dart';
import 'package:government_transit_collector/features/journey_reminders/reminder_widgets.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/nearby_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/saved_journey_repository.dart';
import 'package:government_transit_collector/features/passenger_profile/data/travel_preferences_repository.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location_service.dart';

import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback_repository.dart';
import 'package:government_transit_collector/features/bus_feedback/data/feedback_reference_repository.dart';
import 'package:government_transit_collector/features/bus_feedback/presentation/bus_feedback_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/direct_trip_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_search_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recommendation_realtime_availability.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/transfer_journey_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_validation.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/stop_selection_page.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/journey_map/presentation/route_map_page.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/selected_journey_tracker_page.dart';

typedef SelectedJourneyTrackerBuilder =
    Widget Function(
      SelectedJourneyTracking journey,
      JourneyMapRepository journeyMapRepository,
    );

class _SaveJourneyDialog extends StatefulWidget {
  const _SaveJourneyDialog({required this.origin, required this.destination});
  final DepartureStop origin;
  final DepartureStop destination;
  @override
  State<_SaveJourneyDialog> createState() => _SaveJourneyDialogState();
}

class _SaveJourneyDialogState extends State<_SaveJourneyDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save Journey'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${widget.origin.name} → ${widget.destination.name}'),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 80,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Journey Name'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

class DepartureRecommendationPage extends StatefulWidget {
  const DepartureRecommendationPage({
    required this.stopRepository,
    required this.tripRepository,
    required this.transferRepository,
    required this.timetableRepository,
    required this.recentSearchRepository,
    this.initialJourney,
    this.initialRecentSearch,
    this.savedJourneyRepository,
    this.preferencesRepository,
    this.nearbyStopRepository,
    this.passengerLocationService,
    this.journeyMapRepository,
    this.selectedJourneyTrackerBuilder,
    this.initialDateTime,
    this.now,
    this.realtimeRepository,
    this.feedbackRepository,
    this.feedbackReferenceRepository,
    this.reminderController,
    super.key,
  });

  final DepartureStopRepository stopRepository;
  final ReminderController? reminderController;
  final DirectTripRepository tripRepository;
  final TransferJourneyRepository transferRepository;
  final TimetableRecommendationRepository timetableRepository;
  final RecentSearchRepository recentSearchRepository;
  final SavedJourney? initialJourney;
  final RecentJourneySearch? initialRecentSearch;
  final SavedJourneyRepository? savedJourneyRepository;
  final TravelPreferencesRepository? preferencesRepository;
  final NearbyStopRepository? nearbyStopRepository;
  final PassengerLocationService? passengerLocationService;

  final JourneyMapRepository? journeyMapRepository;
  final SelectedJourneyTrackerBuilder? selectedJourneyTrackerBuilder;

  final DateTime? initialDateTime;
  final DateTime Function()? now;

  final RealtimeVehicleRepository? realtimeRepository;

  final BusFeedbackRepository? feedbackRepository;

  final FeedbackReferenceRepository? feedbackReferenceRepository;

  @override
  State<DepartureRecommendationPage> createState() =>
      _DepartureRecommendationPageState();
}

class _DepartureRecommendationPageState
    extends State<DepartureRecommendationPage> {
  DepartureStop? _origin;
  DepartureStop? _destination;

  String? _validationMessage;
  String? _directError;
  String? _transferError;
  String? _timetableError;

  List<JourneyRecommendation>? _recommendations;

  bool? _routeStructureFound;
  bool _searching = false;
  bool _restoringRecent = false;
  bool get _inputsBusy => _searching || _restoringRecent;
  final _scrollController = ScrollController();

  List<RecentJourneySearch>? _recentSearches;
  String? _historyError;

  late DateTime _travelDate;
  late TimeOfDay _travelTime;

  Map<String, RecommendationRealtimeAvailability> _liveAvailability = const {};

  bool _liveStatusLoading = false;
  bool _liveStatusUnavailable = false;

  int _availabilityRequest = 0;
  late final ReminderController? _reminders =
      widget.reminderController ?? sharedReminderController;

  void _remindersChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _reminders?.removeListener(_remindersChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _reminders?.addListener(_remindersChanged);
    _origin = widget.initialJourney?.origin;
    _destination = widget.initialJourney?.destination;

    final initial =
        widget.initialDateTime ??
        currentTransitServiceDateTime(now: widget.now);

    _travelDate = DateTime(initial.year, initial.month, initial.day);

    _travelTime = TimeOfDay.fromDateTime(initial);

    _loadRecentSearches();
    final recent = widget.initialRecentSearch;
    if (recent != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreRecentSearch(recent);
      });
    }
  }

  Future<void> _loadRecentSearches() async {
    setState(() {
      _recentSearches = null;
      _historyError = null;
    });

    try {
      final searches = await widget.recentSearchRepository.getRecentSearches();

      if (!mounted) return;

      setState(() {
        _recentSearches = searches;
      });
    } on Object {
      if (!mounted) return;

      setState(() {
        _historyError = 'Unable to load recent searches.';
      });
    }
  }

  Future<void> _selectOrigin({bool nearby = false}) async {
    var radius = 1000;
    try {
      radius = await widget.preferencesRepository?.loadRadius() ?? 1000;
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load preferred radius. Using 1 km.'),
          ),
        );
      }
    }
    if (!mounted) return;
    final stop = await Navigator.of(context).push<DepartureStop>(
      MaterialPageRoute(
        builder: (_) => StopSelectionPage(
          title: 'Select origin stop',
          allowNearby: true,
          startNearby: nearby,
          initialRadius: radius,
          nearbyRepository: widget.nearbyStopRepository,
          locationService: widget.passengerLocationService,
          repository: widget.stopRepository,
          excludedStopId: _destination?.id,
        ),
      ),
    );

    if (!mounted || stop == null) return;

    setState(() {
      _origin = stop;
      _resetSearchState();
    });
  }

  Future<void> _selectDestination() async {
    final stop = await Navigator.of(context).push<DepartureStop>(
      MaterialPageRoute(
        builder: (_) => StopSelectionPage(
          title: 'Select destination stop',
          repository: widget.stopRepository,
          excludedStopId: _origin?.id,
        ),
      ),
    );

    if (!mounted || stop == null) return;

    setState(() {
      _destination = stop;
      _resetSearchState();
    });
  }

  bool _savingJourney = false;
  Future<void> _saveJourney() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null || _savingJourney) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _SaveJourneyDialog(origin: origin, destination: destination),
    );
    if (!mounted || name == null) return;
    setState(() => _savingJourney = true);
    try {
      await (widget.savedJourneyRepository ?? SupabaseSavedJourneyRepository())
          .save(name, origin, destination);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Journey saved. View it in My Travel Profile.'),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is SavedJourneyException
                  ? error.message
                  : 'Unable to save journey. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingJourney = false);
    }
  }

  void _resetSearchState() {
    _availabilityRequest++;

    _validationMessage = null;

    _directError = null;
    _transferError = null;
    _timetableError = null;

    _recommendations = null;
    _routeStructureFound = null;

    _liveAvailability = const {};
    _liveStatusLoading = false;
    _liveStatusUnavailable = false;
  }

  Future<void> _selectTravelDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _travelDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (!mounted || selected == null) return;

    setState(() {
      _travelDate = selected;
      _resetSearchState();
    });
  }

  Future<void> _selectTravelTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _travelTime,
    );

    if (!mounted || selected == null) return;

    setState(() {
      _travelTime = selected;
      _resetSearchState();
    });
  }

  Future<void> _search() async {
    if (_inputsBusy) return;

    final validationMessage = validateDepartureStops(
      origin: _origin,
      destination: _destination,
    );

    if (validationMessage != null) {
      setState(() {
        _validationMessage = validationMessage;

        _directError = null;
        _transferError = null;
        _timetableError = null;

        _recommendations = null;
        _routeStructureFound = null;
      });

      return;
    }

    final origin = _origin!;
    final destination = _destination!;

    setState(() {
      _searching = true;

      _validationMessage = null;

      _directError = null;
      _transferError = null;
      _timetableError = null;

      _recommendations = null;
      _routeStructureFound = null;
    });

    final directFuture = widget.tripRepository.findDirectRoutes(
      originStopId: origin.id,
      destinationStopId: destination.id,
    );

    final transferFuture = widget.transferRepository.findOneTransferJourneys(
      originStopId: origin.id,
      destinationStopId: destination.id,
    );

    List<DirectRouteResult>? directResults;
    List<OneTransferJourneyResult>? transferResults;

    String? directError;
    String? transferError;

    try {
      directResults = await directFuture;
    } on DirectTripReadException catch (error) {
      directError = error.message;
    } on Object {
      directError = 'Unable to find direct routes.';
    }

    try {
      transferResults = await transferFuture;
    } on TransferJourneyReadException catch (error) {
      transferError = error.message;
    } on Object {
      transferError = 'Unable to find one-transfer routes.';
    }

    final routeStructureFound =
        directResults?.isNotEmpty == true ||
        transferResults?.isNotEmpty == true;

    List<JourneyRecommendation>? recommendations;

    String? timetableError;

    if (routeStructureFound) {
      try {
        recommendations = await widget.timetableRepository.findRecommendations(
          originStopId: origin.id,
          destinationStopId: destination.id,
          travelDate: _travelDate,
          travelTimeSeconds: timeOfDayToServiceSeconds(_travelTime),
          directRoutes: directResults ?? const [],
          transferJourneys: transferResults ?? const [],
        );
      } on TimetableReadException catch (error) {
        timetableError = error.message;
      } on Object {
        timetableError = 'Unable to load scheduled departures.';
      }
    }

    if (!mounted) return;

    setState(() {
      _directError = directError;
      _transferError = transferError;
      _timetableError = timetableError;

      _recommendations = recommendations;
      _routeStructureFound = routeStructureFound;

      _searching = false;

      _liveAvailability = const {};
      _liveStatusUnavailable = false;

      _liveStatusLoading = recommendations?.isNotEmpty == true;
    });

    if (recommendations?.isNotEmpty == true) {
      final request = ++_availabilityRequest;

      unawaited(_loadRealtimeAvailability(recommendations!, request));
    }

    if (directError == null || transferError == null) {
      await _saveRecentSearch(origin, destination);
    }
  }

  Future<void> _loadRealtimeAvailability(
    List<JourneyRecommendation> recommendations,
    int request,
  ) async {
    try {
      final snapshot =
          await (widget.realtimeRepository ??
                  DataGovMyRealtimeVehicleRepository())
              .fetchVehiclePositions();

      if (!mounted || request != _availabilityRequest) {
        return;
      }

      setState(() {
        _liveAvailability = evaluateRecommendationRealtimeAvailability(
          recommendations: recommendations,
          vehicles: snapshot.vehicles,
        );

        _liveStatusLoading = false;
        _liveStatusUnavailable = false;
      });
    } on Object {
      if (!mounted || request != _availabilityRequest) {
        return;
      }

      setState(() {
        _liveAvailability = const {};

        _liveStatusLoading = false;
        _liveStatusUnavailable = true;
      });
    }
  }

  Future<void> _saveRecentSearch(
    DepartureStop origin,
    DepartureStop destination,
  ) async {
    try {
      await widget.recentSearchRepository.saveRecentSearch(
        RecentJourneySearch(
          originStopId: origin.id,
          originStopName: origin.name,
          destinationStopId: destination.id,
          destinationStopName: destination.name,
          searchedAt: DateTime.now().toUtc(),
        ),
      );

      await _loadRecentSearches();
    } on Object {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Route search completed, but recent history was not saved.',
          ),
        ),
      );
    }
  }

  void _reverseJourney() {
    if (_inputsBusy || (_origin == null && _destination == null)) return;
    setState(() {
      final origin = _origin;
      _origin = _destination;
      _destination = origin;
      _resetSearchState();
    });
  }

  Future<void> _restoreRecentSearch(RecentJourneySearch search) async {
    if (_inputsBusy) return;
    setState(() => _restoringRecent = true);
    try {
      final stops = await Future.wait([
        widget.stopRepository.getStopById(search.originStopId),
        widget.stopRepository.getStopById(search.destinationStopId),
      ]);
      if (!mounted) return;
      if (stops.any((stop) => stop == null)) {
        setState(
          () => _validationMessage =
              'A previous stop is no longer available. Please select your stops again.',
        );
        return;
      }
      final fresh = currentTransitServiceDateTime(now: widget.now);
      setState(() {
        _origin = stops[0];
        _destination = stops[1];
        _travelDate = DateTime(fresh.year, fresh.month, fresh.day);
        _travelTime = TimeOfDay.fromDateTime(fresh);
        _resetSearchState();
      });
    } on Object {
      if (mounted) {
        setState(
          () => _validationMessage =
              'Unable to load the previous stops. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _restoringRecent = false);
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
    }
  }

  Future<void> _clearRecentSearches() async {
    try {
      await widget.recentSearchRepository.clearRecentSearches();

      if (!mounted) return;

      setState(() {
        _recentSearches = const [];
        _historyError = null;
      });
    } on Object {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to clear recent searches.')),
      );
    }
  }

  BusFeedbackRepository _feedbackRepository() {
    return widget.feedbackRepository ?? SupabaseBusFeedbackRepository();
  }

  FeedbackReferenceRepository _feedbackReferenceRepository() {
    return widget.feedbackReferenceRepository ??
        SupabaseFeedbackReferenceRepository();
  }

  String _feedbackRouteLabel(String routeId, String? shortName) {
    final trimmed = shortName?.trim();

    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }

    return routeId;
  }

  void _reportBusProblem(JourneyRecommendation recommendation) {
    final options = <FeedbackJourneyOption>[];

    if (recommendation is DirectJourneyRecommendation) {
      options.add(
        FeedbackJourneyOption(
          label: 'Direct Bus',
          routeId: recommendation.routeId,
          routeLabel: _feedbackRouteLabel(
            recommendation.routeId,
            recommendation.routeShortName,
          ),
          tripId: recommendation.tripId,
          boardingStop: FeedbackStop(
            id: recommendation.originStopId,
            name: _origin?.name ?? recommendation.originStopId,
          ),
          departureSeconds: recommendation.departureSeconds,
        ),
      );
    }

    if (recommendation is TransferJourneyRecommendation) {
      options.add(
        FeedbackJourneyOption(
          label: 'Leg 1',
          routeId: recommendation.firstRouteId,
          routeLabel: _feedbackRouteLabel(
            recommendation.firstRouteId,
            recommendation.firstRouteShortName,
          ),
          tripId: recommendation.firstTripId,
          boardingStop: FeedbackStop(
            id: recommendation.originStopId,
            name: _origin?.name ?? recommendation.originStopId,
          ),
          departureSeconds: recommendation.departureSeconds,
        ),
      );

      options.add(
        FeedbackJourneyOption(
          label: 'Leg 2',
          routeId: recommendation.secondRouteId,
          routeLabel: _feedbackRouteLabel(
            recommendation.secondRouteId,
            recommendation.secondRouteShortName,
          ),
          tripId: recommendation.secondTripId,
          boardingStop: FeedbackStop(
            id: recommendation.transferStopId,
            name: recommendation.transferStopName,
          ),
          departureSeconds: recommendation.secondDepartureSeconds,
        ),
      );
    }

    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to identify the journey for feedback.'),
        ),
      );

      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BusFeedbackPage(
          repository: _feedbackRepository(),
          referenceRepository: _feedbackReferenceRepository(),
          journeyOptions: options,
          travelDate: _travelDate,
          now: widget.now,
        ),
      ),
    );
  }

  void _openGeneralFeedback() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BusFeedbackPage(
          repository: _feedbackRepository(),
          referenceRepository: _feedbackReferenceRepository(),
          now: widget.now,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Departure Recommendation')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth >= 700 ? 32.0 : 16.0;

            return SingleChildScrollView(
              key: const Key('departure-page-scroll'),
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Where would you like to go?',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),

                      const SizedBox(height: 8),

                      const Text('Select an origin and destination stop.'),

                      const SizedBox(height: 24),

                      _buildStopFields(constraints.maxWidth),
                      TextButton.icon(
                        onPressed: _inputsBusy
                            ? null
                            : () => _selectOrigin(nearby: true),
                        icon: const Icon(Icons.my_location),
                        label: const Text('Use My Current Location'),
                      ),
                      if (_origin != null &&
                          _destination != null &&
                          _origin!.id != _destination!.id)
                        TextButton.icon(
                          onPressed: _savingJourney ? null : _saveJourney,
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: Text(
                            _savingJourney ? 'Saving journey…' : 'Save Journey',
                          ),
                        ),

                      const SizedBox(height: 12),

                      _buildTravelFields(constraints.maxWidth),
                      if (_restoringRecent) const LinearProgressIndicator(),

                      if (_validationMessage != null) ...[
                        const SizedBox(height: 12),

                        Text(
                          _validationMessage!,
                          key: const Key('validation-message'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      FilledButton.icon(
                        key: const Key('journey-search-button'),
                        onPressed: _inputsBusy ? null : _search,
                        icon: _searching
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search),
                        label: Text(_searching ? 'Searching...' : 'Search'),
                      ),

                      const SizedBox(height: 28),

                      _buildResults(),

                      const SizedBox(height: 28),

                      _buildRecentSearches(),

                      const SizedBox(height: 28),

                      _buildFeedbackSection(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStopFields(double width) {
    final origin = _StopField(
      key: const Key('origin-field'),
      label: 'Origin / From stop',
      icon: Icons.trip_origin,
      stop: _origin,
      onTap: _inputsBusy ? null : _selectOrigin,
    );

    final destination = _StopField(
      key: const Key('destination-field'),
      label: 'Destination / To stop',
      icon: Icons.location_on_outlined,
      stop: _destination,
      onTap: _inputsBusy ? null : _selectDestination,
    );

    final reverse = IconButton(
      tooltip: 'Reverse journey',
      onPressed: _inputsBusy ? null : _reverseJourney,
      icon: Icon(width >= 700 ? Icons.swap_horiz : Icons.swap_vert),
    );

    if (width >= 700) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: origin),

          reverse,

          Expanded(child: destination),
        ],
      );
    }

    return Column(children: [origin, reverse, destination]);
  }

  Widget _buildTravelFields(double width) {
    final localizations = MaterialLocalizations.of(context);

    final date = _PickerField(
      key: const Key('travel-date-field'),
      label: 'Travel Date',
      value: localizations.formatMediumDate(_travelDate),
      icon: Icons.calendar_today_outlined,
      onTap: _inputsBusy ? null : _selectTravelDate,
    );

    final time = _PickerField(
      key: const Key('travel-time-field'),
      label: 'Travel Time',
      value: localizations.formatTimeOfDay(_travelTime),
      icon: Icons.schedule,
      onTap: _inputsBusy ? null : _selectTravelTime,
    );

    if (width >= 700) {
      return Row(
        children: [
          Expanded(child: date),

          const SizedBox(width: 16),

          Expanded(child: time),
        ],
      );
    }

    return Column(children: [date, const SizedBox(height: 12), time]);
  }

  Widget _buildResults() {
    if (_searching) {
      return const _SectionMessage(
        key: Key('route-loading'),
        icon: Icons.route,
        message: 'Finding scheduled journeys...',
        showProgress: true,
      );
    }

    if (_routeStructureFound == null &&
        _directError == null &&
        _transferError == null &&
        _timetableError == null) {
      return const SizedBox.shrink();
    }

    if (_timetableError != null) {
      return _SectionMessage(
        key: const Key('timetable-error'),
        icon: Icons.error_outline,
        message: _timetableError!,
        actionLabel: 'Retry',
        onAction: _search,
      );
    }

    if (_routeStructureFound == false) {
      if (_directError != null || _transferError != null) {
        return _SectionMessage(
          key: const Key('route-error'),
          icon: Icons.error_outline,
          message: _directError ?? _transferError!,
          actionLabel: 'Retry',
          onAction: _search,
        );
      }

      return const _SectionMessage(
        key: Key('no-journeys'),
        icon: Icons.route_outlined,
        message:
            'No direct or one-transfer journey was found between these stops.',
      );
    }

    final recommendations = _recommendations ?? const [];

    if (recommendations.isEmpty) {
      return const _SectionMessage(
        key: Key('no-upcoming-departures'),
        icon: Icons.event_busy_outlined,
        message:
            'No upcoming departure was found for the selected date and time.',
      );
    }

    return Column(
      key: const Key('journey-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recommended Departures',
          style: Theme.of(context).textTheme.titleLarge,
        ),

        const SizedBox(height: 12),

        ...recommendations.map(
          (recommendation) => _RecommendationCard(
            reminders: _reminders,
            now: widget.now,
            recommendation: recommendation,
            originStopName: _origin!.name,
            destinationStopName: _destination!.name,
            travelDate: _travelDate,
            journeyMapRepository:
                widget.journeyMapRepository ?? GtfsJourneyMapRepository(),
            selectedJourneyTrackerBuilder: widget.selectedJourneyTrackerBuilder,
            liveAvailability:
                _liveAvailability[recommendationAvailabilityKey(
                  recommendation,
                )],
            liveStatusLoading: _liveStatusLoading,
            liveStatusUnavailable: _liveStatusUnavailable,
            onReportProblem: () {
              _reportBusProblem(recommendation);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSearches() {
    return Column(
      key: const Key('recent-searches-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Searches',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),

            if (_recentSearches?.isNotEmpty == true)
              TextButton(
                key: const Key('clear-recent-searches'),
                onPressed: _clearRecentSearches,
                child: const Text('Clear'),
              ),
          ],
        ),

        const SizedBox(height: 8),

        if (_historyError != null)
          _SectionMessage(
            icon: Icons.error_outline,
            message: _historyError!,
            actionLabel: 'Retry',
            onAction: _loadRecentSearches,
          )
        else if (_recentSearches == null)
          const Center(child: CircularProgressIndicator())
        else if (_recentSearches!.isEmpty)
          const Text('No recent searches yet.')
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: _recentSearches!
                  .map(
                    (search) => ListTile(
                      key: Key(
                        'recent-${search.originStopId}-${search.destinationStopId}',
                      ),
                      leading: const Icon(Icons.history),
                      title: Text(
                        '${search.originStopName} → ${search.destinationStopName}',
                      ),
                      trailing: TextButton(
                        onPressed: _inputsBusy
                            ? null
                            : () => _restoreRecentSearch(search),
                        child: const Text('Search Again'),
                      ),
                      onTap: _inputsBusy
                          ? null
                          : () => _restoreRecentSearch(search),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }

  Widget _buildFeedbackSection() {
    return Card(
      key: const Key('general-feedback-section'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.report_problem_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    'Report a Transit Issue',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            const Text(
              'Report a problem with a previous bus journey, route, bus stop, or walking distance.',
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                key: const Key('general-feedback-button'),
                onPressed: _openGeneralFeedback,
                icon: const Icon(Icons.feedback_outlined),
                label: const Text('Report Bus / Stop Issue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.originStopName,
    required this.destinationStopName,
    required this.travelDate,
    required this.journeyMapRepository,
    required this.liveAvailability,
    required this.liveStatusLoading,
    required this.liveStatusUnavailable,
    required this.onReportProblem,
    this.reminders,
    this.now,
    this.selectedJourneyTrackerBuilder,
  });

  final JourneyRecommendation recommendation;
  final ReminderController? reminders;
  final DateTime Function()? now;

  final String originStopName;

  final String destinationStopName;

  final DateTime travelDate;

  final JourneyMapRepository journeyMapRepository;

  final SelectedJourneyTrackerBuilder? selectedJourneyTrackerBuilder;

  final RecommendationRealtimeAvailability? liveAvailability;

  final bool liveStatusLoading;

  final bool liveStatusUnavailable;

  final VoidCallback onReportProblem;

  String _routeLabel(String routeId, String? shortName) {
    final trimmed = shortName?.trim();

    return trimmed?.isNotEmpty == true ? trimmed! : routeId;
  }

  @override
  Widget build(BuildContext context) {
    final departure = formatServiceDaySeconds(recommendation.departureSeconds);
    final reminderJourney = ReminderJourney.fromRecommendation(
      recommendation,
      travelDate,
      originStopName,
      destinationStopName,
    );
    final existingReminder = reminders?.matching(reminderJourney);
    final futureDeparture = reminderJourney.departure.isAfter(
      (now ?? DateTime.now)(),
    );

    final arrival = formatServiceDaySeconds(recommendation.arrivalSeconds);

    final duration = formatDurationMinutes(recommendation.durationSeconds);

    final transfer = recommendation is TransferJourneyRecommendation
        ? recommendation as TransferJourneyRecommendation
        : null;

    final direct = recommendation is DirectJourneyRecommendation
        ? recommendation as DirectJourneyRecommendation
        : null;

    final title = direct != null
        ? 'Route ${_routeLabel(direct.routeId, direct.routeShortName)}'
        : '${_routeLabel(transfer!.firstRouteId, transfer.firstRouteShortName)} → ${_routeLabel(transfer.secondRouteId, transfer.secondRouteShortName)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),

            const SizedBox(height: 8),

            Text('$originStopName → $destinationStopName'),

            const SizedBox(height: 8),

            Text(
              '$departure → $arrival',
              style: Theme.of(context).textTheme.titleSmall,
            ),

            if (transfer != null) ...[
              const SizedBox(height: 10),

              Text('Transfer at ${transfer.transferStopName}'),

              Text(
                '${formatDurationMinutes(transfer.transferWaitSeconds)} transfer',
              ),
            ],

            const SizedBox(height: 12),

            _JourneySummary(
              label: transfer == null
                  ? '$duration • Direct'
                  : '$duration • 1 transfer',
            ),

            const SizedBox(height: 8),

            _RecommendationLiveStatus(
              transfer: transfer != null,
              availability: liveAvailability,
              loading: liveStatusLoading,
              unavailable: liveStatusUnavailable,
            ),

            const SizedBox(height: 12),

            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children:
                    [
                          TextButton.icon(
                            key: Key(
                              'report-bus-${recommendation.departureSeconds}',
                            ),
                            onPressed: onReportProblem,
                            icon: const Icon(Icons.report_problem_outlined),
                            label: const Text('Report Problem'),
                          ),

                          TextButton.icon(
                            key: Key(
                              'view-route-${recommendation.departureSeconds}',
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => RouteMapPage(
                                    recommendation: recommendation,
                                    originStopName: originStopName,
                                    destinationStopName: destinationStopName,
                                    repository: journeyMapRepository,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('View Route'),
                          ),

                          if (futureDeparture)
                            TextButton.icon(
                              key: Key(
                                'remind-me-${recommendation.departureSeconds}',
                              ),
                              onPressed: reminders == null
                                  ? () {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Please sign in to set a reminder.',
                                          ),
                                        ),
                                      );
                                    }
                                  : () {
                                      if (existingReminder != null) {
                                        showExistingReminder(
                                          context,
                                          reminders!,
                                          existingReminder,
                                        );
                                      } else {
                                        showReminderSheet(
                                          context,
                                          reminders!,
                                          reminderJourney,
                                        );
                                      }
                                    },
                              icon: Icon(
                                existingReminder == null
                                    ? Icons.notifications_none
                                    : Icons.notifications_active,
                              ),
                              label: Text(
                                existingReminder == null
                                    ? 'Remind Me'
                                    : 'Reminder Set',
                              ),
                            )
                          else
                            const SizedBox.shrink(),

                          FilledButton.tonalIcon(
                            key: Key(
                              'track-journey-${recommendation.departureSeconds}',
                            ),
                            onPressed: () {
                              final selected =
                                  SelectedJourneyTracking.fromRecommendation(
                                    recommendation: recommendation,
                                    originStopName: originStopName,
                                    destinationStopName: destinationStopName,
                                    travelDate: travelDate,
                                  );

                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      selectedJourneyTrackerBuilder?.call(
                                        selected,
                                        journeyMapRepository,
                                      ) ??
                                      SelectedJourneyTrackerPage(
                                        journey: selected,
                                        realtimeRepository:
                                            DataGovMyRealtimeVehicleRepository(),
                                        journeyMapRepository:
                                            journeyMapRepository,
                                      ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.directions_bus_outlined),
                            label: const Text('Track Journey'),
                          ),
                        ]
                        .map(
                          (action) => SizedBox(
                            width: (constraints.maxWidth - 8) / 2,
                            child: action,
                          ),
                        )
                        .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationLiveStatus extends StatelessWidget {
  const _RecommendationLiveStatus({
    required this.transfer,
    required this.availability,
    required this.loading,
    required this.unavailable,
  });

  final bool transfer;

  final RecommendationRealtimeAvailability? availability;

  final bool loading;

  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Text(
        'Checking live status...',
        key: Key('recommendation-live-loading'),
      );
    }

    if (unavailable || availability == null) {
      return const Text(
        'Live status unavailable',
        key: Key('recommendation-live-unavailable'),
      );
    }

    if (!transfer) {
      return Text(
        availability!.firstLegLive ? 'Live now' : 'Not currently live',
        key: const Key('direct-live-status'),
      );
    }

    return Column(
      key: const Key('transfer-live-status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Leg 1: ${availability!.firstLegLive ? 'Live' : 'Not live'}'),

        Text(
          'Leg 2: ${availability!.secondLegLive == true ? 'Live' : 'Not live yet'}',
        ),
      ],
    );
  }
}

class _JourneySummary extends StatelessWidget {
  const _JourneySummary({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String label;

  final String value;

  final IconData icon;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelLarge),

                    const SizedBox(height: 4),

                    Text(value),
                  ],
                ),
              ),

              const Icon(Icons.edit_outlined, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _StopField extends StatelessWidget {
  const _StopField({
    required this.label,
    required this.icon,
    required this.stop,
    required this.onTap,
    super.key,
  });

  final String label;

  final IconData icon;

  final DepartureStop? stop;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelLarge),

                    const SizedBox(height: 4),

                    Text(stop?.name ?? 'Tap to select a stop'),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage({
    required this.icon,
    required this.message,
    this.showProgress = false,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;

  final String message;

  final bool showProgress;

  final String? actionLabel;

  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (showProgress)
              const CircularProgressIndicator()
            else
              Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),

            const SizedBox(height: 12),

            Text(message, textAlign: TextAlign.center),

            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),

              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
