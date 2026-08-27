import 'dart:async';

import 'package:flutter/material.dart';

import '../data/feedback_reference_repository.dart';

class FeedbackRouteSelectionPage
    extends StatefulWidget {
  const FeedbackRouteSelectionPage({
    required this.repository,
    super.key,
  });

  final FeedbackReferenceRepository
  repository;

  @override
  State<FeedbackRouteSelectionPage>
  createState() =>
      _FeedbackRouteSelectionPageState();
}

class _FeedbackRouteSelectionPageState
    extends State<FeedbackRouteSelectionPage> {
  final _controller =
  TextEditingController();

  Timer? _debounce;

  List<FeedbackRoute>? _routes =
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
        _routes = const [];
        _error = null;
      });

      return;
    }

    setState(() {
      _routes = null;
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
      final routes =
      await widget.repository
          .searchRoutes(
        query,
      );

      if (!mounted ||
          requestId != _requestId) {
        return;
      }

      setState(() {
        _routes = routes;
      });
    } on FeedbackReferenceException catch (
    error) {
      if (!mounted ||
          requestId != _requestId) {
        return;
      }

      setState(() {
        _routes = const [];
        _error = error.message;
      });
    } on Object {
      if (!mounted ||
          requestId != _requestId) {
        return;
      }

      setState(() {
        _routes = const [];
        _error =
        'Unable to search routes.';
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
      _routes = null;
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
      appBar: AppBar(
        title: const Text(
          'Select Route',
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding:
          const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                key: const Key(
                  'feedback-route-search',
                ),
                controller:
                _controller,
                autofocus: true,
                decoration:
                const InputDecoration(
                  labelText:
                  'Search route',
                  helperText:
                  'Enter a route number or route name',
                  border:
                  OutlineInputBorder(),
                  prefixIcon:
                  Icon(
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

    final routes = _routes;

    if (routes == null) {
      return const Center(
        child:
        CircularProgressIndicator(),
      );
    }

    if (routes.isEmpty) {
      return Center(
        child: Text(
          _controller.text
              .trim()
              .isEmpty
              ? 'Search for a route'
              : 'No routes found',
        ),
      );
    }

    return ListView.separated(
      itemCount:
      routes.length,
      separatorBuilder:
          (_, _) =>
      const Divider(
        height: 1,
      ),
      itemBuilder:
          (context, index) {
        final route =
        routes[index];

        return ListTile(
          key: Key(
            'feedback-route-${route.id}',
          ),
          leading:
          const Icon(
            Icons.route,
          ),
          title: Text(
            route.displayName,
          ),
          subtitle: Text(
            'Route ID: ${route.id}',
          ),
          trailing:
          const Icon(
            Icons.chevron_right,
          ),
          onTap: () {
            Navigator.of(
              context,
            ).pop(
              route,
            );
          },
        );
      },
    );
  }
}