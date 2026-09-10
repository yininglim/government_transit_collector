import 'package:government_transit_collector/core/widgets/readable_app_bar.dart';
import 'package:flutter/material.dart';
import '../data/auth_repository.dart';
import 'auth_validation.dart';
import 'forgot_password_page.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({required this.repository, super.key});
  final AuthRepository repository;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  final _visiblePasswords = <TextEditingController>{};
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (_loading || !_form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.repository.changePassword(
        currentPassword: _current.text,
        newPassword: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop('Password updated successfully.');
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is AuthFlowException
            ? error.message
            : 'Unable to update your password. Please try again.',
      );
    } finally {
      if (mounted) {
        _current.clear();
        _password.clear();
        _confirm.clear();
        setState(() => _loading = false);
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String? Function(String?) validator, {
    bool last = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_loading,
      obscureText: !_visiblePasswords.contains(controller),
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _visiblePasswords.contains(controller)
              ? 'Hide password'
              : 'Show password',
          onPressed: _loading
              ? null
              : () => setState(() {
                  if (!_visiblePasswords.remove(controller))
                    _visiblePasswords.add(controller);
                }),
          icon: Icon(
            _visiblePasswords.contains(controller)
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
      validator: validator,
      onFieldSubmitted: last ? (_) => _change() : null,
    ),
  );

  @override
  Widget build(BuildContext context) =>
      widget.repository.supportsEmailPassword &&
          !widget.repository.passwordAuthenticatedSession
      ? ForgotPasswordPage(
          repository: widget.repository,
          accountEmail: widget.repository.currentEmail,
          googleSession:
              widget.repository.currentAuthenticationMethod == 'oauth' &&
              widget.repository.hasGoogleIdentity,
        )
      : Scaffold(
          appBar: readableAppBar(context, title: const Text('Change Email Password')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: !widget.repository.supportsEmailPassword
                      ? const Text(
                          'Your Google password is managed through your Google Account.',
                        )
                      : Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Change the password for this app’s email sign-in.',
                              ),
                              if (widget.repository.hasGoogleIdentity)
                                const Text(
                                  'This does not change your Google Account password.',
                                ),
                              const SizedBox(height: 24),
                              _field(
                                _current,
                                'Current Password',
                                (value) => AuthValidation.requiredField(
                                  value,
                                  'Current password',
                                ),
                              ),
                              _field(
                                _password,
                                'New Password',
                                (value) => AuthValidation.newPassword(
                                  value,
                                  email: widget.repository.currentEmail,
                                  currentPassword: _current.text,
                                ),
                              ),
                              _field(
                                _confirm,
                                'Confirm New Password',
                                (value) => AuthValidation.confirmPassword(
                                  value,
                                  _password.text,
                                ),
                                last: true,
                              ),
                              FilledButton(
                                onPressed: _loading ? null : _change,
                                child: Text(
                                  _loading
                                      ? 'Updating…'
                                      : 'Change Email Password',
                                ),
                              ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(_error!),
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
