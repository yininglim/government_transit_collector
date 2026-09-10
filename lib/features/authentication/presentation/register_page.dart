import 'package:government_transit_collector/core/widgets/readable_app_bar.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/authentication/presentation/auth_validation.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({required this.repository, super.key});

  final AuthRepository repository;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  static final _pendingInput = TextInputFormatter.withFunction(
    (oldValue, newValue) => oldValue,
  );
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _loading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) {
      _cancelRegistrationAutofill();
      return;
    }

    setState(() => _loading = true);
    try {
      _emailFocusNode.requestFocus();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final result = await widget.repository.register(
        fullName: _fullNameController.text,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      TextInput.finishAutofillContext(shouldSave: true);
      FocusManager.instance.primaryFocus?.unfocus();
      if (result.requiresEmailConfirmation) {
        setState(() {
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Verification email sent. Please check your inbox before signing in.',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pop();
      }
    } on AuthFlowException catch (error) {
      if (!mounted) return;
      _cancelRegistrationAutofill();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      setState(() => _loading = false);
    } on Object {
      if (!mounted) return;
      _cancelRegistrationAutofill();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to create the account. Please try again.'),
        ),
      );
      setState(() => _loading = false);
    }
  }

  void _cancelRegistrationAutofill() {
    TextInput.finishAutofillContext(shouldSave: false);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: readableAppBar(context, title: const Text('Create account')),
      body: SafeArea(
        child: GestureDetector(
          onTap: _loading
              ? null
              : () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: _loading ? const NeverScrollableScrollPhysics() : null,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  onDisposeAction: AutofillContextAction.cancel,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Passenger registration',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your passenger profile will be created automatically.',
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _fullNameController,
                          inputFormatters: [if (_loading) _pendingInput],
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              AuthValidation.requiredField(value, 'Full name'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          focusNode: _emailFocusNode,
                          inputFormatters: [if (_loading) _pendingInput],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: AuthValidation.email,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          errorBuilder: (context, error) => Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                          inputFormatters: [if (_loading) _pendingInput],
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: _loading
                                  ? null
                                  : () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => AuthValidation.newPassword(
                            value,
                            email: _emailController.text,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmPasswordController,
                          errorBuilder: (context, error) => Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                          inputFormatters: [if (_loading) _pendingInput],
                          obscureText: _obscureConfirmation,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _obscureConfirmation
                                  ? 'Show password confirmation'
                                  : 'Hide password confirmation',
                              onPressed: _loading
                                  ? null
                                  : () => setState(
                                      () => _obscureConfirmation =
                                          !_obscureConfirmation,
                                    ),
                              icon: Icon(
                                _obscureConfirmation
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => AuthValidation.confirmPassword(
                            value,
                            _passwordController.text,
                          ),
                          onFieldSubmitted: (_) => _register(),
                          onEditingComplete: () {},
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _loading ? null : _register,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: _loading
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Register'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Already have an account? Sign in'),
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
}

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({
    required this.repository,
    required this.email,
    this.unverifiedSignIn = false,
    super.key,
  });
  final AuthRepository repository;
  final String email;
  final bool unverifiedSignIn;
  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  Timer? _timer;
  int _remaining = 0;
  bool _busy = false;
  String? _message;
  void _cooldown() {
    _timer?.cancel();
    _remaining = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining = (60 - timer.tick).clamp(0, 60));
      if (_remaining == 0) timer.cancel();
    });
  }

  @override
  void initState() {
    super.initState();
    if (!widget.unverifiedSignIn) _cooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    if (_busy || _remaining > 0) return;
    setState(() {
      _busy = true;
      _message = null;
      _cooldown();
    });
    try {
      await widget.repository.resendVerificationEmail(widget.email);
      if (mounted)
        setState(
          () => _message = 'Verification email sent. Please check your inbox.',
        );
    } on Object catch (error) {
      if (mounted)
        setState(
          () => _message = error is AuthFlowException
              ? error.message
              : 'Unable to resend verification email. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: readableAppBar(context, 
        title: Text(
          widget.unverifiedSignIn ? 'Email Not Verified' : 'Verify Your Email',
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final topPadding = (constraints.maxHeight * 0.06).clamp(16.0, 40.0).toDouble();
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, topPadding, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  key: const Key('email-verification-content'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.mark_email_unread_outlined,
                      key: const Key('email-verification-icon'),
                      size: 48, color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.unverifiedSignIn
                          ? 'Your email address has not been verified.'
                          : 'We sent a verification link to:',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.email.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        key: const Key('verification-email-card'),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.email_outlined, size: 20,
                              color: theme.colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(child: Text(widget.email,
                              style: theme.textTheme.bodyLarge,
                            )),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      widget.unverifiedSignIn
                          ? 'Please verify your email before signing in.'
                          : 'Please check your email and verify your account before signing in.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy || _remaining > 0 ? null : _resend,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      child: const Text('Resend Verification Email',
                        textAlign: TextAlign.center),
                    ),
                    if (_remaining > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Resend available in $_remaining seconds.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_message!, textAlign: TextAlign.center),
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Back to Sign In'),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      key: const Key('verification-spam-info'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 18,
                            color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(child: Text(
                            'Check your Spam/Junk folder if you cannot find the email.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
