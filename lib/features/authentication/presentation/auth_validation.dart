abstract final class AuthValidation {
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String? requiredField(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    return null;
  }

  static String? email(String? value) {
    final requiredError = requiredField(value, 'Email');
    if (requiredError != null) return requiredError;
    if (!_emailPattern.hasMatch(value!.trim())) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? password(String? value) {
    final requiredError = requiredField(value, 'Password');
    if (requiredError != null) return requiredError;
    if (value!.length < 8) {
      return 'Password must contain at least 8 characters.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    final requiredError = requiredField(value, 'Confirm password');
    if (requiredError != null) return requiredError;
    if (value != password) return 'Passwords do not match.';
    return null;
  }
}
