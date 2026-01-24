import 'package:PeerReal/services/logger_service.dart';
import 'package:flutter/material.dart';
import 'package:PeerReal/services/ditto_service.dart';

enum _Step { username, login, signup, setPassword }

class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;
  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _nameC = TextEditingController();
  final _pwC = TextEditingController();
  final _pw2C = TextEditingController();

  bool _busy = false;
  bool _showPw = false;
  String? _error;

  _Step _step = _Step.username;

  UserLookup? _hit;

  @override
  void dispose() {
    _nameC.dispose();
    _pwC.dispose();
    _pw2C.dispose();
    super.dispose();
  }

  Future<void> _ensureDittoReady() async {
    await DittoService.instance.init();
  }

  Future<void> _checkUsername() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _ensureDittoReady();

      final name = _nameC.text.trim();
      if (name.isEmpty) throw StateError('Bitte Username eingeben.');

      final hit = await DittoService.instance.lookupUserByDisplayName(name);

      setState(() {
        _hit = hit;
        if (hit == null) {
          _step = _Step.signup;
        } else if (!hit.hasPassword) {
          _step = _Step.setPassword;
        } else {
          _step = _Step.login;
        }
      });
    } catch (e) {
      setState(() {
        _error = e is StateError ? e.message : 'Fehler beim Prüfen.';
      });
      logger.e(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    await _ensureDittoReady();

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final name = _nameC.text.trim();
      final pw = _pwC.text;
      final pw2 = _pw2C.text;

      if (_step == _Step.login) {
        await DittoService.instance.loginUser(displayName: name, password: pw);
      } else if (_step == _Step.signup) {
        if (pw.length < 6) throw StateError('Passwort min. 6 Zeichen.');
        if (pw != pw2) throw StateError('Passwörter stimmen nicht überein.');
        await DittoService.instance.signupNewUser(
          displayName: name,
          password: pw,
        );
      } else if (_step == _Step.setPassword) {
        if (_hit == null) throw StateError('User nicht gefunden.');
        if (pw.length < 6) throw StateError('Passwort min. 6 Zeichen.');
        if (pw != pw2) throw StateError('Passwörter stimmen nicht überein.');
        await DittoService.instance.setPasswordForExistingUser(
          docId: _hit!.docId,
          userId: _hit!.userId,
          displayName: _hit!.displayName,
          password: pw,
        );
      } else {
        return;
      }

      widget.onAuthenticated();
    } catch (e) {
      final msg = e.toString();
      setState(() {
        if (msg.contains('NAME_TAKEN')) {
          _error = 'Username ist bereits vergeben.';
        } else if (msg.contains('NO_USER'))
          _error = 'User nicht gefunden.';
        else if (msg.contains('NO_PASSWORD_SET'))
          _error = 'Kein Passwort gesetzt – bitte einmal setzen.';
        else if (msg.contains('WRONG_PASSWORD'))
          _error = 'Falsches Passwort.';
        else if (e is StateError)
          _error = e.message;
        else
          _error = 'Authentifizierung fehlgeschlagen.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetToUsername() {
    setState(() {
      _step = _Step.username;
      _hit = null;
      _pwC.clear();
      _pw2C.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    final fg = Theme.of(context).colorScheme.onSurface;

    final title = switch (_step) {
      _Step.username => 'PeerReal.',
      _Step.login => 'Welcome back',
      _Step.signup => 'Create your profile',
      _Step.setPassword => 'Secure your profile',
    };

    final subtitle = switch (_step) {
      _Step.username => 'Enter your username to continue.',
      _Step.login => 'Enter your password.',
      _Step.signup => 'Set a password for your new account.',
      _Step.setPassword => 'Existing user found. Set password once.',
    };

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: _step == _Step.username ? 44 : 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.1,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 16,
                      color: fg.withOpacity(0.75),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 22),

                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: fg.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: fg.withOpacity(0.12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Field(
                          controller: _nameC,
                          label: 'Username',
                          enabled: !_busy && _step == _Step.username,
                          textInputAction: TextInputAction.next,
                        ),

                        if (_step != _Step.username) ...[
                          const SizedBox(height: 12),
                          _PasswordField(
                            controller: _pwC,
                            label: _step == _Step.login
                                ? 'Passwort'
                                : 'Passwort festlegen',
                            enabled: !_busy,
                            show: _showPw,
                            onToggle: () => setState(() => _showPw = !_showPw),
                            textInputAction: TextInputAction.next,
                          ),
                          if (_step != _Step.login) ...[
                            const SizedBox(height: 12),
                            _PasswordField(
                              controller: _pw2C,
                              label: 'Passwort bestätigen',
                              enabled: !_busy,
                              show: _showPw,
                              onToggle: () =>
                                  setState(() => _showPw = !_showPw),
                              textInputAction: TextInputAction.done,
                            ),
                          ],
                        ],

                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Colors.redAccent.shade100,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        ElevatedButton(
                          onPressed: _busy
                              ? null
                              : (_step == _Step.username
                                    ? _checkUsername
                                    : _submit),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: fg,
                            foregroundColor: bg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _busy
                              ? SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: bg,
                                  ),
                                )
                              : Text(
                                  _step == _Step.username
                                      ? 'Continue'
                                      : _step == _Step.login
                                      ? 'Login'
                                      : _step == _Step.signup
                                      ? 'Account erstellen'
                                      : 'Passwort speichern',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),

                        if (_step != _Step.username) ...[
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _busy ? null : _resetToUsername,
                            child: Text(
                              'Anderen Username verwenden',
                              style: TextStyle(
                                color: fg.withOpacity(0.85),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final TextInputAction textInputAction;

  const _Field({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.onSurface;
    return TextField(
      controller: controller,
      enabled: enabled,
      textInputAction: textInputAction,
      style: TextStyle(color: fg, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: fg.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: fg.withOpacity(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: fg.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: fg.withOpacity(0.28)),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool show;
  final VoidCallback onToggle;
  final TextInputAction textInputAction;

  const _PasswordField({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.show,
    required this.onToggle,
    required this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.onSurface;

    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: !show,
      textInputAction: textInputAction,
      style: TextStyle(color: fg, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: fg.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: fg.withOpacity(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: fg.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: fg.withOpacity(0.28)),
        ),
        suffixIcon: IconButton(
          onPressed: enabled ? onToggle : null,
          icon: Icon(
            show ? Icons.visibility_off : Icons.visibility,
            color: fg.withOpacity(0.7),
          ),
        ),
      ),
    );
  }
}
