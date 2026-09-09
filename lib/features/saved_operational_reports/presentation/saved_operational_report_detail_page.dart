import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report_repository.dart';

class SavedOperationalReportDetailPage extends StatefulWidget {
  const SavedOperationalReportDetailPage({
    required this.report,
    required this.repository,
    super.key,
  });

  final SavedOperationalReport report;
  final SavedOperationalReportRepository repository;

  @override
  State<SavedOperationalReportDetailPage> createState() =>
      _SavedOperationalReportDetailPageState();
}

class _SavedOperationalReportDetailPageState
    extends State<SavedOperationalReportDetailPage> {
  late SavedOperationalReport _report;
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late SavedOperationalReportStatus _status;
  bool _saving = false;
  bool _deleting = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _titleController = TextEditingController(text: _report.title);
    _notesController = TextEditingController(text: _report.adminNotes ?? '');
    _status = _report.status;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _titleError = 'Title cannot be blank.');
      return;
    }
    setState(() {
      _saving = true;
      _titleError = null;
    });
    try {
      final updated = await widget.repository.updateManagementMetadata(
        reportId: _report.reportId,
        title: _titleController.text,
        adminNotes: _notesController.text,
        status: _status,
      );
      if (!mounted) return;
      setState(() {
        _report = updated;
        _titleController.text = updated.title;
        _notesController.text = updated.adminNotes ?? '';
        _status = updated.status;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report updated successfully.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved report?'),
        content: const Text(
          'This removes the historical report permanently. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.repository.deleteReport(_report.reportId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Operational Report'),
      actions: [
        IconButton(
          tooltip: 'Delete report',
          onPressed: _saving || _deleting ? null : _delete,
          icon: _deleting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            title: 'Management details',
            icon: Icons.edit_note,
            children: [
              TextField(
                key: const Key('report-title-field'),
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  border: const OutlineInputBorder(),
                  errorText: _titleError,
                ),
                onChanged: (_) {
                  if (_titleError != null) setState(() => _titleError = null);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SavedOperationalReportStatus>(
                key: const Key('report-status-field'),
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: SavedOperationalReportStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(status.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _status = value);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('report-notes-field'),
                controller: _notesController,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Admin notes',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('save-report-metadata'),
                  onPressed: _saving || _deleting ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save changes'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            title: 'Report source',
            icon: Icons.info_outline,
            children: [
              _fact('Report type', _report.reportType.label),
              _fact(
                'Route',
                _report.routeId == null
                    ? 'All Routes'
                    : _report.routeNameSnapshot,
              ),
              _fact(
                'Analysis period',
                '${_dateTime(_report.periodStart)} – ${_dateTime(_report.periodEnd)}',
              ),
              _fact('Created by', _report.adminId),
              _fact('Created', _dateTime(_report.createdAt)),
              _fact('Last updated', _dateTime(_report.updatedAt)),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            title: 'Result snapshot',
            icon: Icons.assessment_outlined,
            children: _snapshotRows(_report.resultSnapshot),
          ),
        ],
      ),
    ),
  );

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 2),
        SelectableText(value),
      ],
    ),
  );

  List<Widget> _snapshotRows(Map<String, dynamic> snapshot) {
    if (snapshot.isEmpty) {
      return const [Text('No result values were stored in this snapshot.')];
    }
    final entries = snapshot.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map((entry) => _fact(_humanize(entry.key), _value(entry.value)))
        .toList(growable: false);
  }
}

String _humanize(String value) {
  final words = value.replaceAll('_', ' ').trim().split(RegExp(r'\s+'));
  return words
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

String _value(Object? value) {
  if (value == null) return 'Not available';
  if (value is List) return value.map(_value).join(', ');
  if (value is Map) {
    return value.entries
        .map((entry) => '${_humanize('${entry.key}')}: ${_value(entry.value)}')
        .join('\n');
  }
  return '$value';
}

String _dateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
