import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../presentation/auth_validation.dart';

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

class AuthRepository extends ChangeNotifier {
  AuthRepository({SupabaseClient? client, String? redirectUrl})
    : _client = client ?? Supabase.instance.client,
      _redirectUrl = redirectUrl?.trim();

  final SupabaseClient _client;
  final String? _redirectUrl;
  StreamSubscription<Uri>? _linkSubscription;
  SharedPreferences? _preferences;
  bool _handlingCallback = false;
  bool _recovery = false;
  bool _validRecovery = false;
  bool _expectRecovery = false;
  Uri? _lastCallback;
  String? callbackMessage;
  static const invalidRecoveryMessage =
      'This password reset link is invalid or has expired. Please request a new link.';
  static const _recoveryKey = 'auth_recovery_in_progress';
  static const _pendingKey = 'auth_pending_recovery';

  bool get handlingCallback => _handlingCallback;
  bool get recoveryRequired => _recovery;
  bool get hasValidRecoverySession =>
      _recovery &&
      _validRecovery &&
      currentSession != null &&
      !currentSession!.isExpired;

  String get redirectUrl {
    final value =
        _redirectUrl ??
        (dotenv.isInitialized ? dotenv.maybeGet('AUTH_REDIRECT_URL') : null);
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.scheme == 'http') {
      throw const AuthFlowException(
        'Authentication links are not configured. Please contact support.',
      );
    }
    return uri.toString();
  }

  Future<void> initializeDeepLinks() async {
    _preferences = await SharedPreferences.getInstance();
    // An interrupted recovery stays isolated after a process restart. A fresh
    // verified link is required; a persisted normal session cannot bypass it.
    _recovery = _preferences!.getBool(_recoveryKey) ?? false;
    _expectRecovery = _preferences!.getBool(_pendingKey) ?? false;
    final links = AppLinks();
    final initial = await links.getInitialLink();
    if (initial != null) await handleAuthCallback(initial);
    _linkSubscription = links.uriLinkStream.listen(
      (uri) => unawaited(handleAuthCallback(uri)),
      onError: (Object _) {
        callbackMessage =
            'Unable to open the authentication link. Please try again.';
        notifyListeners();
      },
    );
  }

  bool acceptsCallback(Uri uri) {
    try {
      final expected = Uri.parse(redirectUrl);
      return uri.scheme == expected.scheme &&
          uri.host == expected.host &&
          uri.port == expected.port &&
          uri.path == expected.path &&
          uri.userInfo.isEmpty;
    } on AuthFlowException {
      return false;
    }
  }

  Future<void> handleAuthCallback(Uri uri) async {
    if (!acceptsCallback(uri) || _handlingCallback || uri == _lastCallback) {
      return;
    }
    _lastCallback = uri;
    _handlingCallback = true;
    _validRecovery = false;
    callbackMessage = null;
    notifyListeners();
    try {
      // Persist the routing barrier BEFORE Supabase can persist a session.
      await _preferences?.setBool(_recoveryKey, true);
      // This app initiates PKCE flows. Never accept an implicit token callback
      // whose caller-controlled type could turn recovery into a normal login.
      if (uri.queryParameters['code']?.isNotEmpty != true || uri.hasFragment) {
        throw const AuthFlowException('Invalid authentication callback.');
      }
      final response = await _client.auth.getSessionFromUrl(uri);
      _recovery =
          response.redirectType == 'recovery' ||
          response.redirectType == AuthChangeEvent.passwordRecovery.name;
      _validRecovery = _recovery;
      await _preferences?.setBool(_recoveryKey, _recovery);
      _expectRecovery = false;
      await _preferences?.setBool(_pendingKey, false);
    } on Object {
      _recovery = _expectRecovery || _recovery;
      var cancelled = false;
      try {
        cancelled =
            uri.queryParameters['error'] == 'access_denied' ||
            (uri.hasFragment &&
                Uri.splitQueryString(uri.fragment)['error'] == 'access_denied');
      } on FormatException {
        // Malformed callback details must never be shown to the user.
      }
      callbackMessage = _recovery
          ? invalidRecoveryMessage
          : cancelled
          ? 'Google sign-in was cancelled.'
          : 'Unable to sign in with Google. Please try again.';
      // Never leave an old or partially exchanged session available after a
      // failed callback. Keep the barrier if local cleanup itself fails.
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } on Object {
        _recovery = true;
      }
      await _preferences?.setBool(_recoveryKey, _recovery);
    } finally {
      _handlingCallback = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    final redirect = redirectUrl;
    try {
      _expectRecovery = false;
      await _preferences?.setBool(_pendingKey, false);
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const AuthFlowException('Google sign-in was cancelled.');
      }
    } on AuthFlowException {
      rethrow;
    } on Object {
      throw const AuthFlowException(
        'Unable to sign in with Google. Please try again.',
      );
    }
  }

  Future<void> sendPasswordReset(String email) async {
    final validation = AuthValidation.email(email);
    if (validation != null) throw AuthFlowException(validation);
    final redirect = redirectUrl;
    try {
      _expectRecovery = true;
      await _preferences?.setBool(_pendingKey, true);
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: redirect,
      );
    } on AuthException catch (error) {
      // Recovery must not reveal account existence.
      if (error.code == 'user_not_found') return;
      if (_isRateLimit(error)) {
        throw const AuthFlowException(
          'Too many requests. Please wait a few minutes before trying again.',
        );
      }
      throw const AuthFlowException(
        'Unable to send a reset link. Please try again.',
      );
    } on Object {
      throw const AuthFlowException(
        'Unable to send a reset link. Please try again.',
      );
    }
  }

  Future<void> cancelGoogleSignIn() async {
    // Browser dismissal has no reliable OAuth completion event. Let the user
    // explicitly cancel, and invalidate the SDK's pending PKCE verifier.
    await cancelRecovery();
  }

  Future<void> resetPassword(String password) async {
    if (!hasValidRecoverySession) {
      throw const AuthFlowException(invalidRecoveryMessage);
    }
    final validation = AuthValidation.newPassword(
      password,
      email: currentEmail,
    );
    if (validation != null) throw AuthFlowException(validation);
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      if (error.code == 'same_password') {
        throw const AuthFlowException(
          'Your new password cannot be the same as your previous password.',
        );
      }
      if (error.statusCode == '401' || error.statusCode == '403') {
        _validRecovery = false;
        throw const AuthFlowException(invalidRecoveryMessage);
      }
      throw const AuthFlowException(
        'Unable to update your password. Please try again.',
      );
    } on Object {
      throw const AuthFlowException(
        'Unable to update your password. Please try again.',
      );
    }
    await cancelRecovery();
  }

  Future<void> cancelRecovery() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } on Object {
      if (currentSession != null) {
        throw const AuthFlowException('Unable to sign out. Please try again.');
      }
    }
    await _preferences?.setBool(_recoveryKey, false);
    await _preferences?.setBool(_pendingKey, false);
    _recovery = false;
    _validRecovery = false;
    _expectRecovery = false;
    callbackMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  String? get currentEmail => _client.auth.currentUser?.email;
  bool get supportsEmailPassword =>
      _client.auth.currentUser?.identities?.any(
        (identity) => identity.provider == 'email',
      ) ==
      true;
  bool get hasGoogleIdentity =>
      _client.auth.currentUser?.identities?.any(
        (identity) => identity.provider == 'google',
      ) ==
      true;

  bool _changingPassword = false;

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_changingPassword) return;
    final user = _client.auth.currentUser;
    if (user == null || recoveryRequired || handlingCallback) {
      throw const AuthFlowException('Please sign in again.');
    }
    if (!supportsEmailPassword || user.email?.isNotEmpty != true) {
      throw const AuthFlowException(
        'This account does not support app password changes.',
      );
    }
    final validation =
        AuthValidation.requiredField(currentPassword, 'Current password') ??
        AuthValidation.newPassword(
          newPassword,
          email: user.email,
          currentPassword: currentPassword,
        );
    if (validation != null) throw AuthFlowException(validation);
    _changingPassword = true;
    try {
      try {
        // Reauthenticate only the current Supabase user's email using the
        // existing SDK. Profile identity, role and linked providers are untouched.
        final verified = await _client.auth.signInWithPassword(
          email: user.email!,
          password: currentPassword,
        );
        if (verified.user?.id != user.id ||
            _client.auth.currentUser?.id != user.id) {
          await _client.auth.signOut(scope: SignOutScope.local);
          throw const AuthFlowException(
            'Your account changed. Please sign in again.',
          );
        }
      } on AuthException catch (error) {
        if (error.code == 'invalid_credentials' ||
            error.message.toLowerCase().contains('invalid login credentials')) {
          throw const AuthFlowException('Current password is incorrect.');
        }
        throw AuthFlowException(
          _isRateLimit(error)
              ? 'Too many requests. Please wait a few minutes before trying again.'
              : 'Unable to verify your current password. Please try again.',
        );
      } on AuthFlowException {
        rethrow;
      } on Object {
        throw const AuthFlowException(
          'Unable to verify your current password. Please try again.',
        );
      }
      if (recoveryRequired ||
          handlingCallback ||
          _client.auth.currentUser?.id != user.id) {
        throw const AuthFlowException(
          'Your account changed. Please sign in again.',
        );
      }
      try {
        await _client.auth.updateUser(
          _PasswordChangeAttributes(
            password: newPassword,
            currentPassword: currentPassword,
          ),
        );
      } on AuthException catch (error) {
        if (error.code == 'same_password') {
          throw const AuthFlowException(
            'Your new password cannot be the same as your previous password.',
          );
        }
        throw const AuthFlowException(
          'Unable to update your password. Please try again.',
        );
      } on Object {
        throw const AuthFlowException(
          'Unable to update your password. Please try again.',
        );
      }
    } finally {
      _changingPassword = false;
    }
  }

  static bool _isRateLimit(AuthException error) =>
      error.statusCode == '429' ||
      error.code == 'over_email_send_rate_limit' ||
      error.code == 'over_request_rate_limit';

  static const existingAccountMessage =
      'An account with this email already exists. Please sign in instead.';

  Future<RegistrationResult> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final validation =
        AuthValidation.email(email) ??
        AuthValidation.newPassword(password, email: email);
    if (validation != null) throw AuthFlowException(validation);
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
      // Supabase may obfuscate an existing confirmed user instead of returning
      // an error. No profile queries or writes are needed to handle this.
      if (response.session == null &&
          response.user!.identities?.isEmpty == true) {
        throw const AuthFlowException(existingAccountMessage);
      }
      return RegistrationResult(
        requiresEmailConfirmation: response.session == null,
      );
    } on AuthException catch (error) {
      if (error.code == 'user_already_exists' ||
          error.code == 'email_exists' ||
          error.message.toLowerCase().contains('user already registered')) {
        throw const AuthFlowException(existingAccountMessage);
      }
      throw AuthFlowException(
        _isRateLimit(error)
            ? 'Too many requests. Please wait a few minutes before trying again.'
            : 'Unable to create the account. Please try again.',
      );
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
      var data = await _client
          .from('profiles')
          .select('user_id, full_name, role')
          .eq('user_id', user.id)
          .maybeSingle();
      if (data == null &&
          user.identities?.any((i) => i.provider == 'google') == true) {
        // The RPC derives identity and metadata from auth.uid()/auth.users,
        // inserts only if absent, and never updates an existing role.
        await _client.rpc('ensure_current_google_profile');
        data = await _client
            .from('profiles')
            .select('user_id, full_name, role')
            .eq('user_id', user.id)
            .maybeSingle();
      }
      if (_client.auth.currentUser?.id != user.id) return null;
      if (data == null) return null;

      return AppProfile(
        userId: data['user_id'] as String,
        fullName: data['full_name'] as String? ?? '',
        role: data['role'] as String? ?? '',
        email: user.email,
      );
    } on PostgrestException {
      throw const AuthFlowException(
        'Unable to load your profile. Please try again.',
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

// Supabase Auth supports current_password for projects that require it on
// updates. The installed Dart SDK's UserAttributes does not expose that field
// yet; serialize it only into the supported authenticated Auth request.
class _PasswordChangeAttributes extends UserAttributes {
  _PasswordChangeAttributes({
    required super.password,
    required this.currentPassword,
  });
  final String currentPassword;
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'current_password': currentPassword,
  };
}

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}
