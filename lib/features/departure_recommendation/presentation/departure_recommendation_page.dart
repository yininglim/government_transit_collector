import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_validation.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/stop_selection_page.dart';

class DepartureRecommendationPage extends StatefulWidget {
  const DepartureRecommendationPage({required this.repository, super.key});

  final DepartureStopRepository repository;

  @override
  State<DepartureRecommendationPage> createState() =>
      _DepartureRecommendationPageState();
}

class _DepartureRecommendationPageState
    extends State<DepartureRecommendationPage> {
  DepartureStop? _origin;
  DepartureStop? _destination;
  String? _validationMessage;
  String? _confirmationMessage;

  Future<void> _selectOrigin() async {
    final stop = await Navigator.of(context).push<DepartureStop>(
      MaterialPageRoute(
        builder: (_) => StopSelectionPage(
          title: 'Select origin stop',
          repository: widget.repository,
          excludedStopId: _destination?.id,
        ),
      ),
    );
    if (!mounted || stop == null) return;
    setState(() {
      _origin = stop;
      _validationMessage = null;
      _confirmationMessage = null;
    });
  }

  Future<void> _selectDestination() async {
    final stop = await Navigator.of(context).push<DepartureStop>(
      MaterialPageRoute(
        builder: (_) => StopSelectionPage(
          title: 'Select destination stop',
          repository: widget.repository,
          excludedStopId: _origin?.id,
        ),
      ),
    );
    if (!mounted || stop == null) return;
    setState(() {
      _destination = stop;
      _validationMessage = null;
      _confirmationMessage = null;
    });
  }

  void _search() {
    final validationMessage = validateDepartureStops(
      origin: _origin,
      destination: _destination,
    );
    setState(() {
      _validationMessage = validationMessage;
      _confirmationMessage = validationMessage == null
          ? 'Selected journey: ${_origin!.name} → ${_destination!.name}'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Departure Recommendation')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Where would you like to go?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Select an origin and destination stop.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            _StopField(
              key: const Key('origin-field'),
              label: 'Origin / From stop',
              icon: Icons.trip_origin,
              stop: _origin,
              onTap: _selectOrigin,
            ),
            const SizedBox(height: 16),
            _StopField(
              key: const Key('destination-field'),
              label: 'Destination / To stop',
              icon: Icons.location_on_outlined,
              stop: _destination,
              onTap: _selectDestination,
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _validationMessage!,
                key: const Key('validation-message'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('journey-search-button'),
              onPressed: _search,
              icon: const Icon(Icons.search),
              label: const Text('Search'),
            ),
            if (_confirmationMessage != null) ...[
              const SizedBox(height: 24),
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _confirmationMessage!,
                    key: const Key('journey-confirmation'),
                  ),
                ),
              ),
            ],
          ],
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
  final VoidCallback onTap;

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
                    Text(
                      stop?.name ?? 'Tap to select a stop',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
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
