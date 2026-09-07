import 'package:flutter/material.dart';
import 'journey_reminder.dart';
import 'reminder_controller.dart';

Future<void> showReminderSheet(
  BuildContext context,
  ReminderController controller,
  ReminderJourney journey,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => ReminderSheet(controller: controller, journey: journey),
);

class ReminderSheet extends StatefulWidget {
  const ReminderSheet({
    required this.controller,
    required this.journey,
    super.key,
  });
  final ReminderController controller;
  final ReminderJourney journey;
  @override
  State<ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<ReminderSheet> {
  int offset = 10;
  bool saving = false;
  String? error;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Set Departure Reminder',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        JourneyReminderSummary(journey: widget.journey),
        const SizedBox(height: 12),
        RadioGroup<int>(
          groupValue: offset,
          onChanged: (value) {
            if (!saving && value != null) {
              setState(() {
                offset = value;
                error = null;
              });
            }
          },
          child: Column(
            children: [
              for (final value in reminderOffsets)
                RadioListTile<int>(
                  value: value,
                  title: Text('$value minutes before'),
                ),
            ],
          ),
        ),
        const Text(
          'Android notification and alarm permission are needed for a timely reminder.',
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: saving
              ? null
              : () async {
                  setState(() {
                    saving = true;
                    error = null;
                  });
                  try {
                    await widget.controller.set(widget.journey, offset);
                    if (context.mounted) Navigator.pop(context);
                  } on Object catch (e) {
                    if (mounted) {
                      setState(() {
                        error = e is ReminderException
                            ? e.message
                            : 'Unable to set reminder. Please try again.';
                        saving = false;
                      });
                    }
                  }
                },
          child: Text(saving ? 'Setting Reminder…' : 'Set Reminder'),
        ),
      ],
    ),
  );
}

class JourneyReminderSummary extends StatelessWidget {
  const JourneyReminderSummary({
    required this.journey,
    this.reminderAt,
    super.key,
  });
  final ReminderJourney journey;
  final DateTime? reminderAt;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(journey.route, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text('${journey.origin} → ${journey.destination}'),
      const SizedBox(height: 8),
      Text('Departure: ${reminderDisplayTime(journey.departure)}'),
      if (reminderAt != null)
        Text('Reminder: ${reminderDisplayTime(reminderAt!)}'),
    ],
  );
}

Future<void> cancelJourneyReminder(
  BuildContext context,
  ReminderController controller,
  JourneyReminder reminder,
) async {
  try {
    await controller.cancel(reminder);
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to finish cancelling the reminder. Please retry.',
          ),
        ),
      );
    }
  }
}

Future<void> showExistingReminder(
  BuildContext context,
  ReminderController controller,
  JourneyReminder reminder,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Reminder Set'),
    content: SingleChildScrollView(
      child: JourneyReminderSummary(
        journey: reminder.journey,
        reminderAt: reminder.reminderAt,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Close'),
      ),
      TextButton(
        onPressed: () async {
          await cancelJourneyReminder(context, controller, reminder);
          if (dialogContext.mounted) Navigator.pop(dialogContext);
        },
        child: const Text('Cancel Reminder'),
      ),
    ],
  ),
);

class UpcomingJourneys extends StatefulWidget {
  const UpcomingJourneys({required this.controller, super.key});
  final ReminderController controller;
  @override
  State<UpcomingJourneys> createState() => _UpcomingJourneysState();
}

class _UpcomingJourneysState extends State<UpcomingJourneys>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final reminders = widget.controller.upcoming;
      if (reminders.isEmpty && widget.controller.error == null) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Upcoming Journey',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (widget.controller.error != null)
            TextButton(
              onPressed: widget.controller.refresh,
              child: Text(widget.controller.error!),
            ),
          for (final reminder in reminders)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    JourneyReminderSummary(
                      journey: reminder.journey,
                      reminderAt: reminder.reminderAt,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                appBar: AppBar(
                                  title: const Text('Journey Summary'),
                                ),
                                body: SafeArea(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        JourneyReminderSummary(
                                          journey: reminder.journey,
                                          reminderAt: reminder.reminderAt,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Service date: ${reminder.journey.data['service_date']}',
                                        ),
                                        const Text(
                                          'Saved scheduled journey. Live status is not available in this summary.',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          child: const Text('View Journey'),
                        ),
                        TextButton(
                          onPressed: () => cancelJourneyReminder(
                            context,
                            widget.controller,
                            reminder,
                          ),
                          child: const Text('Cancel Reminder'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      );
    },
  );
}
