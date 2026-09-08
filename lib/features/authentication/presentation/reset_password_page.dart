import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/authentication/presentation/auth_validation.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({required this.repository, super.key});
  final AuthRepository repository;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit({bool cancel = false}) async {
    if (_loading || (!cancel && !_form.currentState!.validate())) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _loading = true);
    // The gate can replace this page as soon as the session is cleared.
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (cancel) {
        await widget.repository.cancelRecovery();
      } else {
        await widget.repository.resetPassword(_password.text);
        messenger.showSnackBar(
          const SnackBar(content: Text('Password updated successfully.')),
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _message = error is AuthFlowException
            ? error.message
            : 'Unable to update your password. Please try again.',
      );
    } finally {
      if (mounted) {
        _password.clear();
        _confirmation.clear();
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Reset Password'),
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
                    if (!widget.repository.hasValidRecoverySession)
                      const Text(AuthRepository.invalidRecoveryMessage)
                    else ...[
                      TextFormField(
                        controller: _password,
                        enabled: !_loading,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'New Password',
                          border: OutlineInputBorder(),
                        ),
                        validator: AuthValidation.password,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmation,
                        enabled: !_loading,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Confirm New Password',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => AuthValidation.confirmPassword(
                          value,
                          _password.text,
                        ),
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: Text(_loading ? 'Updating…' : 'Reset Password'),
                      ),
                    ],
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(_message!),
                      ),
                    TextButton(
                      onPressed: _loading ? null : () => _submit(cancel: true),
                      child: const Text('Back to Sign In'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
