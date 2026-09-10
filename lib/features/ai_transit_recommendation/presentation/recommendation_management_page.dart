import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_priority.dart';

class RecommendationManagementPage extends StatefulWidget {
  const RecommendationManagementPage({this.repository, super.key});

  final RecommendationManagementRepository? repository;

  @override
  State<RecommendationManagementPage> createState() =>
      _RecommendationManagementPageState();
}

class _RecommendationManagementPageState
    extends State<RecommendationManagementPage> {
  late final RecommendationManagementRepository _repository;
  List<SavedRecommendation> _records = const [];
  _FeatureFilter _featureFilter = _FeatureFilter.all;
  _StatusFilter _statusFilter = _StatusFilter.all;
  _PriorityFilter _priorityFilter = _PriorityFilter.all;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? DefaultRecommendationManagementRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final records = await _repository.loadSavedRecommendations();
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  List<SavedRecommendation> get _visibleRecords {
    final result = _records
        .where(
          (record) =>
              _featureFilter.includes(record.feature) &&
              _statusFilter.includes(record.status) &&
              _priorityFilter.includes(record.priorityLevel),
        )
        .toList(growable: false);
    result.sort((left, right) {
      final priority = _prioritySortValue(
        left.priorityLevel,
      ).compareTo(_prioritySortValue(right.priorityLevel));
      return priority != 0
          ? priority
          : right.createdAt.compareTo(left.createdAt);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recommendation Management')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Recommendation Management',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Review and manage saved AI recommendations.'),
          const SizedBox(height: 20),
          if (_loading)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Row(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Expanded(child: Text('Loading saved recommendations...')),
                  ],
                ),
              ),
            )
          else if (_failed)
            _failureCard()
          else ...[
            _filters(),
            const SizedBox(height: 16),
            if (_records.isEmpty)
              _emptyCard(
                'No Saved Recommendations',
                'Save a recommendation from Bus Frequency or Route & Bus Stop Recommendation to review it here.',
              )
            else if (_visibleRecords.isEmpty)
              _emptyCard(
                'No Matching Recommendations',
                'No saved recommendations match the selected filters.',
              )
            else
              for (final record in _visibleRecords) ...[
                _recommendationCard(record),
                const SizedBox(height: 12),
              ],
          ],
        ],
      ),
    ),
  );

  Widget _filters() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Feature', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in _FeatureFilter.values)
                FilterChip(
                  key: Key('management-feature-${filter.name}'),
                  label: Text(filter.label),
                  selected: _featureFilter == filter,
                  onSelected: (_) => setState(() => _featureFilter = filter),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Status', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in _StatusFilter.values)
                FilterChip(
                  key: Key('management-status-${filter.name}'),
                  label: Text(filter.label),
                  selected: _statusFilter == filter,
                  onSelected: (_) => setState(() => _statusFilter = filter),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Priority', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in _PriorityFilter.values)
                FilterChip(
                  key: Key('management-priority-${filter.name}'),
                  label: Text(filter.label),
                  selected: _priorityFilter == filter,
                  onSelected: (_) =>
                      setState(() => _priorityFilter = filter),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _recommendationCard(SavedRecommendation record) => Card(
    key: Key('saved-recommendation-${record.recommendationId}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            record.routeDisplayLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(recommendationFeatureLabel(record.feature))),
              Chip(label: Text(recommendationStatusLabel(record.status))),
              Chip(
                label: Text(
                  record.priorityLevel == null
                      ? 'Not Ranked'
                      : recommendationPriorityLabel(record.priorityLevel!),
                ),
              ),
              Chip(
                label: Text(
                  'Follow-up: ${record.followUp == null ? 'Not Created' : recommendationFollowUpStatusLabel(record.followUp!.status)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final action in record.actions)
            Text(
              recommendationActionLabel(action),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 8),
          Text('Saved ${_dateTime(record.createdAt)}'),
          const SizedBox(height: 8),
          Text(record.rationale, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: Key('view-saved-${record.recommendationId}'),
              onPressed: () => _openDetails(record),
              child: const Text('View Details'),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _openDetails(SavedRecommendation record) async {
    final outcome = await Navigator.of(context).push<_DetailOutcome>(
      MaterialPageRoute(
        builder: (_) => RecommendationManagementDetailPage(
          recommendation: record,
          repository: _repository,
        ),
      ),
    );
    if (!mounted || outcome == null) return;
    if (outcome.deleted) {
      setState(() {
        _records = _records
            .where((item) => item.recommendationId != record.recommendationId)
            .toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recommendation deleted.')),
      );
    } else if (outcome.recommendation case final updated?) {
      setState(() {
        _records = [
          for (final item in _records)
            if (item.recommendationId == updated.recommendationId)
              updated
            else
              item,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recommendation updated.')),
      );
    }
  }

  Widget _failureCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Unable to load saved recommendations.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  Widget _emptyCard(String title, String message) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message),
        ],
      ),
    ),
  );
}

class RecommendationManagementDetailPage extends StatefulWidget {
  const RecommendationManagementDetailPage({
    required this.recommendation,
    required this.repository,
    super.key,
  });

  final SavedRecommendation recommendation;
  final RecommendationManagementRepository repository;

  @override
  State<RecommendationManagementDetailPage> createState() =>
      _RecommendationManagementDetailPageState();
}

class _RecommendationManagementDetailPageState
    extends State<RecommendationManagementDetailPage> {
  late SavedRecommendation _recommendation;
  late RecommendationReviewStatus _status;
  late final TextEditingController _noteController;
  late final TextEditingController _followUpActionController;
  late final TextEditingController _followUpNoteController;
  DateTime? _followUpDueDate;
  RecommendationFollowUpStatus _followUpStatus =
      RecommendationFollowUpStatus.pending;
  String? _followUpActionError;
  String? _followUpDueDateError;
  bool _saving = false;
  bool _deleting = false;
  bool _savingFollowUp = false;
  bool _followUpChanged = false;

  @override
  void initState() {
    super.initState();
    _recommendation = widget.recommendation;
    _status = _recommendation.status;
    _noteController = TextEditingController(text: _recommendation.adminNote);
    final followUp = _recommendation.followUp;
    _followUpActionController = TextEditingController(
      text: followUp?.actionText,
    );
    _followUpNoteController = TextEditingController(text: followUp?.note);
    _followUpDueDate = followUp?.dueDate;
    _followUpStatus = followUp?.status ?? RecommendationFollowUpStatus.pending;
  }

  @override
  void dispose() {
    _noteController.dispose();
    _followUpActionController.dispose();
    _followUpNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
    onWillPop: () async {
      _closeDetails();
      return false;
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Saved Recommendation'),
        leading: IconButton(
          onPressed: _closeDetails,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Recommendation Details', [
            _detail('Route', _recommendation.routeDisplayLabel),
            _detail('Feature', recommendationFeatureLabel(_recommendation.feature)),
            _detail(
              'Recommendation Action',
              _recommendation.actions.map(recommendationActionLabel).join(', '),
            ),
            _detail('Saved', _dateTime(_recommendation.createdAt)),
            _detail(
              'Priority',
              _recommendation.priorityLevel == null
                  ? 'Not Ranked'
                  : recommendationPriorityLabel(
                      _recommendation.priorityLevel!,
                    ),
            ),
          ]),
          if (_recommendation.priorityReasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            _section(
              'Priority Reasons',
              [
                for (final reason in _recommendation.priorityReasons)
                  Text(reason),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _section('AI Rationale', [Text(_recommendation.rationale)]),
          if (_recommendation.evidenceReferences.isNotEmpty) ...[
            const SizedBox(height: 12),
            _section(
              'Supporting Evidence',
              [for (final reference in _recommendation.evidenceReferences) Text(reference)],
            ),
          ],
          if (_recommendation.limitations.isNotEmpty) ...[
            const SizedBox(height: 12),
            _section(
              'Limitations',
              [for (final limitation in _recommendation.limitations) Text(limitation)],
            ),
          ],
          if (_recommendation.targetStopIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            _section(
              'Target Stops',
              [for (final stopId in _recommendation.targetStopIds) Text(stopId)],
            ),
          ],
          if (_recommendation.candidateArea case final area?) ...[
            const SizedBox(height: 12),
            _section('Candidate Area', [
              Text(area['area_description']?.toString() ?? 'Available'),
              if (area['from_stop_name'] != null && area['to_stop_name'] != null)
                Text('${area['from_stop_name']} — ${area['to_stop_name']}'),
            ]),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Administrative Review', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (_recommendation.status ==
                      RecommendationReviewStatus.pending)
                    DropdownButtonFormField<RecommendationReviewStatus>(
                      value: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        for (final status in RecommendationReviewStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(recommendationStatusLabel(status)),
                          ),
                      ],
                      onChanged: _saving || _deleting || _savingFollowUp
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _status = value);
                              }
                            },
                    )
                  else
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Status'),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${recommendationStatusLabel(_recommendation.status)} (Final)',
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('admin-note'),
                    controller: _noteController,
                    minLines: 3,
                    maxLines: 6,
                    enabled: !_saving && !_deleting && !_savingFollowUp,
                    decoration: const InputDecoration(labelText: 'Admin Note'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('save-management-changes'),
                    onPressed: _saving || _deleting || _savingFollowUp
                        ? null
                        : _saveChanges,
                    child: Text(_saving ? 'Saving...' : 'Save Changes'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('delete-saved-recommendation'),
                    onPressed: _saving || _deleting || _savingFollowUp
                        ? null
                        : _confirmDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(_deleting ? 'Deleting...' : 'Delete Recommendation'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _followUpSection(),
        ],
      ),
    ),
    ),
  );

  void _closeDetails() => Navigator.of(context).pop(
    _followUpChanged
        ? _DetailOutcome(recommendation: _recommendation)
        : null,
  );

  Widget _followUpSection() {
    final followUp = _recommendation.followUp;
    if (followUp == null &&
        _recommendation.status == RecommendationReviewStatus.rejected) {
      return const SizedBox.shrink();
    }
    if (followUp == null &&
        _recommendation.status == RecommendationReviewStatus.pending) {
      return _section('Follow-up Action', [
        const Text(
          'A follow-up action can be created after this recommendation is Accepted.',
        ),
      ]);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              followUp == null ? 'Create Follow-up Action' : 'Follow-up Action',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (followUp != null &&
                _recommendation.status != RecommendationReviewStatus.accepted) ...[
              const SizedBox(height: 8),
              const Text(
                'This follow-up is retained for history because the recommendation is no longer Accepted.',
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('follow-up-action'),
              controller: _followUpActionController,
              minLines: 2,
              maxLines: 4,
              enabled: !_savingFollowUp && !_saving && !_deleting,
              decoration: InputDecoration(
                labelText: 'Action / Task',
                errorText: _followUpActionError,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              key: const Key('follow-up-due-date'),
              onTap: _savingFollowUp || _saving || _deleting
                  ? null
                  : _selectFollowUpDueDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Due Date',
                  errorText: _followUpDueDateError,
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                ),
                child: Text(
                  _followUpDueDate == null
                      ? 'Select a date'
                      : _dateOnlyLabel(_followUpDueDate!),
                ),
              ),
            ),
            if (followUp != null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<RecommendationFollowUpStatus>(
                key: const Key('follow-up-status'),
                value: _followUpStatus,
                decoration: const InputDecoration(
                  labelText: 'Follow-up Status',
                ),
                items: [
                  for (final status in RecommendationFollowUpStatus.values)
                    DropdownMenuItem(
                      value: status,
                      child: Text(recommendationFollowUpStatusLabel(status)),
                    ),
                ],
                onChanged: _savingFollowUp || _saving || _deleting
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _followUpStatus = value);
                        }
                      },
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('follow-up-note'),
              controller: _followUpNoteController,
              minLines: 3,
              maxLines: 6,
              enabled: !_savingFollowUp && !_saving && !_deleting,
              decoration: const InputDecoration(labelText: 'Follow-up Note'),
            ),
            if (followUp?.updatedAt case final updatedAt?) ...[
              const SizedBox(height: 12),
              Text('Last Updated ${_dateTime(updatedAt)}'),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('save-follow-up'),
              onPressed: _savingFollowUp || _saving || _deleting
                  ? null
                  : _saveFollowUp,
              child: Text(
                _savingFollowUp
                    ? 'Saving...'
                    : followUp == null
                    ? 'Create Follow-up Action'
                    : 'Save Follow-up Changes',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectFollowUpDueDate() async {
    final now = DateTime.now();
    final current = _followUpDueDate;
    final creating = _recommendation.followUp == null;
    final initialDate = current ?? DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: creating
          ? DateTime(now.year, now.month, now.day)
          : DateTime(2000),
      lastDate: DateTime(now.year + 20, 12, 31),
    );
    if (date == null || !mounted) return;
    setState(() {
      _followUpDueDate = date;
      _followUpDueDateError = null;
    });
  }

  Future<void> _saveFollowUp() async {
    final actionMissing = _followUpActionController.text.trim().isEmpty;
    final dueDateMissing = _followUpDueDate == null;
    final creating = _recommendation.followUp == null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDatePast = creating &&
        _followUpDueDate != null &&
        DateTime(
          _followUpDueDate!.year,
          _followUpDueDate!.month,
          _followUpDueDate!.day,
        ).isBefore(today);
    setState(() {
      _followUpActionError = actionMissing ? 'Enter an action or task.' : null;
      _followUpDueDateError = dueDateMissing
          ? 'Select a due date.'
          : dueDatePast
          ? 'Due date cannot be earlier than today.'
          : null;
    });
    if (actionMissing || dueDateMissing || dueDatePast) return;
    setState(() => _savingFollowUp = true);
    try {
      final updated = creating
          ? await widget.repository.createFollowUp(
              recommendation: _recommendation,
              actionText: _followUpActionController.text,
              dueDate: _followUpDueDate!,
              note: _followUpNoteController.text,
            )
          : await widget.repository.updateFollowUp(
              recommendation: _recommendation,
              actionText: _followUpActionController.text,
              dueDate: _followUpDueDate!,
              status: _followUpStatus,
              note: _followUpNoteController.text,
            );
      if (!mounted) return;
      setState(() {
        _recommendation = updated;
        _followUpStatus = updated.followUp!.status;
        _followUpDueDate = updated.followUp!.dueDate;
        _savingFollowUp = false;
        _followUpChanged = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            creating ? 'Follow-up action created.' : 'Follow-up action updated.',
          ),
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _savingFollowUp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            creating
                ? 'Unable to create this follow-up action.'
                : 'Unable to update this follow-up action.',
          ),
        ),
      );
    }
  }

  Future<void> _saveChanges() async {
    if (_recommendation.status == RecommendationReviewStatus.pending &&
        _status != RecommendationReviewStatus.pending) {
      final confirmed = await _confirmReviewDecision(_status);
      if (confirmed != true || !mounted) {
        if (mounted) {
          setState(() => _status = _recommendation.status);
        }
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final updated = await widget.repository.updateRecommendation(
        recommendation: _recommendation,
        status: _status,
        adminNote: _noteController.text,
      );
      if (!mounted) return;
      setState(() {
        _recommendation = updated;
        _status = updated.status;
        _saving = false;
      });
      Navigator.of(context).pop(
        _DetailOutcome(recommendation: updated),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update this recommendation.')),
      );
    }
  }

  Future<bool?> _confirmReviewDecision(
    RecommendationReviewStatus status,
  ) => showDialog<bool>(
    context: context,
    builder: (context) {
      final accepted = status == RecommendationReviewStatus.accepted;
      return AlertDialog(
        title: Text(
          accepted ? 'Accept Recommendation?' : 'Reject Recommendation?',
        ),
        content: Text(
          accepted
              ? 'Once accepted, this recommendation decision cannot be changed. You may create a follow-up action after acceptance.'
              : 'Once rejected, this recommendation decision cannot be changed and no follow-up action can be created.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(accepted ? 'Accept' : 'Reject'),
          ),
        ],
      );
    },
  );

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved recommendation?'),
        content: Text(
          _recommendation.followUp == null
              ? 'This removes the saved recommendation from Recommendation Management. It does not change the original generated result or any bus service data.'
              : 'This removes the saved recommendation and its follow-up action from Recommendation Management. It does not change the original generated result or any bus service data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.repository.deleteRecommendation(
        _recommendation.recommendationId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(const _DetailOutcome(deleted: true));
    } on Object {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to delete this recommendation.')),
      );
    }
  }

  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(value),
      ],
    ),
  );
}

