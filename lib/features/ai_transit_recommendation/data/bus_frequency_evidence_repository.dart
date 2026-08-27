import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_repository.dart';

abstract interface class BusFrequencyEvidenceRepository {
  Future<BusFrequencyEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  });
}

class DefaultBusFrequencyEvidenceRepository
    implements BusFrequencyEvidenceRepository {
  DefaultBusFrequencyEvidenceRepository({
    ScheduledServiceEvidenceRepository? scheduledServiceRepository,
    OperationalEvidenceRepository? operationalRepository,
    AdminFeedbackRepository? feedbackRepository,
  }) : _scheduledServiceRepository =
           scheduledServiceRepository ??
           DefaultScheduledServiceEvidenceRepository(),
       _operationalRepository =
           operationalRepository ?? DefaultOperationalEvidenceRepository(),
       _feedbackRepository =
           feedbackRepository ?? DefaultAdminFeedbackRepository();

  final ScheduledServiceEvidenceRepository _scheduledServiceRepository;
  final OperationalEvidenceRepository _operationalRepository;
  final AdminFeedbackRepository _feedbackRepository;

  @override
  Future<BusFrequencyEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    if (!endExclusiveUtc.isAfter(startUtc)) {
      throw const BusFrequencyEvidenceReadException(
        'The analysis period is invalid.',
      );
    }
    try {
      final results = await Future.wait([
        _scheduledServiceRepository.loadEvidence(
          routeId: routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        ),
        _operationalRepository.loadEvidence(
          routeId: routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        ),
        _feedbackRepository.loadFeedback(
          routeId: routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        ),
      ]);
      final scheduled = results[0] as ScheduledServiceEvidence;
      final operational = results[1] as AiOperationalEvidence;
      final records = results[2] as List<AdminFeedbackRecord>;
      final counts = <String, int>{};
      for (final record in records) {
        counts.update(
          record.issueType,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      final relevantRecords = records
          .where(
            (record) => BusFrequencyFeedbackIssueTypes.frequencyRelevant
                .contains(record.issueType),
          )
          .toList(growable: false);

      return BusFrequencyEvidence(
        routeId: routeId,
        periodStart: startUtc,
        periodEnd: endExclusiveUtc,
        scheduledService: scheduled,
        operational: operational,
        feedback: BusFrequencyFeedbackEvidence(
          records: List.unmodifiable(records),
          countByIssueType: Map.unmodifiable(counts),
          frequencyRelevantRecords: relevantRecords,
        ),
      );
    } on BusFrequencyEvidenceReadException {
      rethrow;
    } on Object {
      throw const BusFrequencyEvidenceReadException(
        'Unable to load bus frequency evidence.',
      );
    }
  }
}

class BusFrequencyEvidenceReadException implements Exception {
  const BusFrequencyEvidenceReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
