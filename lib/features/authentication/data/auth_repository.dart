import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    final redirect = redirectUrl;
    try {
      _expectRecovery = true;
      await _preferences?.setBool(_pendingKey, true);
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: redirect,
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
    if (password.length < 8) {
      throw const AuthFlowException(
        'Password must contain at least 8 characters.',
      );
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
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

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}
