import 'package:government_transit_collector/core/widgets/readable_app_bar.dart';
import 'package:flutter/material.dart';
import '../data/bus_feedback_repository.dart';
import '../data/feedback_reference_repository.dart';
import '../../passenger_profile/presentation/my_reports_section.dart';
import 'bus_feedback_page.dart';

class PassengerReportsPage extends StatefulWidget {
  const PassengerReportsPage({
    this.showPageHeader = true,
    required this.userId,
    this.repository,
    this.referenceRepository,
    super.key,
  });
  final String userId;
  final BusFeedbackRepository? repository;
  final FeedbackReferenceRepository? referenceRepository;

  final bool showPageHeader;

  @override
  State<PassengerReportsPage> createState() => _PassengerReportsPageState();
}

class _PassengerReportsPageState extends State<PassengerReportsPage> {
  int _revision = 0;
  Future<void> _report() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BusFeedbackPage(
          repository: widget.repository ?? SupabaseBusFeedbackRepository(),
          referenceRepository:
              widget.referenceRepository ??
              SupabaseFeedbackReferenceRepository(),
        ),
      ),
    );
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.showPageHeader ? readableAppBar(context, title: const Text('Reports')) : null,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Report a Transit Issue',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tell us about a bus journey, route, bus stop or walking distance.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const Key('general-feedback-button'),
                        onPressed: _report,
                        icon: const Icon(Icons.feedback_outlined),
                        label: const Text('Report Bus / Stop Issue'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('My Reports', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              MyReportsSection(
                key: ValueKey(_revision),
                userId: widget.userId,
                repository: widget.repository,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
