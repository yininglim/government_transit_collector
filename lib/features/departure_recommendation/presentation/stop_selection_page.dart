import 'dart:async';

import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';

class StopSelectionPage extends StatefulWidget {
  const StopSelectionPage({
    required this.title,
    required this.repository,
    required this.excludedStopId,
    super.key,
  });

  final String title;
  final DepartureStopRepository repository;
  final String? excludedStopId;

  @override
  State<StopSelectionPage> createState() => _StopSelectionPageState();
}

class _StopSelectionPageState extends State<StopSelectionPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<DepartureStop>? _stops = const [];
  String? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final requestId = ++_requestId;
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _stops = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _stops = null;
      _error = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadStops(query: query, requestId: requestId),
    );
  }

  Future<void> _loadStops({String? query, int? requestId}) async {
    final effectiveQuery = query ?? _searchController.text.trim();
    if (effectiveQuery.isEmpty) return;
    final effectiveRequestId = requestId ?? ++_requestId;
    setState(() {
      _stops = null;
      _error = null;
    });
    try {
      final stops = await widget.repository.searchStops(effectiveQuery);
      if (!mounted || effectiveRequestId != _requestId) return;
      setState(() => _stops = stops);
    } on DepartureStopReadException catch (error) {
      if (!mounted || effectiveRequestId != _requestId) return;
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                key: const Key('stop-search-field'),
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Search stops',
                  helperText: 'Type a stop name to search all available stops',
                  prefixIcon: Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (_) {
                  _debounce?.cancel();
                  final query = _searchController.text.trim();
                  if (query.isNotEmpty) {
                    _loadStops(query: query);
                  }
                },
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildResults()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_error != null) {
      return _StopMessage(
        icon: Icons.error_outline,
        message: _error!,
        actionLabel: 'Retry',
        onAction: () => _loadStops(),
      );
    }
    final stops = _stops;
    if (stops == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (stops.isEmpty) {
      if (_searchController.text.trim().isEmpty) {
        return const _StopMessage(
          icon: Icons.search,
          message: 'Search to find a bus stop',
        );
      }
      return const _StopMessage(
        icon: Icons.search_off,
        message: 'No stops found',
      );
    }
    return ListView.separated(
      itemCount: stops.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final stop = stops[index];
        final excluded = stop.id == widget.excludedStopId;
        return ListTile(
          key: Key('stop-${stop.id}'),
          leading: const Icon(Icons.directions_bus_outlined),
          title: Text(stop.name),
          subtitle: excluded ? const Text('Already selected') : null,
          enabled: !excluded,
          onTap: excluded ? null : () => Navigator.of(context).pop(stop),
        );
      },
    );
  }
}

class _StopMessage extends StatelessWidget {
  const _StopMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
