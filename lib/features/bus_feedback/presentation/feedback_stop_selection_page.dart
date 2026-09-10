import 'package:government_transit_collector/core/widgets/readable_app_bar.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/feedback_reference_repository.dart';

class FeedbackStopSelectionPage
    extends StatefulWidget {
  const FeedbackStopSelectionPage({
    required this.repository,
    required this.routeId,
    required this.routeLabel,
    this.tripId,
    super.key,
  });

  final FeedbackReferenceRepository
  repository;

  final String routeId;
  final String routeLabel;

  final String? tripId;

  @override
  State<FeedbackStopSelectionPage>
  createState() =>
      _FeedbackStopSelectionPageState();
}

class _FeedbackStopSelectionPageState
    extends State<FeedbackStopSelectionPage> {
  final _controller =
  TextEditingController();

  Timer? _debounce;

  List<FeedbackStop>? _stops =
  const [];

  String? _error;

  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();

    super.dispose();
  }

  void _onChanged(
      String value,
      ) {
    _debounce?.cancel();

    final query =
    value.trim();

    final requestId =
    ++_requestId;

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
      const Duration(
        milliseconds: 350,
      ),
          () {
        _search(
          query,
          requestId,
        );
      },
    );
  }

  Future<void> _search(
      String query,
      int requestId,
      ) async {
    try {
      final stops =
      await widget.repository
          .searchStops(
        routeId:
        widget.routeId,
        tripId:
        widget.tripId,
        query:
        query,
      );

      if (!mounted ||
          requestId != _requestId) {
        return;
      }

      setState(() {
        _stops = stops;
      });
    } on FeedbackReferenceException catch (
    error) {
      if (!mounted ||
          requestId != _requestId) {
        return;
      }

      setState(() {
        _stops = const [];
        _error =
            error.message;
      });
    } on Object {
      if (!mounted ||
          requestId != _requestId) {
        return;
      }

      setState(() {
        _stops = const [];
        _error =
        'Unable to search stops.';
      });
    }
  }

  Future<void> _retry() async {
    final query =
    _controller.text.trim();

    if (query.isEmpty) {
      return;
    }

    final requestId =
    ++_requestId;

    setState(() {
      _stops = null;
      _error = null;
    });

    await _search(
      query,
      requestId,
    );
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      appBar: readableAppBar(context, 
        title: const Text(
          'Select Related Bus Stop',
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding:
          const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                child: ListTile(
                  leading:
                  const Icon(
                    Icons.route,
                  ),
                  title:
                  const Text(
                    'Selected Route',
                  ),
                  subtitle: Text(
                    widget.routeLabel,
                  ),
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              TextField(
                key: const Key(
                  'feedback-stop-search',
                ),
                controller:
                _controller,
                autofocus: true,
                decoration:
                InputDecoration(
                  labelText:
                  'Search bus stop',
                  helperText:
                  widget.tripId !=
                      null
                      ? 'Only stops from this journey are shown'
                      : 'Only stops belonging to this route are shown',
                  border:
                  const OutlineInputBorder(),
                  prefixIcon:
                  const Icon(
                    Icons.search,
                  ),
                ),
                onChanged:
                _onChanged,
              ),

              const SizedBox(
                height: 12,
              ),

              Expanded(
                child:
                _buildResults(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 40,
            ),

            const SizedBox(
              height: 12,
            ),

            Text(
              _error!,
              textAlign:
              TextAlign.center,
            ),

            const SizedBox(
              height: 12,
            ),

            FilledButton.tonal(
              onPressed:
              _retry,
              child: const Text(
                'Retry',
              ),
            ),
          ],
        ),
      );
    }

    final stops = _stops;

    if (stops == null) {
      return const Center(
        child:
        CircularProgressIndicator(),
      );
    }

    if (stops.isEmpty) {
      return Center(
        child: Text(
          _controller.text
              .trim()
              .isEmpty
              ? 'Search for a bus stop'
              : 'No related stops found',
        ),
      );
    }

    return ListView.separated(
      itemCount:
      stops.length,
      separatorBuilder:
          (_, _) =>
      const Divider(
        height: 1,
      ),
      itemBuilder:
          (context, index) {
        final stop =
        stops[index];

        return ListTile(
          key: Key(
            'feedback-stop-${stop.id}',
          ),
          leading:
          const Icon(
            Icons
                .directions_bus_outlined,
          ),
          title: Text(
            stop.name,
          ),
          subtitle: Text(
            'Stop ID: ${stop.id}',
          ),
          trailing:
          const Icon(
            Icons.chevron_right,
          ),
          onTap: () {
            Navigator.of(
              context,
            ).pop(
              stop,
            );
          },
        );
      },
    );
  }
}