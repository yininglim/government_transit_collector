import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/authentication/presentation/auth_validation.dart';
import 'package:government_transit_collector/features/authentication/presentation/register_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({required this.repository, this.message, super.key});

  final AuthRepository repository;
  final String? message;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  bool _googleLoading = false;
  bool _googleAwaiting = false;

  Future<void> _googleLogin() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _googleLoading = true);
    try {
      await widget.repository.signInWithGoogle();
      if (mounted) setState(() => _googleAwaiting = true);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is AuthFlowException
                ? error.message
                : 'Unable to sign in with Google. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _cancelGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await widget.repository.cancelGoogleSignIn();
      if (!mounted) return;
      setState(() => _googleAwaiting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google sign-in was cancelled.')),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to cancel sign-in. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_loading ||
        _googleLoading ||
        _googleAwaiting ||
        !_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.repository.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on EmailNotVerifiedException {
      if (!mounted) return;
      setState(() => _loading = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => EmailVerificationPage(
            repository: widget.repository,
            email: _emailController.text.trim(),
            unverifiedSignIn: true,
          ),
        ),
      );
    } on AuthFlowException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      setState(() => _loading = false);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to sign in. Please try again.')),
      );
      setState(() => _loading = false);
    }
  }

  Future<void> _openRegistration() async {
    if (_loading || _googleLoading || _googleAwaiting) return;
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => RegisterPage(repository: widget.repository),
      ),
    );
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.directions_bus_filled,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Government Transit Collector',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Welcome Back',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 32),
                        if (widget.message != null) ...[
                          Text(widget.message!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _emailController,
                          enabled: !_loading,
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
                          enabled: !_loading,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
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
                          validator: AuthValidation.password,
                          onFieldSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed:
                              _loading || _googleLoading || _googleAwaiting
                              ? null
                              : _login,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: _loading
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Sign In'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text('OR'),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed:
                              _loading || _googleLoading || _googleAwaiting
                              ? null
                              : _googleLogin,
                          icon: const Text(
                            'G',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          label: Text(
                            _googleLoading
                                ? 'Opening Google…'
                                : 'Continue with Google',
                          ),
                        ),
                        if (_googleAwaiting)
                          TextButton(
                            onPressed: _googleLoading ? null : _cancelGoogle,
                            child: const Text('Cancel Google sign-in'),
                          ),
                        TextButton(
                          onPressed:
                              _loading || _googleLoading || _googleAwaiting
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ForgotPasswordPage(
                                      repository: widget.repository,
                                    ),
                                  ),
                                ),
                          child: const Text('Forgot Password?'),
                        ),
                        TextButton(
                          onPressed:
                              _loading || _googleLoading || _googleAwaiting
                              ? null
                              : _openRegistration,
                          child: const Text("Don't have an account? Sign Up"),
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
