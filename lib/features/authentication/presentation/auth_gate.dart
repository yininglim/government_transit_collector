import 'dart:async';

import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/admin_home/presentation/admin_home_page.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/authentication/presentation/login_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/reset_password_page.dart';
import 'package:government_transit_collector/features/passenger_home/presentation/passenger_home_page.dart';

enum AuthDestination { passenger, admin, unsupported }

AuthDestination destinationForRole(String role) {
  return switch (role.trim().toLowerCase()) {
    'passenger' => AuthDestination.passenger,
    'admin' => AuthDestination.admin,
    _ => AuthDestination.unsupported,
  };
}

class AuthGate extends StatefulWidget {
  AuthGate({super.key, AuthRepository? repository})
    : repository = repository ?? AuthRepository();

  final AuthRepository repository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<Object?>? _authSubscription;
  AppProfile? _profile;
  String? _error;
  bool _loading = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_repositoryChanged);
    _authSubscription = widget.repository.authStateChanges.listen(
      (_) {
        _refresh();
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Unable to verify your account. Please try again.';
        });
      },
    );
    _refresh();
  }

  void _repositoryChanged() {
    if (!mounted) return;
    // Recovery must replace any pushed signup/forgot-password/home subpage.
    if (widget.repository.handlingCallback ||
        widget.repository.recoveryRequired) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    _refresh();
  }

  Future<void> _refresh() async {
    final requestId = ++_requestId;
    if (widget.repository.handlingCallback ||
        widget.repository.recoveryRequired) {
      if (mounted) {
        setState(() {
          _profile = null;
          _loading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    if (widget.repository.currentSession == null) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _profile = null;
        _loading = false;
      });
      return;
    }

    try {
      final profile = await widget.repository.loadCurrentProfile();
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _profile = profile;
        _loading = false;
        if (profile == null) {
          _error = 'Your account is signed in, but its profile is missing.';
        } else if (destinationForRole(profile.role) ==
            AuthDestination.unsupported) {
          _error = 'Your account has an unsupported role.';
        }
      });
    } on AuthFlowException catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _profile = null;
        _error = error.message;
        _loading = false;
      });
    } on Object {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _profile = null;
        _error = 'Unable to verify your account. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_repositoryChanged);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository.handlingCallback) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (widget.repository.recoveryRequired) {
      return ResetPasswordPage(repository: widget.repository);
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (widget.repository.currentSession == null) {
      return LoginPage(
        repository: widget.repository,
        message: widget.repository.callbackMessage,
      );
    }

    if (_error != null || _profile == null) {
      return _ProfileErrorPage(
        message: _error ?? 'Unable to load your profile.',
        repository: widget.repository,
        onRetry: _refresh,
      );
    }

    return switch (destinationForRole(_profile!.role)) {
      AuthDestination.passenger => PassengerHomePage(
        profile: _profile!,
        repository: widget.repository,
      ),
      AuthDestination.admin => AdminHomePage(
        profile: _profile!,
        repository: widget.repository,
      ),
      AuthDestination.unsupported => _ProfileErrorPage(
        message: 'Your account has an unsupported role.',
        repository: widget.repository,
        onRetry: _refresh,
      ),
    };
  }
}

class _ProfileErrorPage extends StatefulWidget {
  const _ProfileErrorPage({
    required this.message,
    required this.repository,
    required this.onRetry,
  });

  final String message;
  final AuthRepository repository;
  final VoidCallback onRetry;

  @override
  State<_ProfileErrorPage> createState() => _ProfileErrorPageState();
}

class _ProfileErrorPageState extends State<_ProfileErrorPage> {
  bool _signingOut = false;

  Future<void> _logout() async {
    setState(() => _signingOut = true);
    try {
      await widget.repository.logout();
    } on AuthFlowException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text(widget.message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: widget.onRetry,
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: _signingOut ? null : _logout,
                  child: Text(_signingOut ? 'Signing out…' : 'Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
