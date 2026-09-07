import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../data/bus_feedback.dart';
import '../data/feedback_issue_types.dart';
import '../data/bus_feedback_repository.dart';
import '../data/feedback_reference_repository.dart';
import 'feedback_route_selection_page.dart';
import '../data/feedback_schedule_repository.dart';

class FeedbackJourneyOption {
  const FeedbackJourneyOption({
    required this.label,
    required this.routeId,
    required this.routeLabel,
    required this.tripId,
    required this.departureSeconds,
    this.boardingStop,
  });

  final String label;

  final String routeId;
  final String routeLabel;

  final String tripId;

  final int departureSeconds;
  final FeedbackStop? boardingStop;
}

class BusFeedbackPage extends StatefulWidget {
  const BusFeedbackPage({
    required this.repository,
    required this.referenceRepository,
    this.journeyOptions = const [],
    this.travelDate,
    this.now,
    this.scheduleRepository,
    this.currentUserId,
    super.key,
  });

  final BusFeedbackRepository repository;

  final FeedbackReferenceRepository referenceRepository;

  final List<FeedbackJourneyOption> journeyOptions;

  final DateTime? travelDate;

  final DateTime Function()? now;
  final FeedbackScheduleRepository? scheduleRepository;
  final String? Function()? currentUserId;

  bool get hasJourneyContext => journeyOptions.isNotEmpty && travelDate != null;

  @override
  State<BusFeedbackPage> createState() => _BusFeedbackPageState();
}

class _BusFeedbackPageState extends State<BusFeedbackPage> {
  final _formKey = GlobalKey<FormState>();

  final _descriptionController = TextEditingController();

  static const int _missingBusGraceMinutes = 10;

  Set<String> _issueTypes = {};

  FeedbackJourneyOption? _selectedJourneyOption;

  FeedbackRoute? _selectedRoute;

  FeedbackStop? _selectedStop;

  bool _submitting = false;
  late final FeedbackScheduleRepository _schedule =
      widget.scheduleRepository ?? SupabaseFeedbackScheduleRepository();
  late DateTime _serviceDate;
  List<FeedbackStop> _stops = [];
  List<FeedbackDeparture> _departures = [];
  FeedbackDeparture? _departure;
  bool _loadingStops = false, _loadingTimes = false;
  String? _stopError, _timeError;
  int _stopRequest = 0, _timeRequest = 0;
  bool get _fixedStop =>
      widget.hasJourneyContext && _selectedJourneyOption?.boardingStop != null;
  int? get _departureSeconds => _departure?.seconds;

  @override
  void initState() {
    super.initState();
    final date = widget.travelDate ?? _currentTransitTime;
    _serviceDate = DateTime(date.year, date.month, date.day);

    if (widget.journeyOptions.length == 1) {
      _selectedJourneyOption = widget.journeyOptions.first;
      _applyJourney();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();

    super.dispose();
  }

  DateTime get _currentTransitTime {
    return currentTransitServiceDateTime(now: widget.now);
  }

  String? get _selectedRouteId {
    final journey = _selectedJourneyOption;

    if (journey != null) {
      return journey.routeId;
    }

    return _selectedRoute?.id;
  }

  String? get _selectedRouteLabel {
    final journey = _selectedJourneyOption;

    if (journey != null) {
      return journey.routeLabel;
    }

    return _selectedRoute?.displayName;
  }

  String? get _selectedTripId {
    return _selectedJourneyOption?.tripId ?? _departure?.tripId;
  }

  DateTime? get _scheduledDeparture {
    final seconds = _departureSeconds;
    if (seconds == null) return null;
    return timezone.TZDateTime(
      transitServiceLocation,
      _serviceDate.year,
      _serviceDate.month,
      _serviceDate.day,
    ).add(Duration(seconds: seconds));
  }

  List<String> get _availableIssueTypes {
    const generalIssues = <String>[
      'Bus overcrowded',
      'Missing bus stop',
      'Long walking distance',
      'Incorrect route information',
      'Bus location is incorrect',
      'Other',
    ];

    final departure = _scheduledDeparture;

    if (departure == null) {
      return const [
        'Bus was late',
        'Bus overcrowded',
        'Bus did not arrive',
        'Missing bus stop',
        'Long walking distance',
        'Incorrect route information',
        'Bus location is incorrect',
        'Other',
      ];
    }

    final now = _currentTransitTime;

    final issues = <String>[...generalIssues];

    if (!now.isBefore(departure)) {
      issues.insert(0, 'Bus was late');
    }

    final missingBusAvailableAt = departure.add(
      const Duration(minutes: _missingBusGraceMinutes),
    );

    if (!now.isBefore(missingBusAvailableAt)) {
      issues.insert(0, 'Bus did not arrive');
    }

    return issues;
  }

  String _formatTime(DateTime value) {
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(value));
  }

