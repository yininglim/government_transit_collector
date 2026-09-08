abstract final class AuthValidation {
  static final RegExp _emailPattern = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)+$",
  );

  static String? requiredField(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    return null;
  }

  static String? email(String? value) {
    final requiredError = requiredField(value, 'Email');
    if (requiredError != null) return requiredError;
    final trimmed = value!.trim();
    final local = trimmed.split('@').first;
    if (!_emailPattern.hasMatch(trimmed) ||
        local.startsWith('.') ||
        local.endsWith('.') ||
        local.contains('..')) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  static String? password(String? value) {
    final requiredError = requiredField(value, 'Password');
    if (requiredError != null) return requiredError;
    if (value!.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    return null;
  }

  static String? newPassword(
    String? value, {
    String? email,
    String? currentPassword,
  }) {
    final error = password(value);
    if (error != null) return error;
    if (currentPassword != null && value == currentPassword) {
      return 'New password must be different from your current password.';
    }
    if (email?.trim().isNotEmpty == true &&
        value!.trim().toLowerCase() == email!.trim().toLowerCase()) {
      return 'Password cannot be the same as your email address.';
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
