import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/bus_feedback.dart';
import '../data/bus_feedback_repository.dart';
import '../data/feedback_reference_repository.dart';
import 'feedback_route_selection_page.dart';
import 'feedback_stop_selection_page.dart';

class FeedbackJourneyOption {
  const FeedbackJourneyOption({
    required this.label,
    required this.routeId,
    required this.routeLabel,
    required this.tripId,
    required this.departureSeconds,
  });

  final String label;

  final String routeId;
  final String routeLabel;

  final String tripId;

  final int departureSeconds;
}

class BusFeedbackPage
    extends StatefulWidget {
  const BusFeedbackPage({
    required this.repository,
    required this.referenceRepository,
    this.journeyOptions = const [],
    this.travelDate,
    this.now,
    super.key,
  });

  final BusFeedbackRepository
  repository;

  final FeedbackReferenceRepository
  referenceRepository;

  final List<FeedbackJourneyOption>
  journeyOptions;

  final DateTime? travelDate;

  final DateTime Function()? now;

  bool get hasJourneyContext =>
      journeyOptions.isNotEmpty &&
          travelDate != null;

  @override
  State<BusFeedbackPage> createState() =>
      _BusFeedbackPageState();
}

class _BusFeedbackPageState
    extends State<BusFeedbackPage> {
  final _formKey =
  GlobalKey<FormState>();

  final _commentController =
  TextEditingController();

  static const int
  _missingBusGraceMinutes = 10;

  String? _issueType;

  FeedbackJourneyOption?
  _selectedJourneyOption;

  FeedbackRoute? _selectedRoute;

  FeedbackStop? _selectedStop;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();

    if (widget.journeyOptions.length ==
        1) {
      _selectedJourneyOption =
          widget.journeyOptions.first;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();

    super.dispose();
  }

  DateTime get _currentTransitTime {
    return currentTransitServiceDateTime(
      now: widget.now,
    );
  }

  String? get _selectedRouteId {
    final journey =
        _selectedJourneyOption;

    if (journey != null) {
      return journey.routeId;
    }

    return _selectedRoute?.id;
  }

  String? get _selectedRouteLabel {
    final journey =
        _selectedJourneyOption;

    if (journey != null) {
      return journey.routeLabel;
    }

    return _selectedRoute?.displayName;
  }

  String? get _selectedTripId {
    return _selectedJourneyOption
        ?.tripId;
  }

  DateTime? get _scheduledDeparture {
    final option =
        _selectedJourneyOption;

    final travelDate =
        widget.travelDate;

    if (option == null ||
        travelDate == null) {
      return null;
    }

    final seconds =
        option.departureSeconds;

    final serviceDays =
        seconds ~/
            Duration.secondsPerDay;

    final remainingSeconds =
        seconds %
            Duration.secondsPerDay;

    final hour =
        remainingSeconds ~/ 3600;

    final minute =
        (remainingSeconds % 3600) ~/
            60;

    final second =
        remainingSeconds % 60;

    final baseDate = DateTime(
      travelDate.year,
      travelDate.month,
      travelDate.day,
    ).add(
      Duration(
        days: serviceDays,
      ),
    );

    return DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      hour,
      minute,
      second,
    );
  }

  List<String> get _availableIssueTypes {
    const generalIssues =
    <String>[
      'Bus overcrowded',
      'Missing bus stop',
      'Long walking distance',
      'Incorrect route information',
      'Other',
    ];

    final departure =
        _scheduledDeparture;

    if (departure == null) {
      return const [
        'Bus was late',
        'Bus overcrowded',
        'Bus did not arrive',
        'Missing bus stop',
        'Long walking distance',
        'Incorrect route information',
        'Other',
      ];
    }

    final now =
        _currentTransitTime;

    final issues =
    <String>[
      ...generalIssues,
    ];

    if (!now.isBefore(
      departure,
    )) {
      issues.insert(
        0,
        'Bus was late',
      );
    }

    final missingBusAvailableAt =
    departure.add(
      const Duration(
        minutes:
        _missingBusGraceMinutes,
      ),
    );

    if (!now.isBefore(
      missingBusAvailableAt,
    )) {
      issues.insert(
        0,
        'Bus did not arrive',
      );
    }

    return issues;
  }

  String _formatTime(
      DateTime value,
      ) {
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(
      TimeOfDay.fromDateTime(
        value,
      ),
    );
  }

  String get _timingMessage {
    final departure =
        _scheduledDeparture;

    if (departure == null) {
      return 'Select the related route and bus stop. '
          'For a previous journey, include the approximate date and time in your description.';
    }

    final now =
        _currentTransitTime;

    if (now.isBefore(
      departure,
    )) {
      return 'Scheduled departure: '
          '${_formatTime(departure)}. '
          'Late and missing-bus reports are not available before the scheduled departure.';
    }

    final missingBusAvailableAt =
    departure.add(
      const Duration(
        minutes:
        _missingBusGraceMinutes,
      ),
    );

    if (now.isBefore(
      missingBusAvailableAt,
    )) {
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

    final route =
    await Navigator.of(context)
        .push<FeedbackRoute>(
      MaterialPageRoute(
        builder: (_) =>
            FeedbackRouteSelectionPage(
              repository:
              widget.referenceRepository,
            ),
      ),
    );

    if (!mounted ||
        route == null) {
      return;
    }

    setState(() {
      _selectedRoute = route;
      _selectedStop = null;
    });
  }

  Future<void> _selectStop() async {
    final routeId =
        _selectedRouteId;

    final routeLabel =
        _selectedRouteLabel;

    if (routeId == null ||
        routeLabel == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a route first.',
          ),
        ),
      );

      return;
    }

    final stop =
    await Navigator.of(context)
        .push<FeedbackStop>(
      MaterialPageRoute(
        builder: (_) =>
            FeedbackStopSelectionPage(
              repository:
              widget.referenceRepository,
              routeId:
              routeId,
              routeLabel:
              routeLabel,
              tripId:
              _selectedTripId,
            ),
      ),
    );

    if (!mounted ||
        stop == null) {
      return;
    }

    setState(() {
      _selectedStop = stop;
    });
  }

  void _selectJourneyOption(
      FeedbackJourneyOption? option,
      ) {
    if (option == null) {
      return;
    }

    setState(() {
      _selectedJourneyOption =
          option;

      _selectedStop = null;

      if (_issueType != null &&
          !_availableIssueTypes
              .contains(
            _issueType,
          )) {
        _issueType = null;
      }
    });
  }

  Future<void> _submitFeedback() async {
    if (_submitting) {
      return;
    }

    if (!_formKey.currentState!
        .validate()) {
      return;
    }

    final routeId =
        _selectedRouteId;

    if (routeId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a route.',
          ),
        ),
      );

      return;
    }

    final stop =
        _selectedStop;

    if (stop == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a related bus stop.',
          ),
        ),
      );

      return;
    }

    final issueType =
        _issueType;

    if (issueType == null ||
        !_availableIssueTypes
            .contains(
          issueType,
        )) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a valid problem type.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final valid =
      await widget.referenceRepository
          .stopBelongsToSelection(
        routeId:
        routeId,
        stopId:
        stop.id,
        tripId:
        _selectedTripId,
      );

      if (!valid) {
        if (!mounted) {
          return;
        }

        setState(() {
          _selectedStop = null;
        });

        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'The selected stop is not related to the selected route or journey.',
            ),
          ),
        );

        return;
      }

      final user =
          Supabase.instance.client.auth
              .currentUser;

      if (user == null) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'Please log in before submitting feedback.',
            ),
          ),
        );

        return;
      }

      final feedback =
      BusFeedback(
        userId:
        user.id,
        routeId:
        routeId,
        tripId:
        _selectedTripId,
        stopId:
        stop.id,
        issueType:
        issueType,
        comment:
        _commentController.text
            .trim(),
        createdAt:
        DateTime.now().toUtc(),
      );

      await widget.repository
          .submitFeedback(
        feedback,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Thank you. Your report has been submitted.',
          ),
        ),
      );

      Navigator.of(context).pop();
    } on FeedbackReferenceException catch (
    error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            error.message,
          ),
        ),
      );
    } on BusFeedbackException catch (
    error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            error.message,
          ),
        ),
      );
    } on Object {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to submit feedback.',
          ),
        ),
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
  Widget build(
      BuildContext context,
      ) {
    final issueTypes =
        _availableIssueTypes;

    final selectedIssue =
    _issueType != null &&
        issueTypes.contains(
          _issueType,
        )
        ? _issueType
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Report Bus / Stop Issue',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
          const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 650,
              ),
              child: Form(
                key:
                _formKey,
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .stretch,
                  children: [
                    const Icon(
                      Icons
                          .report_problem_outlined,
                      size: 56,
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    Text(
                      'Report a Transit Problem',
                      textAlign:
                      TextAlign.center,
                      style:
                      Theme.of(context)
                          .textTheme
                          .headlineSmall,
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    const Text(
                      'Choose the related route and bus stop, then describe the problem.',
                      textAlign:
                      TextAlign.center,
                    ),

                    const SizedBox(
                      height: 24,
                    ),

                    Card(
                      child: Padding(
                        padding:
                        const EdgeInsets
                            .all(16),
                        child: Row(
                          crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                          children: [
                            Icon(
                              Icons.schedule,
                              color:
                              Theme.of(
                                context,
                              )
                                  .colorScheme
                                  .primary,
                            ),

                            const SizedBox(
                              width: 12,
                            ),

                            Expanded(
                              child: Text(
                                _timingMessage,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (widget
                        .journeyOptions
                        .length >
                        1) ...[
                      const SizedBox(
                        height: 16,
                      ),

                      DropdownButtonFormField<
                          FeedbackJourneyOption>(
                        value:
                        _selectedJourneyOption,
                        decoration:
                        const InputDecoration(
                          labelText:
                          'Bus / Journey Leg',
                          border:
                          OutlineInputBorder(),
                          prefixIcon:
                          Icon(
                            Icons
                                .directions_bus_outlined,
                          ),
                        ),
                        items: widget
                            .journeyOptions
                            .map(
                              (option) {
                            return DropdownMenuItem<
                                FeedbackJourneyOption>(
                              value:
                              option,
                              child:
                              Text(
                                '${option.label} - ${option.routeLabel}',
                              ),
                            );
                          },
                        ).toList(),
                        onChanged:
                        _submitting
                            ? null
                            : _selectJourneyOption,
                        validator:
                            (value) {
                          if (value ==
                              null) {
                            return 'Please select the bus or journey leg.';
                          }

                          return null;
                        },
                      ),
                    ],

                    const SizedBox(
                      height: 16,
                    ),

                    if (widget
                        .hasJourneyContext)
                      Card(
                        child: ListTile(
                          leading:
                          const Icon(
                            Icons.route,
                          ),
                          title:
                          const Text(
                            'Route',
                          ),
                          subtitle: Text(
                            _selectedRouteLabel ??
                                'Select a journey leg',
                          ),
                        ),
                      )
                    else
                      Card(
                        clipBehavior:
                        Clip.antiAlias,
                        child: InkWell(
                          onTap:
                          _submitting
                              ? null
                              : _selectRoute,
                          child:
                          Padding(
                            padding:
                            const EdgeInsets
                                .all(16),
                            child:
                            Row(
                              children: [
                                Icon(
                                  Icons
                                      .route,
                                  color:
                                  Theme.of(
                                    context,
                                  )
                                      .colorScheme
                                      .primary,
                                ),

                                const SizedBox(
                                  width:
                                  16,
                                ),

                                Expanded(
                                  child:
                                  Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                    children: [
                                      const Text(
                                        'Route',
                                      ),
                                      const SizedBox(
                                        height:
                                        4,
                                      ),
                                      Text(
                                        _selectedRoute
                                            ?.displayName ??
                                            'Tap to search and select a route',
                                      ),
                                    ],
                                  ),
                                ),

                                const Icon(
                                  Icons
                                      .chevron_right,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(
                      height: 12,
                    ),

                    Card(
                      clipBehavior:
                      Clip.antiAlias,
                      child: InkWell(
                        onTap:
                        _submitting ||
                            _selectedRouteId ==
                                null
                            ? null
                            : _selectStop,
                        child: Padding(
                          padding:
                          const EdgeInsets
                              .all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons
                                    .location_on_outlined,
                                color:
                                _selectedRouteId ==
                                    null
                                    ? Theme.of(
                                  context,
                                )
                                    .disabledColor
                                    : Theme.of(
                                  context,
                                )
                                    .colorScheme
                                    .primary,
                              ),

                              const SizedBox(
                                width: 16,
                              ),

                              Expanded(
                                child:
                                Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                                  children: [
                                    const Text(
                                      'Related Bus Stop',
                                    ),

                                    const SizedBox(
                                      height:
                                      4,
                                    ),

                                    Text(
                                      _selectedRouteId ==
                                          null
                                          ? 'Select a route first'
                                          : _selectedStop
                                          ?.name ??
                                          'Tap to search related bus stops',
                                    ),
                                  ],
                                ),
                              ),

                              const Icon(
                                Icons
                                    .chevron_right,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    DropdownButtonFormField<
                        String>(
                      value:
                      selectedIssue,
                      isExpanded: true,
                      decoration:
                      const InputDecoration(
                        labelText:
                        'Problem Type',
                        border:
                        OutlineInputBorder(),
                        prefixIcon:
                        Icon(
                          Icons
                              .error_outline,
                        ),
                      ),
                      items:
                      issueTypes.map(
                            (issue) {
                          return DropdownMenuItem<
                              String>(
                            value:
                            issue,
                            child:
                            Text(
                              issue,
                            ),
                          );
                        },
                      ).toList(),
                      onChanged:
                      _submitting
                          ? null
                          : (value) {
                        setState(
                              () {
                            _issueType =
                                value;
                          },
                        );
                      },
                      validator:
                          (value) {
                        if (value ==
                            null ||
                            value
                                .isEmpty) {
                          return 'Please select a problem type.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    TextFormField(
                      controller:
                      _commentController,
                      enabled:
                      !_submitting,
                      minLines: 4,
                      maxLines: 6,
                      maxLength: 500,
                      decoration:
                      const InputDecoration(
                        labelText:
                        'Describe the Problem',
                        hintText:
                        'Include useful details such as the approximate time and what happened.',
                        border:
                        OutlineInputBorder(),
                        alignLabelWithHint:
                        true,
                      ),
                      validator:
                          (value) {
                        final text =
                            value
                                ?.trim() ??
                                '';

                        if (text.isEmpty) {
                          return 'Please describe the problem.';
                        }

                        if (text.length <
                            5) {
                          return 'Please provide more detail.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(
                      height: 24,
                    ),

                    FilledButton.icon(
                      onPressed:
                      _submitting
                          ? null
                          : _submitFeedback,
                      icon: _submitting
                          ? const SizedBox
                          .square(
                        dimension:
                        18,
                        child:
                        CircularProgressIndicator(
                          strokeWidth:
                          2,
                        ),
                      )
                          : const Icon(
                        Icons.send,
                      ),
                      label: Text(
                        _submitting
                            ? 'Submitting...'
                            : 'Submit Report',
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