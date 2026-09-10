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
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          child: const Icon(Icons.lock_reset),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.accountEmail == null
                            ? 'Reset Your Password'
                            : 'Change Email Password',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (widget.accountEmail == null)
                        Text(
                          'Enter your email to receive a secure password reset link.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        )
                      else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.googleSession) ...[
                                      const Text(
                                        'You signed in with Google.',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                    const Text(
                                      'This changes only your Email & Password sign-in for Government Transit Collector.',
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Your Google password will not be changed.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Send a password reset email to:',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (widget.accountEmail == null)
                        TextFormField(
                          controller: _email,
                          enabled: !_loading && _requestedEmail == null,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: AuthValidation.email,
                          onFieldSubmitted: (_) => _send(),
                        )
                      else
                        FormField<String>(
                          initialValue: _email.text,
                          validator: AuthValidation.email,
                          builder: (field) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLow,
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.email_outlined,
                                      size: 20,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _email.text,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (field.hasError)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    field.errorText!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      if (_requestedEmail == null)
                        FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _loading ? null : _send,
                          child: Text(
                            _loading
                                ? 'Sending...'
                                : 'Send Password Reset Email',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (_requestedEmail != null) ...[
                        const Text(
                          "Didn't receive the email?",
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                          onPressed: _loading || _secondsRemaining > 0
                              ? null
                              : _send,
                          child: const Text('Resend Reset Email'),
                        ),
                        if (_secondsRemaining > 0)
                          Text(
                            'Resend available in ${_secondsRemaining}s',
                            textAlign: TextAlign.center,
                          ),
                      ],
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(_message!, textAlign: TextAlign.center),
                        ),
                      const SizedBox(height: 4),
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
      ),
    ),
  );
}
