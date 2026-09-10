import 'dart:async';

import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/authentication/presentation/auth_validation.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    required this.repository,
    this.accountEmail,
    this.googleSession = false,
    super.key,
  });
  final AuthRepository repository;
  final String? accountEmail;
  final bool googleSession;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.accountEmail);
  bool _loading = false;
  String? _message;
  Timer? _cooldownTimer;
  int _secondsRemaining = 0;
  String? _requestedEmail;

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _secondsRemaining = 60;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsRemaining = (60 - timer.tick).clamp(0, 60));
      if (_secondsRemaining == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_loading || _secondsRemaining > 0 || !_form.currentState!.validate()) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _message = null;
      _requestedEmail ??= _email.text.trim();
      _startCooldown();
    });
    try {
      await widget.repository.sendPasswordReset(_requestedEmail!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If an account exists for this email, a password reset link has been sent.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _message = error is AuthFlowException
            ? error.message
            : 'Unable to send a reset link. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.accountEmail == null
            ? 'Forgot Password'
            : 'Change Email Password',
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.accountEmail == null)
                    const Text('Enter the email associated with your account.')
                  else ...[
                    Text(
                      widget.googleSession
                          ? 'You signed in with Google.'
                          : 'Use a secure reset link for this sign-in session.',
                    ),
                    const Text(
                      'This password is only used when signing in with Email & Password. Changing it does not change your Google password.',
                    ),
                    Text(
                      'Send a secure password reset link to: ${widget.accountEmail}',
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    enabled: !_loading && _requestedEmail == null,
                    readOnly: widget.accountEmail != null,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: AuthValidation.email,
                    onFieldSubmitted: (_) => _send(),
                  ),
                  const SizedBox(height: 24),
                  if (_requestedEmail == null)
                    FilledButton(
                      onPressed: _loading ? null : _send,
                      child: Text(_loading ? 'Sending…' : 'Send Reset Link'),
                    ),
                  if (_requestedEmail != null) ...[
                    const Text("Didn't receive the email?"),
                    TextButton(
                      onPressed: _loading || _secondsRemaining > 0
                          ? null
                          : _send,
                      child: const Text('Resend Reset Email'),
                    ),
                    if (_secondsRemaining > 0)
                      Text('Resend available in ${_secondsRemaining}s'),
                  ],
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(_message!, textAlign: TextAlign.center),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      widget.accountEmail == null
                          ? 'Back to Sign In'
                          : 'Back to Account Security',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
