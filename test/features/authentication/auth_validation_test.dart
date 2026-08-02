import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/authentication/presentation/auth_validation.dart';

void main() {
  group('registration validation', () {
    test('rejects empty required fields', () {
      expect(
        AuthValidation.requiredField('', 'Full name'),
        'Full name is required.',
      );
      expect(AuthValidation.email(''), 'Email is required.');
      expect(AuthValidation.password(''), 'Password is required.');
    });

    test('rejects an invalid email', () {
      expect(
        AuthValidation.email('not-an-email'),
        'Enter a valid email address.',
      );
    });

    test('rejects a password mismatch', () {
      expect(
        AuthValidation.confirmPassword('different1', 'password1'),
        'Passwords do not match.',
      );
    });
  });
}
