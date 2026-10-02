import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_controller.dart';

/// Change-password form. Pops with `true` on success.
///
/// The backend checks the current password and the project's password rules
/// (length, not too common, not all numeric, not similar to your details), and
/// returns per-field messages, which are shown under the matching field. A
/// successful change returns fresh tokens for this device (stored by the auth
/// repository); every other device is signed out.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _showOld = false;
  bool _showNew = false;
  bool _busy = false;

  // Server-side messages, cleared as soon as the user edits the field.
  String? _oldError;
  String? _newError;
  String? _formError;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _oldError = null;
      _newError = null;
      _formError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .changePassword(
            oldPassword: _oldCtrl.text,
            newPassword: _newCtrl.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _oldError = e.fieldErrors['old_password'];
        _newError = e.fieldErrors['new_password'];
        // Anything that isn't tied to a field (throttling, 403, ...).
        if (_oldError == null && _newError == null) _formError = e.message;
      });
    } on NetworkUnavailable {
      if (!mounted) return;
      setState(
        () => _formError =
            'Cannot reach the server. Check your internet connection and '
            'try again.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _formError = 'Could not change the password.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration({
    required String label,
    required bool obscured,
    VoidCallback? onToggle,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline),
      errorText: errorText,
      errorMaxLines: 4,
      suffixIcon: onToggle == null
          ? null
          : IconButton(
              tooltip: obscured ? 'Show password' : 'Hide password',
              icon: Icon(
                obscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: onToggle,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Choose a password that is at least 8 characters, not '
                      'all numbers and not easy to guess. You will stay '
                      'signed in on this device; other devices will be '
                      'signed out.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_formError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: scheme.onErrorContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _formError!,
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _oldCtrl,
                      enabled: !_busy,
                      obscureText: !_showOld,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration(
                        label: 'Current password',
                        obscured: !_showOld,
                        onToggle: () => setState(() => _showOld = !_showOld),
                        errorText: _oldError,
                      ),
                      onChanged: (_) {
                        if (_oldError != null) setState(() => _oldError = null);
                      },
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your current password'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _newCtrl,
                      enabled: !_busy,
                      obscureText: !_showNew,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration(
                        label: 'New password',
                        obscured: !_showNew,
                        onToggle: () => setState(() => _showNew = !_showNew),
                        errorText: _newError,
                      ),
                      onChanged: (_) {
                        if (_newError != null) setState(() => _newError = null);
                      },
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Enter a new password';
                        }
                        if (v == _oldCtrl.text) {
                          return 'The new password must be different from '
                              'the current one';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmCtrl,
                      enabled: !_busy,
                      obscureText: !_showNew,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _busy ? null : _submit(),
                      decoration: _decoration(
                        label: 'Confirm new password',
                        obscured: !_showNew,
                      ),
                      validator: (v) =>
                          v != _newCtrl.text ? 'Passwords do not match' : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Change password'),
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
}
