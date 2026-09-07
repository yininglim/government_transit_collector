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
    super.key,
  });

  final AppProfile profile;
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
        builder: (_) => DepartureRecommendationPage(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Government Transit Collector'),
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
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Passenger',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Welcome, ${(_updatedProfile ?? widget.profile).displayName}'),
            const SizedBox(height: 32),
            if (_reminders != null) UpcomingJourneys(controller: _reminders),
            _PlaceholderCard(
              icon: Icons.departure_board,
              title: 'Departure Recommendation',
              description: 'Select your origin and destination stops.',
              onTap: _openDeparture,
            ),
            const SizedBox(height: 16),
            _PlaceholderCard(
              icon: Icons.location_searching,
              title: 'Realtime Journey Tracker',
              description: 'View current myBAS vehicles on OpenStreetMap.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RealtimeJourneyTrackerPage(
                      repository: DataGovMyRealtimeVehicleRepository(),
                      tripMatcher: SupabaseStaticTripMatcher(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _PlaceholderCard(
              icon: Icons.data_object,
              title: 'Realtime Data Check',
              description: 'Verify the current myBAS vehicle-position feed.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RealtimeDataCheckPage(
                      repository: DataGovMyRealtimeVehicleRepository(),
                      tripMatcher: SupabaseStaticTripMatcher(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(description),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
