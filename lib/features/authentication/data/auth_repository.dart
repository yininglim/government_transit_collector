import 'package:supabase_flutter/supabase_flutter.dart';

class AppProfile {
  const AppProfile({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.email,
  });

  final String userId;
  final String fullName;
  final String role;
  final String? email;

  String get displayName {
    final trimmedName = fullName.trim();
    if (trimmedName.isNotEmpty) return trimmedName;
    return email?.trim().isNotEmpty == true ? email!.trim() : 'User';
  }
}

class RegistrationResult {
  const RegistrationResult({required this.requiresEmailConfirmation});

  final bool requiresEmailConfirmation;
}

class AuthRepository {
  AuthRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<RegistrationResult> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: <String, dynamic>{'full_name': fullName.trim()},
      );
      if (response.user == null) {
        throw const AuthFlowException(
          'Registration did not complete. Please try again.',
        );
      }
      return RegistrationResult(
        requiresEmailConfirmation: response.session == null,
      );
    } on AuthException catch (error) {
      throw AuthFlowException(_friendlyAuthMessage(error));
    }
  }

  Future<void> login({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (error) {
      throw AuthFlowException(_friendlyAuthMessage(error));
    }
  }

  Future<void> logout() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (error) {
      throw AuthFlowException(_friendlyAuthMessage(error));
    }
  }

  Future<AppProfile?> loadCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final data = await _client
          .from('profiles')
          .select('user_id, full_name, role')
          .eq('user_id', user.id)
          .maybeSingle();
      if (data == null) return null;

      return AppProfile(
        userId: data['user_id'] as String,
        fullName: data['full_name'] as String? ?? '',
        role: data['role'] as String? ?? '',
        email: user.email,
      );
    } on PostgrestException catch (error) {
      throw AuthFlowException(
        error.message.isEmpty
            ? 'Unable to load your profile.'
            : 'Unable to load your profile: ${error.message}',
      );
    }
  }

  Future<AppProfile> updateFullName(String fullName) async {
    final user = _client.auth.currentUser;
    final name = fullName.trim();
    if (user == null) throw const AuthFlowException('Please sign in again.');
    if (name.isEmpty || name.length > 100) {
      throw const AuthFlowException(
        'Enter a name between 1 and 100 characters.',
      );
    }
    try {
      final row = await _client
          .from('profiles')
          .update({'full_name': name})
          .eq('user_id', user.id)
          .select('user_id, full_name, role')
          .single();
      return AppProfile(
        userId: row['user_id'] as String,
        fullName: row['full_name'] as String,
        role: row['role'] as String,
        email: user.email,
      );
    } on Object {
      throw const AuthFlowException(
        'Unable to update your name. Please try again.',
      );
    }
  }

  static String _friendlyAuthMessage(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'The email or password is incorrect.';
    }
    if (message.contains('email not confirmed')) {
      return 'Please confirm your email before signing in.';
    }
    if (message.contains('user already registered')) {
      return 'An account already exists for this email.';
    }
    if (message.contains('password')) {
      return 'The password was not accepted. Please use at least 8 characters.';
    }
    if (message.contains('email')) {
      return 'Please check the email address and try again.';
    }
    return error.message.isEmpty
        ? 'Authentication failed. Please try again.'
        : error.message;
  }
}

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}
