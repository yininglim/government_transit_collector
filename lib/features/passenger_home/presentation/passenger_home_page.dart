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
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_data_check_page.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_journey_tracker_page.dart';

class PassengerHomePage extends StatefulWidget {
  const PassengerHomePage({
    required this.profile,
    required this.repository,
    this.recentSearchRepository,
    this.preferencesRepository,
    this.savedJourneyRepository,
    this.feedbackRepository,
    this.reminderController,
    this.departurePageBuilder,
    this.livePageBuilder,
    this.dataCheckPageBuilder,
    super.key,
  });

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

class _PassengerHomePageState extends State<PassengerHomePage> {
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            widget.departurePageBuilder?.call(context) ??
            DepartureRecommendationPage(
              reminderController: _reminders,
              stopRepository: SupabaseDepartureStopRepository(),
              tripRepository: SupabaseDirectTripRepository(),
              transferRepository: SupabaseTransferJourneyRepository(),
              timetableRepository: SupabaseTimetableRecommendationRepository(),
              recentSearchRepository: _recentRepository,
              preferencesRepository: _preferencesRepository,
              savedJourneyRepository: _savedRepository,
              initialJourney: journey,
              initialRecentSearch: recent,
            ),
      ),
    );
  }

  Future<void> _openProfile() async {
    final journey = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => PassengerProfilePage(
          profile: _updatedProfile ?? widget.profile,
          authRepository: widget.repository,
          savedRepository: _savedRepository,
          recentRepository: _recentRepository,
          preferencesRepository: _preferencesRepository,
          feedbackRepository: widget.feedbackRepository,
          onProfileUpdated: (profile) {
            if (mounted) setState(() => _updatedProfile = profile);
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

  String _greeting() {
    final hour = DateTime.now().hour;
    return hour < 12
        ? 'Good Morning'
        : hour < 18
        ? 'Good Afternoon'
        : 'Good Evening';
  }

  void _openLive() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) =>
          widget.livePageBuilder?.call(context) ??
          RealtimeJourneyTrackerPage(
            repository: DataGovMyRealtimeVehicleRepository(),
            tripMatcher: SupabaseStaticTripMatcher(),
          ),
    ),
  );

  void _openDataCheck() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) =>
          widget.dataCheckPageBuilder?.call(context) ??
          RealtimeDataCheckPage(
            repository: DataGovMyRealtimeVehicleRepository(),
            tripMatcher: SupabaseStaticTripMatcher(),
          ),
    ),
  );

  Widget _navItem(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool selected = false,
  }) => Expanded(
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        backgroundColor: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        foregroundColor: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
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
          Text(
            'No upcoming journey. Plan your next trip when you are ready.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Government Transit Collector'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _navItem('Home', Icons.home_outlined, () {}, selected: true),
                  _navItem('Plan', Icons.route_outlined, _openDeparture),
                  _navItem('Live', Icons.location_searching, _openLive),
                  _navItem('Data Check', Icons.data_object, _openDataCheck),
                  _navItem(
                    'Reports',
                    Icons.feedback_outlined,
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PassengerReportsPage(
                          userId: widget.profile.userId,
                          repository: widget.feedbackRepository,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  '${_greeting()}, ${(_updatedProfile ?? widget.profile).displayName}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
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
      ),
    );
  }
}