  String get _timingMessage {
    final departure = _scheduledDeparture;

    if (departure == null) {
      return 'Select a route, related stop, service date and scheduled departure.';
    }

    final now = _currentTransitTime;

    if (now.isBefore(departure)) {
      return 'Scheduled departure: '
          '${_formatTime(departure)}. '
          'Late and missing-bus reports are not available before the scheduled departure.';
    }

    final missingBusAvailableAt = departure.add(
      const Duration(minutes: _missingBusGraceMinutes),
    );

    if (now.isBefore(missingBusAvailableAt)) {
      return 'Scheduled departure: '
          '${_formatTime(departure)}. '
          'A missing-bus report becomes available at '
          '${_formatTime(missingBusAvailableAt)}.';
    }

    return 'Scheduled departure: '
        '${_formatTime(departure)}.';
  }

  Future<void> _selectRoute() async {
    if (widget.hasJourneyContext) {
      return;
    }

    final route = await Navigator.of(context).push<FeedbackRoute>(
      MaterialPageRoute(
        builder: (_) =>
            FeedbackRouteSelectionPage(repository: widget.referenceRepository),
      ),
    );

    if (!mounted || route == null) {
      return;
    }

    setState(() {
      _selectedRoute = route;
      _selectedStop = null;
    });
    _loadStops();
  }

  void _clearTimes() {
    _timeRequest++;
    _departure = null;
    _departures = [];
    _timeError = null;
    _loadingTimes = false;
    _issueTypes = {};
  }

  void _applyJourney() {
    _stopRequest++;
    _loadingStops = false;
    _clearTimes();
    final option = _selectedJourneyOption;
    _selectedStop = option?.boardingStop;
    _stops = [];
    _stopError = null;
    if (_selectedStop != null && option != null) {
      _departure = FeedbackDeparture(
        tripId: option.tripId,
        seconds: option.departureSeconds,
      );
    } else if (option != null) {
      _loadStops();
    }
  }

  Future<void> _loadStops() async {
    final route = _selectedRouteId;
    final request = ++_stopRequest;
    setState(() {
      _selectedStop = null;
      _stops = [];
      _stopError = null;
      _loadingStops = route != null;
      _clearTimes();
    });
    if (route == null) return;
    try {
      final rows = await _schedule.loadRouteStops(
        route,
        tripId: _selectedJourneyOption?.tripId,
      );
      if (!mounted || request != _stopRequest) return;
      setState(() => _stops = rows);
    } on Object {
      if (mounted && request == _stopRequest) {
        setState(
          () => _stopError = 'Unable to load related stops. Please try again.',
        );
      }
    } finally {
      if (mounted && request == _stopRequest) {
        setState(() => _loadingStops = false);
      }
    }
  }

  Future<void> _loadTimes() async {
    final route = _selectedRouteId;
    final stop = _selectedStop;
    final date = _serviceDate;
    _clearTimes();
    final request = _timeRequest;
    setState(() => _loadingTimes = route != null && stop != null);
    if (route == null || stop == null) return;
    try {
      final rows = await _schedule.loadDepartures(
        routeId: route,
        stopId: stop.id,
        serviceDate: date,
        tripId: _selectedJourneyOption?.tripId,
      );
      if (!mounted || request != _timeRequest) return;
      setState(() {
        _departures = rows;
        if (widget.hasJourneyContext) {
          final exact = rows.where(
            (r) => r.seconds == _selectedJourneyOption?.departureSeconds,
          );
          if (exact.isNotEmpty) {
            _departure = exact.first;
          } else if (rows.length == 1) {
            _departure = rows.first;
          } else if (rows.length > 1) {
            _timeError =
                'This trip visits the stop more than once. Reopen the report from the boarding journey.';
          }
        }
      });
    } on Object {
      if (mounted && request == _timeRequest) {
        setState(
          () => _timeError =
              'Unable to load scheduled departures. Please try again.',
        );
      }
    } finally {
      if (mounted && request == _timeRequest) {
        setState(() => _loadingTimes = false);
      }
    }
  }

