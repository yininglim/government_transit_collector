import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback_repository.dart';
import 'my_reports_section.dart';
import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/authentication/presentation/change_password_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_search_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/saved_journey_repository.dart';
import 'package:government_transit_collector/features/passenger_profile/data/travel_preferences_repository.dart';

class PassengerProfilePage extends StatefulWidget {
  const PassengerProfilePage({
    super.key,
    required this.profile,
    required this.authRepository,
    required this.savedRepository,
    required this.recentRepository,
    required this.preferencesRepository,
    required this.onProfileUpdated,
    this.feedbackRepository,
  });
  final AppProfile profile;
  final BusFeedbackRepository? feedbackRepository;
  final AuthRepository authRepository;
  final SavedJourneyRepository savedRepository;
  final RecentSearchRepository recentRepository;
  final TravelPreferencesRepository preferencesRepository;
  final ValueChanged<AppProfile> onProfileUpdated;
  @override
  State<PassengerProfilePage> createState() => _PassengerProfilePageState();
}

class _PassengerProfilePageState extends State<PassengerProfilePage> {
  late final TextEditingController _name;
  late String _displayName;
  List<SavedJourney>? _saved;
  List<RecentJourneySearch>? _recent;
  String? _savedError, _recentError, _preferenceError;
  int _radius = 1000;
  bool _savingName = false, _savingRadius = false;
  final Set<String> _deleting = {};
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.fullName);
    _displayName = widget.profile.displayName;
    _loadSaved();
    _loadRecent();
    _loadRadius();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _loadSaved() async {
    setState(() {
      _savedError = null;
    });
    try {
      final rows = await widget.savedRepository.load();
      if (mounted) setState(() => _saved = rows);
    } on Object {
      if (mounted) {
        setState(() => _savedError = 'Unable to load saved journeys.');
      }
    }
  }

  Future<void> _loadRecent() async {
    setState(() => _recentError = null);
    try {
      final rows = await widget.recentRepository.getRecentSearches();
      if (mounted) setState(() => _recent = rows);
    } on Object {
      if (mounted) {
        setState(() => _recentError = 'Unable to load recent searches.');
      }
    }
  }

  Future<void> _loadRadius() async {
    setState(() => _savingRadius = true);
    try {
      final radius = await widget.preferencesRepository.loadRadius();
      if (mounted) {
        setState(() {
          _radius = radius;
          _preferenceError = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _preferenceError =
              'Unable to load preference. Using 1 km until saved.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingRadius = false);
    }
  }

  Future<void> _saveRadius(int radius) async {
    setState(() => _savingRadius = true);
    try {
      await widget.preferencesRepository.saveRadius(radius);
      if (mounted) {
        setState(() {
          _radius = radius;
          _preferenceError = null;
        });
      }
    } on Object {
      _message('Unable to save nearby radius. Please try again.');
    } finally {
      if (mounted) setState(() => _savingRadius = false);
    }
  }

  Future<void> _saveName() async {
    setState(() => _savingName = true);
    try {
      final profile = await widget.authRepository.updateFullName(_name.text);
      if (!mounted) return;
      setState(() => _displayName = profile.displayName);
      widget.onProfileUpdated(profile);
      _message('Name updated.');
    } on Object catch (error) {
      _message(
        error is AuthFlowException ? error.message : 'Unable to update name.',
      );
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _delete(SavedJourney journey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved journey?'),
        content: Text(journey.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _deleting.add(journey.id));
    try {
      await widget.savedRepository.delete(journey.id);
      if (mounted) await _loadSaved();
    } on Object {
      _message('Unable to delete journey. Please try again.');
    } finally {
      if (mounted) setState(() => _deleting.remove(journey.id));
    }
  }

  Future<void> _clear() async {
    try {
      await widget.recentRepository.clearRecentSearches();
      if (mounted) await _loadRecent();
    } on Object {
      _message('Unable to clear recent searches.');
    }
  }

  Widget _section(String title, IconData icon, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My Travel Profile')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    size: 36,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _displayName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                widget.profile.email ?? 'No email',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              _section('Account Information', Icons.person_outline, [
                TextField(
                  controller: _name,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                FilledButton(
                  onPressed: _savingName ? null : _saveName,
                  child: Text(_savingName ? 'Saving…' : 'Update Name'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Email (read-only)'),
                  subtitle: Text(widget.profile.email ?? 'No email'),
                ),
              ]),
              _section('Account Security', Icons.security_outlined, [
                const Text('Sign-in methods'),
                if (widget.authRepository.supportsEmailPassword)
                  const Text('✓ Email & Password'),
                if (widget.authRepository.hasGoogleIdentity)
                  const Text('✓ Google'),
                if (widget.authRepository.supportsEmailPassword)
                  OutlinedButton(
                    onPressed: () async {
                      final message = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (_) => ChangePasswordPage(
                            repository: widget.authRepository,
                          ),
                        ),
                      );
                      if (message != null) _message(message);
                    },
                    child: const Text('Change Email Password'),
                  ),
                if (widget.authRepository.hasGoogleIdentity) ...[
                  Text(
                    widget.authRepository.supportsEmailPassword
                        ? 'Google sign-in is also linked'
                        : 'Signed in with Google',
                  ),
                  const Text(
                    'Your Google password is managed through your Google Account.',
                  ),
                ] else if (!widget.authRepository.supportsEmailPassword)
                  const Text(
                    'Password changes are not available for this sign-in method.',
                  ),
              ]),
              _section('Travel Preferences', Icons.tune, [
                const Text('Default Nearby Stop Radius'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final radius in [500, 1000, 2000])
                      ChoiceChip(
                        label: Text(
                          radius == 500 ? '500 m' : '${radius ~/ 1000} km',
                        ),
                        selected: radius == _radius,
                        onSelected: _savingRadius
                            ? null
                            : (_) => _saveRadius(radius),
                      ),
                  ],
                ),
                if (_preferenceError != null) Text(_preferenceError!),
              ]),
              _section('Saved Journeys', Icons.bookmark_outline, [
                if (_savedError != null) ...[
                  Text(_savedError!),
                  TextButton(
                    onPressed: _loadSaved,
                    child: const Text('Retry saved journeys'),
                  ),
                ] else if (_saved == null)
                  const Center(child: CircularProgressIndicator())
                else if (_saved!.isEmpty)
                  const Text(
                    'Save an origin and destination in Departure Recommendation.',
                  )
                else
                  for (final journey in _saved!)
                    ListTile(
                      title: Text(journey.name),
                      subtitle: Text(
                        journey.usable
                            ? '${journey.origin!.name} → ${journey.destination!.name}'
                            : 'A saved stop is no longer available. Please save a new journey.',
                      ),
                      onTap: journey.usable && !_deleting.contains(journey.id)
                          ? () => Navigator.pop(context, journey)
                          : null,
                      trailing: IconButton(
                        tooltip: 'Delete ${journey.name}',
                        onPressed: _deleting.contains(journey.id)
                            ? null
                            : () => _delete(journey),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
              ]),
              _section('Recent Searches', Icons.history, [
                const Text(
                  'Recent searches on this device, not completed trips.',
                ),
                TextButton(
                  onPressed: _clear,
                  child: const Text('Clear History'),
                ),
                if (_recentError != null) ...[
                  Text(_recentError!),
                  TextButton(
                    onPressed: _loadRecent,
                    child: const Text('Retry recent searches'),
                  ),
                ] else if (_recent == null)
                  const Center(child: CircularProgressIndicator())
                else if (_recent!.isEmpty)
                  const Text('No recent searches.')
                else
                  for (final recent in _recent!)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      trailing: TextButton(
                        onPressed: () => Navigator.pop(context, recent),
                        child: const Text('Search Again'),
                      ),
                      title: Text(
                        '${recent.originStopName} → ${recent.destinationStopName}',
                      ),
                    ),
              ]),
              _section('My Reports', Icons.receipt_long_outlined, [
                MyReportsSection(
                  userId: widget.profile.userId,
                  repository: widget.feedbackRepository,
                ),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
}
