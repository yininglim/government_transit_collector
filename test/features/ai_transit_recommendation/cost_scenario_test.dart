import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_scenario.dart';

void main() {
  test('additional bus planning limit accepts 100 and rejects 101', () {
    final accepted = parseNonNegativeResource(
      '100',
      'Additional buses',
      maximum: maxAdditionalBusPlanningCount,
    );
    final rejected = parseNonNegativeResource(
      '101',
      'Additional buses',
      maximum: maxAdditionalBusPlanningCount,
    );

    expect(accepted.value, 100);
    expect(accepted.error, isNull);
    expect(rejected.value, isNull);
    expect(rejected.error, 'Additional buses must be between 0 and 100.');
  });

  test('additional driver planning limit accepts 500 and rejects 501', () {
    final accepted = parseNonNegativeResource(
      '500',
      'Additional drivers',
      maximum: maxAdditionalDriverPlanningCount,
    );
    final rejected = parseNonNegativeResource(
      '501',
      'Additional drivers',
      maximum: maxAdditionalDriverPlanningCount,
    );

    expect(accepted.value, 500);
    expect(accepted.error, isNull);
    expect(rejected.value, isNull);
    expect(rejected.error, 'Additional drivers must be between 0 and 500.');
  });

  test('blank resource planning input remains optional', () {
    final buses = parseNonNegativeResource(
      '   ',
      'Additional buses',
      maximum: maxAdditionalBusPlanningCount,
    );
    final drivers = parseNonNegativeResource(
      '',
      'Additional drivers',
      maximum: maxAdditionalDriverPlanningCount,
    );

    expect(buses.value, isNull);
    expect(buses.error, isNull);
    expect(drivers.value, isNull);
    expect(drivers.error, isNull);
  });
}
