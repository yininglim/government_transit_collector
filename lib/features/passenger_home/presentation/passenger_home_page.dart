import 'package:government_transit_collector/core/widgets/responsive_app_shell.dart';
import 'package:government_transit_collector/features/tracked_journeys/tracked_journey_repository.dart';
import 'package:government_transit_collector/features/tracked_journeys/tracked_journey_widgets.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import 'dart:async';
import 'package:government_transit_collector/features/bus_feedback/presentation/passenger_reports_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/journey_reminders/reminder_controller.dart';
import 'package:government_transit_collector/features/journey_reminders/reminder_widgets.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/saved_journey_repository.dart';
import 'package:government_transit_collector/features/passenger_profile/data/travel_preferences_repository.dart';
import 'package:government_transit_collector/features/passenger_profile/presentation/passenger_profile_page.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/direct_trip_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_search_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/transfer_journey_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_recommendation_page.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/static_trip_matcher.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_journey_tracker_page.dart';

String malaysiaGreeting(DateTime instant) {
  final hour = instant.toUtc().add(const Duration(hours: 8)).hour;
  if (hour >= 5 && hour < 12) return 'Good Morning';
  if (hour >= 12 && hour < 18) return 'Good Afternoon';
  return 'Good Evening';
}

class PassengerHomePage extends StatefulWidget {
  const PassengerHomePage({
    required this.profile,
    required this.repository,
    this.recentSearchRepository,
    this.preferencesRepository,
    this.savedJourneyRepository,
    this.feedbackRepository,
    this.reminderController,
    this.trackedJourneyRepository,
    this.activeJourneyTrackerBuilder,
    this.departurePageBuilder,
    this.livePageBuilder,
    this.dataCheckPageBuilder,
    this.now,
    super.key,
  });

  final TrackedJourneyRepository? trackedJourneyRepository;
  final Widget Function(SelectedJourneyTracking)? activeJourneyTrackerBuilder;
  final DateTime Function()? now;
  final AppProfile profile;
  final WidgetBuilder? departurePageBuilder;
  final WidgetBuilder? livePageBuilder;
  final WidgetBuilder? dataCheckPageBuilder;
  final ReminderController? reminderController;
  final AuthRepository repository;
  final RecentSearchRepository? recentSearchRepository;
  final TravelPreferencesRepository? preferencesRepository;
  final SavedJourneyRepository? savedJourneyRepository;
  final BusFeedbackRepository? feedbackRepository;

  @override
  State<PassengerHomePage> createState() => _PassengerHomePageState();
}

