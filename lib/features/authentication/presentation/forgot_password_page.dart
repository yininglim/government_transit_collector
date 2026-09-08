import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/authentication/presentation/auth_validation.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({required this.repository, super.key});
  final AuthRepository repository;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_loading || !_form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await widget.repository.sendPasswordReset(_email.text);
      if (!mounted) return;
      setState(
        () => _message =
            'If an account exists for this email, a password reset link has been sent.',
      );
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
    appBar: AppBar(title: const Text('Forgot Password')),
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
                  const Text('Enter the email associated with your account.'),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    enabled: !_loading,
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
                  FilledButton(
                    onPressed: _loading ? null : _send,
                    child: Text(_loading ? 'Sending…' : 'Send Reset Link'),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(_message!, textAlign: TextAlign.center),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to Sign In'),
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
