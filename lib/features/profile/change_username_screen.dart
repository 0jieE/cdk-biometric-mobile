import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_controller.dart';

/// Same rule as the backend (`apps/api/usernames.py`): 3-30 characters,
/// lowercase letters / digits / `.` `_` `-`, starting with a letter or digit.
final _usernameRe = RegExp(r'^[a-z0-9][a-z0-9._-]{2,29}$');
const _formatMessage =
    'Use 3-30 characters: lowercase letters, digits, dots, hyphens and '
    'underscores, starting with a letter or digit.';

/// Change-username form. Pops with the stored username on success.
///
/// The current password is required (a username is a login credential). The
/// server normalises the name to lowercase and refuses taken / reserved /
/// employee-number-style names with one generic message. Nobody is signed out.
class ChangeUsernameScreen extends ConsumerStatefulWidget {
  const ChangeUsernameScreen({super.key});

  @override
  ConsumerState<ChangeUsernameScreen> createState() =>
      _ChangeUsernameScreenState();
}

class _ChangeUsernameScreenState extends ConsumerState<ChangeUsernameScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameCtrl;
  final _passwordCtrl = TextEditingController();

  bool _showPassword = false;
  bool _busy = false;

  // Server-side messages, cleared as soon as the user edits the field.
  String? _usernameError;
  String? _passwordError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(
      text: ref.read(authControllerProvider).employee?.username ?? '',
    );
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _usernameError = null;
      _passwordError = null;
      _formError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final username = _usernameCtrl.text.trim().toLowerCase();
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .changeUsername(
            username: username,
            currentPassword: _passwordCtrl.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(username);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _usernameError = e.fieldErrors['username'];
        _passwordError = e.fieldErrors['current_password'];
        // Anything that isn't tied to a field (throttling, 403, ...).
        if (_usernameError == null && _passwordError == null) {
          _formError = e.message;
        }
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
      setState(() => _formError = 'Could not change the username.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Change username')),
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
                      'Your username is what you type to log in. You stay '
                      'signed in on every device; use the new name next time '
                      'you log in.',
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
                      controller: _usernameCtrl,
                      enabled: !_busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.visiblePassword,
                      decoration: InputDecoration(
                        labelText: 'New username',
                        helperText: 'Letters, digits, . _ - (3-30 characters)',
                        prefixIcon: const Icon(Icons.alternate_email),
                        errorText: _usernameError,
                        errorMaxLines: 4,
                      ),
                      onChanged: (_) {
                        if (_usernameError != null) {
                          setState(() => _usernameError = null);
                        }
                      },
                      validator: (v) {
                        final value = (v ?? '').trim().toLowerCase();
                        if (value.isEmpty) return 'Enter a username';
                        if (!_usernameRe.hasMatch(value)) return _formatMessage;
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtrl,
                      enabled: !_busy,
                      obscureText: !_showPassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _busy ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Current password',
                        helperText: 'Needed to confirm it is you',
                        prefixIcon: const Icon(Icons.lock_outline),
                        errorText: _passwordError,
                        errorMaxLines: 3,
                        suffixIcon: IconButton(
                          tooltip: _showPassword
                              ? 'Hide password'
                              : 'Show password',
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      onChanged: (_) {
                        if (_passwordError != null) {
                          setState(() => _passwordError = null);
                        }
                      },
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your current password'
                          : null,
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
                          : const Text('Change username'),
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