class _DetailOutcome {
  const _DetailOutcome({this.recommendation, this.deleted = false});

  final SavedRecommendation? recommendation;
  final bool deleted;
}

enum _FeatureFilter {
  all('All'),
  busFrequency('Bus Frequency'),
  routeBusStop('Route & Bus Stop');

  const _FeatureFilter(this.label);
  final String label;

  bool includes(RecommendationManagementFeature feature) => switch (this) {
    _FeatureFilter.all => true,
    _FeatureFilter.busFrequency => feature == RecommendationManagementFeature.busFrequency,
    _FeatureFilter.routeBusStop => feature == RecommendationManagementFeature.routeBusStop,
  };
}

enum _StatusFilter {
  all('All'),
  pending('Pending'),
  accepted('Accepted'),
  rejected('Rejected');

  const _StatusFilter(this.label);
  final String label;

  bool includes(RecommendationReviewStatus status) => switch (this) {
    _StatusFilter.all => true,
    _StatusFilter.pending => status == RecommendationReviewStatus.pending,
    _StatusFilter.accepted => status == RecommendationReviewStatus.accepted,
    _StatusFilter.rejected => status == RecommendationReviewStatus.rejected,
  };
}

enum _PriorityFilter {
  all('All'),
  high('High'),
  medium('Medium'),
  low('Low');

  const _PriorityFilter(this.label);
  final String label;

  bool includes(RecommendationPriorityLevel? priority) => switch (this) {
    _PriorityFilter.all => true,
    _PriorityFilter.high => priority == RecommendationPriorityLevel.high,
    _PriorityFilter.medium => priority == RecommendationPriorityLevel.medium,
    _PriorityFilter.low => priority == RecommendationPriorityLevel.low,
  };
}

int _prioritySortValue(RecommendationPriorityLevel? priority) =>
    switch (priority) {
      RecommendationPriorityLevel.high => 0,
      RecommendationPriorityLevel.medium => 1,
      RecommendationPriorityLevel.low => 2,
      null => 3,
    };

String _dateTime(DateTime value) {
  final local = value.toLocal();
  final date = '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

String _dateOnlyLabel(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