  Future<void> _pickServiceDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _serviceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!mounted || date == null) return;
    setState(() => _serviceDate = date);
    _loadTimes();
  }

  Widget _stopAndScheduleFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_fixedStop)
        Card(
          child: ListTile(
            title: const Text('Related Bus Stop'),
            subtitle: Text('${_selectedStop!.name} (${_selectedStop!.id})'),
          ),
        )
      else
        DropdownButtonFormField<String>(
          key: ValueKey('report-stop-$_selectedRouteId-${_selectedStop?.id}'),
          initialValue: _selectedStop?.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Related Bus Stop',
            border: OutlineInputBorder(),
          ),
          hint: Text(
            _selectedRouteId == null
                ? 'Select a route first'
                : 'Select related bus stop',
          ),
          items: [
            for (final stop in _stops)
              DropdownMenuItem(
                value: stop.id,
                child: Text(
                  '${stop.name} (${stop.id})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _submitting || _loadingStops || _stops.isEmpty
              ? null
              : (id) {
                  setState(
                    () => _selectedStop = _stops.firstWhere((s) => s.id == id),
                  );
                  _loadTimes();
                },
        ),
      if (_loadingStops) const LinearProgressIndicator(),
      if (_stopError != null) ...[
        Text(_stopError!),
        TextButton(
          onPressed: _loadStops,
          child: const Text('Retry related stops'),
        ),
      ] else if (!_fixedStop &&
          _selectedRouteId != null &&
          !_loadingStops &&
          _stops.isEmpty)
        const Text('No related stops found for this route.'),
      const SizedBox(height: 16),
      if (widget.hasJourneyContext)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Service Date: ${MaterialLocalizations.of(context).formatMediumDate(_serviceDate)}, ${_serviceDate.year}'
              '\nScheduled departure: ${_departureSeconds == null ? 'Select a journey leg and related stop' : feedbackDepartureLabel(_departureSeconds!)}',
            ),
          ),
        )
      else ...[
        OutlinedButton.icon(
          key: const Key('report-service-date'),
          onPressed: _submitting ? null : _pickServiceDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(
            'Service Date: ${MaterialLocalizations.of(context).formatMediumDate(_serviceDate)}, ${_serviceDate.year}',
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          key: ValueKey('report-time-$_timeRequest-${_departure?.seconds}'),
          initialValue: _departure?.seconds,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Scheduled Time',
            border: OutlineInputBorder(),
          ),
          hint: Text(
            _selectedStop == null
                ? 'Select a route and stop first'
                : 'Select scheduled departure',
          ),
          items: [
            for (final departure in _departures)
              DropdownMenuItem(
                value: departure.seconds,
                child: Text(feedbackDepartureLabel(departure.seconds)),
              ),
          ],
          onChanged: _submitting || _loadingTimes || _departures.isEmpty
              ? null
              : (seconds) {
                  setState(() {
                    _departure = _departures.firstWhere(
                      (d) => d.seconds == seconds,
                    );
                    _issueTypes = {};
                  });
                },
        ),
      ],
      if (_loadingTimes) const LinearProgressIndicator(),
      if (_timeError != null) ...[
        Text(_timeError!),
        TextButton(
          onPressed: _loadTimes,
          child: const Text('Retry scheduled departures'),
        ),
      ] else if (!_fixedStop &&
          _selectedStop != null &&
          !_loadingTimes &&
          _departures.isEmpty)
        const Text(
          'No scheduled departures found for this stop on the selected date.',
        ),
    ],
  );

  void _selectJourneyOption(FeedbackJourneyOption? option) {
    if (option == null) {
      return;
    }

    setState(() {
      _selectedJourneyOption = option;

      _applyJourney();

      _issueTypes.removeWhere((issue) => !_availableIssueTypes.contains(issue));
    });
  }

  Future<void> _selectIssues() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final available = _availableIssueTypes;
    final selected = _issueTypes.where(available.contains).toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Problem Type'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final issue in available)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(issue),
                      value: selected.contains(issue),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (checked) => update(() {
                        if (checked == true) {
                          selected.add(issue);
                        } else {
                          selected.remove(issue);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _issueTypes = result);
  }

  Future<void> _submitFeedback() async {
    if (_submitting || _departure == null || _loadingTimes || _loadingStops) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final routeId = _selectedRouteId;

    if (routeId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a route.')));

      return;
    }

    final stop = _selectedStop;

    if (stop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a related bus stop.')),
      );

      return;
    }

    final issueTypes = _issueTypes.toList();

    if (issueTypes.isEmpty ||
        !issueTypes.every(_availableIssueTypes.contains)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid problem type.')),
      );

      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final valid = await widget.referenceRepository.stopBelongsToSelection(
        routeId: routeId,
        stopId: stop.id,
        tripId: _selectedTripId,
      );

      if (!valid) {
        if (!mounted) {
          return;
        }

        setState(() {
          if (!_fixedStop) _selectedStop = null;
          _clearTimes();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The selected stop is not related to the selected route or journey.',
            ),
          ),
        );

        return;
      }

      final choices = await _schedule.loadDepartures(
        routeId: routeId,
        stopId: stop.id,
        serviceDate: _serviceDate,
        tripId: _selectedTripId,
      );
      if (!choices.any((d) => d.seconds == _departureSeconds)) {
        throw const BusFeedbackException(
          'This scheduled departure is no longer available. Please select it again.',
        );
      }
      final userId = widget.currentUserId != null
          ? widget.currentUserId!()
          : Supabase.instance.client.auth.currentUser?.id;

      if (userId == null) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in before submitting feedback.'),
          ),
        );

        return;
      }

      final feedback = BusFeedback(
        userId: userId,
        serviceDate: _serviceDate,
        scheduledDepartureSeconds: _departureSeconds,
        routeId: routeId,
        tripId: _selectedTripId,
        stopId: stop.id,
        issueType: encodeFeedbackIssueTypes(issueTypes),
        comment: _descriptionController.text.trim(),
        createdAt: DateTime.now().toUtc(),
      );

      await widget.repository.submitFeedback(feedback);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thank you. Your report has been submitted.'),
        ),
      );

      Navigator.of(context).pop();
    } on FeedbackReferenceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on BusFeedbackException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on Object {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to submit feedback.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Bus / Stop Issue')),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.report_problem_outlined, size: 56),

                    const SizedBox(height: 16),

                    Text(
                      'Report a Transit Problem',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Choose the related route and bus stop, then describe the problem.',
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 24),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.schedule,
                              color: Theme.of(context).colorScheme.primary,
                            ),

                            const SizedBox(width: 12),

                            Expanded(child: Text(_timingMessage)),
                          ],
                        ),
                      ),
                    ),

                    if (widget.journeyOptions.length > 1) ...[
                      const SizedBox(height: 16),

                      DropdownButtonFormField<FeedbackJourneyOption>(
                        initialValue: _selectedJourneyOption,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Bus / Journey Leg',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.directions_bus_outlined),
                        ),
                        items: widget.journeyOptions.map((option) {
                          return DropdownMenuItem<FeedbackJourneyOption>(
                            value: option,
                            child: Text(
                              '${option.label} - ${option.routeLabel}',
                            ),
                          );
                        }).toList(),
                        onChanged: _submitting ? null : _selectJourneyOption,
                        validator: (value) {
                          if (value == null) {
                            return 'Please select the bus or journey leg.';
                          }

                          return null;
                        },
                      ),
                    ],

                    const SizedBox(height: 16),

                    if (widget.hasJourneyContext)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.route),
                          title: const Text('Route'),
                          subtitle: Text(
                            _selectedRouteLabel ?? 'Select a journey leg',
                          ),
                        ),
                      )
                    else
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _submitting ? null : _selectRoute,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.route,
                                  color: Theme.of(context).colorScheme.primary,
                                ),

                                const SizedBox(width: 16),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Route'),
                                      const SizedBox(height: 4),
                                      Text(
                                        _selectedRoute?.displayName ??
                                            'Tap to search and select a route',
                                      ),
                                    ],
                                  ),
                                ),

                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    _stopAndScheduleFields(),

                    const SizedBox(height: 20),

                    FormField<Set<String>>(
                      key: ValueKey(_issueTypes.join('|')),
                      initialValue: _issueTypes,
                      validator: (_) => _issueTypes.isEmpty
                          ? 'Please select a problem type.'
                          : null,
                      builder: (field) => InkWell(
                        key: const Key('report-issues'),
                        onTap: _submitting ? null : _selectIssues,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Problem Type',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.error_outline),
                            suffixIcon: const Icon(Icons.expand_more),
                            errorText: field.errorText,
                            enabled: !_submitting,
                          ),
                          child: _issueTypes.isEmpty
                              ? const Text('Select problem types')
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final issue in _issueTypes)
                                      Text(issue),
                                  ],
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _descriptionController,
                      enabled: !_submitting,
                      minLines: 4,
                      maxLines: 6,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Describe the Problem',
                        hintText:
                            'Describe what happened at the selected service.',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';

                        if (text.isEmpty) {
                          return 'Please describe the problem.';
                        }

                        if (text.length < 5) {
                          return 'Please provide more detail.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    FilledButton.icon(
                      onPressed:
                          _submitting ||
                              _departure == null ||
                              _selectedStop == null ||
                              _loadingTimes ||
                              _loadingStops
                          ? null
                          : _submitFeedback,
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(
                        _submitting ? 'Submitting...' : 'Submit Report',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
