import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/authentication/presentation/auth_validation.dart';

void main() {
  for (final email in [
    'abc',
    'abc@',
    '@gmail.com',
    'abc@gmail',
    '1=1',
    '1==1',
    'a..b@example.com',
    'a@-example.com',
  ]) {
    test('rejects malformed email $email', () {
      expect(
        AuthValidation.email(email),
        'Please enter a valid email address.',
      );
    });
  }
  test('valid emails are trimmed and accepted without SQL special cases', () {
    expect(AuthValidation.email(' user@example.com '), isNull);
    expect(AuthValidation.email('user+tag@example.com'), isNull);
    expect(AuthValidation.email('1=1@example.com'), isNull);
  });
  for (final password in ['1=1', '1==1', '1234567']) {
    test('short password fails length validation', () {
      expect(
        AuthValidation.newPassword(password),
        'Password must be at least 8 characters.',
      );
    });
  }
  test('new password rejects trimmed case-insensitive email equality', () {
    expect(
      AuthValidation.newPassword(
        ' USER@example.com ',
        email: 'user@EXAMPLE.com ',
      ),
      'Password cannot be the same as your email address.',
    );
    expect(
      AuthValidation.newPassword('valid-password', email: 'user@example.com'),
      isNull,
    );
  });
  test('new password cannot equal current password', () {
    expect(
      AuthValidation.newPassword('password123', currentPassword: 'password123'),
      'New password must be different from your current password.',
    );
  });
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
        'Please enter a valid email address.',
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
