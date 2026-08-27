import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';

class BusFrequencyEvidence {
  const BusFrequencyEvidence({
    required this.routeId,
    required this.periodStart,
    required this.periodEnd,
    required this.scheduledService,
    required this.operational,
    required this.feedback,
  });

  final String routeId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final ScheduledServiceEvidence scheduledService;
  final AiOperationalEvidence operational;
  final BusFrequencyFeedbackEvidence feedback;
}

class BusFrequencyFeedbackEvidence {
  const BusFrequencyFeedbackEvidence({
    required this.records,
    required this.countByIssueType,
    required this.frequencyRelevantRecords,
  });

  final List<AdminFeedbackRecord> records;
  final Map<String, int> countByIssueType;
  final List<AdminFeedbackRecord> frequencyRelevantRecords;

  int get totalRecordCount => records.length;
  int get frequencyRelevantRecordCount => frequencyRelevantRecords.length;
}

abstract final class BusFrequencyFeedbackIssueTypes {
  static const busWasLate = 'Bus was late';
  static const busOvercrowded = 'Bus overcrowded';
  static const busDidNotArrive = 'Bus did not arrive';

  static const frequencyRelevant = {
    busWasLate,
    busOvercrowded,
    busDidNotArrive,
  };
}