class _PassengerHomePageState extends State<PassengerHomePage>
    with WidgetsBindingObserver {
  Timer? _homeTimer;
  final _tabNavigators = List.generate(5, (_) => GlobalKey<NavigatorState>());
  final _detailTabs = List<bool>.filled(5, false);
  late final _tabObservers = List.generate(5, (tab) => _TabHeaderObserver((detail) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _detailTabs[tab] != detail) {
        setState(() => _detailTabs[tab] = detail);
      }
    });
  }));
  final _planKey = GlobalKey<DepartureRecommendationPageState>();
  final Map<int, WidgetBuilder> _tabBuilders = {};
  int _activeTab = 0;
  final _homeRevision = ValueNotifier(0);

  void _pushTab(int tab, WidgetBuilder builder) {
    setState(() {
      _tabBuilders.putIfAbsent(tab, () => builder);
      _activeTab = tab;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshHome();
    _homeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshHome(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshHome();
  }

  void _refreshHome() {
    if (mounted) _homeRevision.value++;
  }

  @override
  void dispose() {
    _homeTimer?.cancel();
    _homeRevision.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  late final _trackedJourneys =
      widget.trackedJourneyRepository ??
      SupabaseTrackedJourneyRepository(userId: widget.profile.userId);
  bool _signingOut = false;
  late final _reminders = widget.reminderController ?? sharedReminderController;
  AppProfile? _updatedProfile;
  late final _recentRepository =
      widget.recentSearchRepository ??
      SqliteRecentSearchRepository(userId: widget.profile.userId);
  late final _preferencesRepository =
      widget.preferencesRepository ??
      SqliteTravelPreferencesRepository(userId: widget.profile.userId);
  late final _savedRepository =
      widget.savedJourneyRepository ?? SupabaseSavedJourneyRepository();

  void _openDeparture([SavedJourney? journey, RecentJourneySearch? recent]) {
    if (journey != null || recent != null) {
      _planKey.currentState?.selectJourney(journey: journey, recent: recent);
    }
    _pushTab(
      1,
      (context) =>
          widget.departurePageBuilder?.call(context) ??
          DepartureRecommendationPage(
            key: _planKey,
            showPageHeader: false,
            reminderController: _reminders,
            trackedJourneyRepository: _trackedJourneys,
            stopRepository: SupabaseDepartureStopRepository(),
            tripRepository: SupabaseDirectTripRepository(),
            transferRepository: SupabaseTransferJourneyRepository(),
            timetableRepository: SupabaseTimetableRecommendationRepository(),
            recentSearchRepository: _recentRepository,
            preferencesRepository: _preferencesRepository,
            savedJourneyRepository: _savedRepository,
            initialJourney: journey,
            initialRecentSearch: recent,
            feedbackRepository: widget.feedbackRepository,
          ),
    );
  }

  Future<void> _openProfile() async {
    final journey = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => PassengerProfilePage(
          trackedJourneyRepository: _trackedJourneys,
          profile: _updatedProfile ?? widget.profile,
          authRepository: widget.repository,
          savedRepository: _savedRepository,
          recentRepository: _recentRepository,
          preferencesRepository: _preferencesRepository,
          feedbackRepository: widget.feedbackRepository,
          onProfileUpdated: (profile) {
            if (mounted) {
              setState(() => _updatedProfile = profile);
              _homeRevision.value++;
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    if (journey is SavedJourney) _openDeparture(journey);
    if (journey is RecentJourneySearch) _openDeparture(null, journey);
  }

  Future<void> _logout() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await widget.repository.logout();
    } on AuthFlowException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      setState(() => _signingOut = false);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to sign out. Please try again.')),
      );
      setState(() => _signingOut = false);
    }
  }

  void _openLive() => _pushTab(
    2,
    (context) =>
        widget.livePageBuilder?.call(context) ??
        RealtimeJourneyTrackerPage(
          showPageHeader: false,
          repository: DataGovMyRealtimeVehicleRepository(),
          tripMatcher: SupabaseStaticTripMatcher(),
        ),
  );

  void _openReports() => _pushTab(
    3,
    (_) => PassengerReportsPage(
      showPageHeader: false,
      userId: widget.profile.userId,
      repository: widget.feedbackRepository,
    ),
  );

  void _selectTab(int index) {
    if (index == _activeTab) return;
    switch (index) {
      case 0:
        setState(() => _activeTab = 0);
      case 1:
        _openDeparture();
      case 2:
        _openLive();
      case 3:
        _openReports();
      case 4:
        _openMyTrips();
    }
  }

  void _openMyTrips() => _pushTab(
    4,
    (_) => Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'My Trips',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text('Review your completed journeys.'),
                        const SizedBox(height: 16),
                        MyTripsSection(
                          repository: _trackedJourneys,
                          feedbackRepository: widget.feedbackRepository,
                          onPlanAgain: (recent) =>
                              _openDeparture(null, recent),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _emptyJourney() => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.event_available_outlined, size: 32),
          SizedBox(height: 12),
          Text('Upcoming Journey'),
          SizedBox(height: 8),
          Text(
            'Nothing scheduled yet',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Text(
            'Your next journey reminder will appear here after you plan a trip.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ResponsiveAppShell(
      items: const [
        AppNavigationItem(label: 'Home', icon: Icons.home_outlined),
        AppNavigationItem(label: 'Plan', icon: Icons.route_outlined),
        AppNavigationItem(label: 'Live', icon: Icons.location_searching),
        AppNavigationItem(label: 'Reports', icon: Icons.feedback_outlined),
        AppNavigationItem(label: 'My Trips', icon: Icons.task_alt),
      ],
      selectedIndex: _activeTab,
      onSelected: _selectTab,
      navigationKeyPrefix: 'passenger-nav',
      showHeader: !_detailTabs[_activeTab],
      actions: [
        IconButton(
          tooltip: 'My Travel Profile',
          onPressed: _signingOut ? null : _openProfile,
          icon: const Icon(Icons.person_outline),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: _signingOut ? null : _logout,
          icon: _signingOut
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.logout),
        ),
      ],
      child: ScrollConfiguration(
        behavior: const _PassengerScrollBehavior(),
        child: IndexedStack(
          index: _activeTab,
          children: List.generate(5, (tab) {
            if (tab != 0 && !_tabBuilders.containsKey(tab)) {
              return const SizedBox.shrink();
            }
            return NavigatorPopHandler<Object?>(
              enabled: _activeTab == tab,
              onPopWithResult: (_) => _tabNavigators[tab].currentState!.pop(),
              child: Navigator(
                key: _tabNavigators[tab],
                observers: [_tabObservers[tab]],
                onGenerateInitialRoutes: (_, _) => [
                  MaterialPageRoute<void>(
                    settings: RouteSettings(name: 'passenger-tab-$tab'),
                    builder: tab == 0
                        ? (_) => ValueListenableBuilder(
                            valueListenable: _homeRevision,
                            builder: (_, _, _) => _homeBody(),
                          )
                        : _tabBuilders[tab]!,
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _homeBody() => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '${malaysiaGreeting((widget.now ?? DateTime.now)())}, ${(_updatedProfile ?? widget.profile).displayName}',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Your journey, made easier.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              onPressed: _openDeparture,
              icon: const Icon(Icons.route),
              label: const Text('Plan a Journey'),
            ),
            const SizedBox(height: 32),
            ActiveJourneySection(
              key: ValueKey('active-journey-${widget.profile.userId}'),
              repository: _trackedJourneys,
              now: widget.now,
              trackerBuilder: widget.activeJourneyTrackerBuilder,
            ),
            if (_reminders != null)
              UpcomingJourneys(
                controller: _reminders,
                emptyState: _emptyJourney(),
              )
            else
              _emptyJourney(),
          ],
        ),
      ),
    ),
  );
}

class _TabHeaderObserver extends NavigatorObserver {
  _TabHeaderObserver(this.onDetailChanged);
  final ValueChanged<bool> onDetailChanged;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    if (topRoute is PageRoute) onDetailChanged(!topRoute.isFirst);
  }
}

class _PassengerScrollBehavior extends MaterialScrollBehavior {
  const _PassengerScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      AlwaysScrollableScrollPhysics(parent: super.getScrollPhysics(context));
}
