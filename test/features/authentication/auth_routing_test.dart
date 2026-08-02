import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/authentication/presentation/auth_gate.dart';

void main() {
  group('role routing', () {
    test('routes passengers to passenger home', () {
      expect(destinationForRole('passenger'), AuthDestination.passenger);
    });

    test('routes admins to admin home', () {
      expect(destinationForRole('admin'), AuthDestination.admin);
    });

    test('rejects unknown roles', () {
      expect(destinationForRole('unknown'), AuthDestination.unsupported);
    });
  });
}
