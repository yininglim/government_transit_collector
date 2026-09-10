const maxAdditionalBusPlanningCount = 100;
const maxAdditionalDriverPlanningCount = 500;
const additionalDieselBusCostRm = 700000;
const lowMonthlyDriverCostRm = 2500;
const highMonthlyDriverCostRm = 3500;
const additionalDieselBusCostSource =
    'Publicly reported Prasarana diesel-bus procurement benchmark';
const monthlyDriverCostSource =
    'Johor and Johor Bahru bus-operator Bus Captain monthly income range';

class CostPlanningContext {
  const CostPlanningContext({
    required this.routeId,
    required this.busFrequencyAction,
    this.additionalBuses,
    this.additionalDrivers,
    this.estimatedBusAcquisitionCostRm,
    this.lowMonthlyDriverCostRm,
    this.highMonthlyDriverCostRm,
  });

  final String routeId;
  final String busFrequencyAction;
  final int? additionalBuses;
  final int? additionalDrivers;
  final int? estimatedBusAcquisitionCostRm;
  final int? lowMonthlyDriverCostRm;
  final int? highMonthlyDriverCostRm;
}

class CostPlanningValidation {
  const CostPlanningValidation(this.value, this.error);

  final int? value;
  final String? error;

  bool get isValid => value != null;
}

CostPlanningValidation parseNonNegativeResource(
  String raw,
  String label, {
  required int maximum,
}) {
  final value = raw.trim();
  if (value.isEmpty) return const CostPlanningValidation(null, null);
  final normalized = value.contains(',')
      ? (RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(value)
            ? value.replaceAll(',', '')
            : value)
      : value;
  if (value.startsWith('-') && int.tryParse(value) != null) {
    return CostPlanningValidation(null, '$label cannot be negative.');
  }
  if (normalized.contains('.') || !RegExp(r'^\d+$').hasMatch(normalized)) {
    return const CostPlanningValidation(null, 'Enter a valid whole number.');
  }
  final parsed = int.tryParse(normalized);
  if (parsed == null || parsed > maximum) {
    return CostPlanningValidation(
      null,
      '$label must be between 0 and $maximum.',
    );
  }
  return CostPlanningValidation(parsed, null);
}
