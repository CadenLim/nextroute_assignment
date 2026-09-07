import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/personal_travel_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.auth, this.passwordLogin});

  final GoTrueClient? auth;
  final PasswordCodeLogin? passwordLogin;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();

  bool _isRegister = false;
  bool _isLoading = false;
  bool _hidePassword = true;
  bool _verificationMessageIsError = false;
  String? _pendingVerificationEmail;
  String? _verificationMessage;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  OtpType _verificationType = OtpType.email;

  GoTrueClient get _auth => widget.auth ?? Supabase.instance.client.auth;

  void _requestOtpFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pendingVerificationEmail != null) {
        _otpFocusNode.requestFocus();
      }
    });
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();

    final displayName = _displayNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (_isRegister && displayName.isEmpty) {
      _showMessage('Please enter your name.');
      return;
    }

    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _showMessage('Please enter a valid email address.');
      return;
    }

    final minimumPasswordLength = _isRegister ? 8 : 6;
    if (password.length < minimumPasswordLength) {
      _showMessage(
        _isRegister
            ? 'Password must contain at least 8 characters.'
            : 'Password must contain at least 6 characters.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isRegister) {
        final response = await _auth.signUp(
          email: email,
          password: password,
          data: {'display_name': displayName},
        );

        if (!mounted) return;

        if (response.session == null) {
          setState(() {
            _verificationType = OtpType.signup;
            _pendingVerificationEmail = email;
            _verificationMessage = null;
          });
          _startResendCountdown();
          _requestOtpFocus();
        } else {
          await _auth.signOut(scope: SignOutScope.local);
          if (!mounted) return;
          _showMessage(
            'Email confirmation is not enabled. Please contact the app administrator.',
          );
        }
      } else {
        await (widget.passwordLogin ?? PasswordCodeLogin(auth: _auth)).sendCode(
          email: email,
          password: password,
        );

        if (!mounted) return;
        _passwordController.clear();
        setState(() {
          _verificationType = OtpType.email;
          _pendingVerificationEmail = email;
          _verificationMessage = null;
        });
        _startResendCountdown();
        _requestOtpFocus();
      }
    } on AuthException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _verifyCode() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    final code = _otpController.text.trim();
    final email = _pendingVerificationEmail;

    if (email == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _verificationMessageIsError = true;
        _verificationMessage = 'Enter the 6-digit code from your email.';
      });
      _requestOtpFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _verificationMessage = null;
    });

    try {
      final response = await _auth.verifyOTP(
        type: _verificationType,
        email: email,
        token: code,
      );

      if (!mounted) return;
      if (response.session == null) {
        setState(() {
          _verificationMessageIsError = true;
          _verificationMessage =
              'Verification did not complete. Please try again.';
        });
      } else {
        _resendTimer?.cancel();
        Navigator.pop(context, true);
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _verificationMessageIsError = true;
        _verificationMessage = error.message;
      });
      _requestOtpFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verificationMessageIsError = true;
        _verificationMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    final email = _pendingVerificationEmail;
    if (email == null || _resendSeconds > 0 || _isLoading) return;

    setState(() {
      _isLoading = true;
      _verificationMessage = null;
    });

    try {
      if (_verificationType == OtpType.signup) {
        await _auth.resend(type: OtpType.signup, email: email);
      } else {
        await _auth.signInWithOtp(email: email, shouldCreateUser: false);
      }
      if (!mounted) return;
      _otpController.clear();
      setState(() {
        _verificationMessageIsError = false;
        _verificationMessage = 'Verification code resent.';
      });
      _startResendCountdown();
      _requestOtpFocus();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _verificationMessageIsError = true;
        _verificationMessage = error.message;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _verificationMessageIsError = true;
          _verificationMessage = 'Something went wrong. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeVerificationEmail() {
    _resendTimer?.cancel();
    _otpController.clear();
    setState(() {
      _pendingVerificationEmail = null;
      _verificationMessage = null;
      _resendSeconds = 0;
    });
  }

  Future<void> _openForgotPassword() async {
    final resetEmail = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _ForgotPasswordScreen(
          auth: _auth,
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
    if (resetEmail == null || !mounted) return;
    _emailController.text = resetEmail;
    _passwordController.clear();
    _showMessage(
      'Password reset successfully. Sign in with your new password.',
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Widget _buildVerificationScreen(BuildContext context) {
    final email = _pendingVerificationEmail!;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(backgroundColor: const Color(0xFFF5F7FF)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 36,
                        backgroundColor: Color(0xFF1E3A8A),
                        child: Icon(
                          Icons.mark_email_read_outlined,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Verify your email',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enter the verification code sent to',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        key: const Key('auth-verification-code'),
                        controller: _otpController,
                        focusNode: _otpFocusNode,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        autofillHints: const [AutofillHints.oneTimeCode],
                        onSubmitted: (_) => _verifyCode(),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                        ),
                        decoration: InputDecoration(
                          hintText: 'XXXXXX',
                          counterText: '',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (_verificationMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                (_verificationMessageIsError
                                        ? Colors.red
                                        : Colors.green)
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _verificationMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _verificationMessageIsError
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _verifyCode,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text('Verify Code'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _resendSeconds == 0 && !_isLoading
                            ? _resendCode
                            : null,
                        child: Text(
                          _resendSeconds == 0
                              ? 'Resend Code'
                              : '${'Resend code in'} '
                                    '${_resendSeconds}s',
                        ),
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : _changeVerificationEmail,
                        child: Text('Change email address'),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,
      child: _pendingVerificationEmail != null
          ? _buildVerificationScreen(context)
          : _buildSignInScreen(context),
    );
  }

  Widget _buildSignInScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(backgroundColor: const Color(0xFFF5F7FF)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 36,
                        backgroundColor: Color(0xFF1E3A8A),
                        child: Icon(
                          Icons.directions_transit,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _isRegister ? 'Create Account' : 'Welcome Back',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRegister
                            ? 'Create your NextRoute account'
                            : 'Enter your password to receive a sign-in code.',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 28),
                      if (_isRegister) ...[
                        TextField(
                          controller: _displayNameController,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Display name',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: _hidePassword,
                        onSubmitted: (_) => _submit(),
                        autofillHints: [
                          _isRegister
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _hidePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () {
                              setState(() => _hidePassword = !_hidePassword);
                            },
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                      ),
                      if (!_isRegister)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const Key('forgot-password'),
                            onPressed: _isLoading ? null : _openForgotPassword,
                            child: Text('Forgot password?'),
                          ),
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isRegister
                                      ? 'Register'
                                      : 'Send sign-in code',
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isRegister = !_isRegister;
                                });
                              },
                        child: Text(
                          _isRegister
                              ? 'Already have an account? Sign In'
                              : 'New user? Create an account',
                        ),
                      ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.pop(context, false),
                        child: Text('Continue as guest'),
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
}

class _ForgotPasswordScreen extends StatefulWidget {
  const _ForgotPasswordScreen({required this.auth, required this.initialEmail});

  final GoTrueClient auth;
  final String initialEmail;

  @override
  State<_ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<_ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _codeFocusNode = FocusNode();
  int _step = 0;
  bool _loading = false;
  bool _hideNewPassword = true;
  bool _hideConfirmation = true;
  bool _recoverySessionEstablished = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail;
  }

  @override
  void dispose() {
    if (_recoverySessionEstablished) {
      unawaited(widget.auth.signOut(scope: SignOutScope.local));
    }
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  void _setError(String message) {
    setState(() {
      _messageIsError = true;
      _message = message;
    });
  }

  void _requestCodeFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _step == 1) _codeFocusNode.requestFocus();
    });
  }

  Future<void> _sendCode({bool resend = false}) async {
    if (_loading) return;
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _setError('Please enter a valid email address.');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await widget.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      _codeController.clear();
      setState(() {
        _step = 1;
        _messageIsError = false;
        _message = resend ? 'Verification code resent.' : null;
      });
      _requestCodeFocus();
    } on AuthException catch (error) {
      if (mounted) _setError(error.message);
    } catch (_) {
      if (mounted) {
        _setError('Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_loading) return;
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _setError('Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final response = await widget.auth.verifyOTP(
        type: OtpType.recovery,
        email: _emailController.text.trim(),
        token: code,
      );
      if (!mounted) return;
      if (response.session == null) {
        _setError('Verification did not complete. Please try again.');
        return;
      }
      setState(() {
        _recoverySessionEstablished = true;
        _step = 2;
        _message = null;
      });
    } on AuthException catch (error) {
      if (mounted) _setError(error.message);
    } catch (_) {
      if (mounted) {
        _setError('Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_loading) return;
    final password = _newPasswordController.text;
    if (password.length < 8) {
      _setError('New password must contain at least 8 characters.');
      return;
    }
    if (_confirmPasswordController.text != password) {
      _setError('New passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await widget.auth.updateUser(UserAttributes(password: password));
      await widget.auth.signOut(scope: SignOutScope.local);
      _recoverySessionEstablished = false;
      if (mounted) Navigator.pop(context, _emailController.text.trim());
    } on AuthException catch (error) {
      if (mounted) _setError(error.message);
    } catch (_) {
      if (mounted) {
        _setError('Unable to update password. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _messageBox() {
    if (_message == null) return const SizedBox();
    final color = _messageIsError ? Colors.red : Colors.green;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _message!,
        softWrap: true,
        style: TextStyle(
          color: _messageIsError ? Colors.red.shade700 : Colors.green.shade700,
        ),
      ),
    );
  }

  Widget _emailStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Enter your account email to receive a reset code.',
        style: const TextStyle(color: Colors.grey),
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('reset-email'),
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _sendCode(),
        decoration: InputDecoration(
          labelText: 'Email',
          prefixIcon: const Icon(Icons.email_outlined),
          border: const OutlineInputBorder(),
        ),
      ),
      _messageBox(),
      const SizedBox(height: 20),
      FilledButton(
        key: const Key('send-reset-code'),
        onPressed: _loading ? null : _sendCode,
        child: _buttonChild('Send reset code'),
      ),
    ],
  );

  Widget _codeStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Enter the 6-digit verification code sent to',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.grey),
      ),
      const SizedBox(height: 4),
      Text(
        _emailController.text.trim(),
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('reset-code'),
        controller: _codeController,
        focusNode: _codeFocusNode,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 6,
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _verifyCode(),
        decoration: const InputDecoration(
          hintText: 'XXXXXX',
          counterText: '',
          border: OutlineInputBorder(),
        ),
      ),
      _messageBox(),
      const SizedBox(height: 20),
      FilledButton(
        key: const Key('verify-reset-code'),
        onPressed: _loading ? null : _verifyCode,
        child: _buttonChild('Verify Code'),
      ),
      TextButton(
        onPressed: _loading ? null : () => _sendCode(resend: true),
        child: Text('Resend Code'),
      ),
      TextButton(
        onPressed: _loading
            ? null
            : () => setState(() {
                _step = 0;
                _message = null;
              }),
        child: Text('Change email address'),
      ),
    ],
  );

  InputDecoration _passwordDecoration({
    required String label,
    required bool hidden,
    required VoidCallback toggle,
  }) => InputDecoration(
    labelText: label,
    prefixIcon: const Icon(Icons.lock_outline),
    border: const OutlineInputBorder(),
    errorMaxLines: 3,
    suffixIcon: IconButton(
      tooltip: (hidden ? 'Show password' : 'Hide password'),
      onPressed: toggle,
      icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
    ),
  );

  Widget _passwordStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Create a new password for your account.',
        style: const TextStyle(color: Colors.grey),
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('reset-new-password'),
        controller: _newPasswordController,
        obscureText: _hideNewPassword,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.next,
        decoration: _passwordDecoration(
          label: 'New password',
          hidden: _hideNewPassword,
          toggle: () => setState(() => _hideNewPassword = !_hideNewPassword),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('reset-confirm-password'),
        controller: _confirmPasswordController,
        obscureText: _hideConfirmation,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _resetPassword(),
        decoration: _passwordDecoration(
          label: 'Confirm new password',
          hidden: _hideConfirmation,
          toggle: () => setState(() => _hideConfirmation = !_hideConfirmation),
        ),
      ),
      _messageBox(),
      const SizedBox(height: 20),
      FilledButton(
        key: const Key('reset-password-submit'),
        onPressed: _loading ? null : _resetPassword,
        child: _buttonChild('Update password'),
      ),
    ],
  );

  Widget _buttonChild(String label) => _loading
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
      : Text(label);

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      0 => 'Forgot password',
      1 => 'Verify reset code',
      _ => 'Create new password',
    };
    return PopScope(
      canPop: !_loading,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FF),
        appBar: AppBar(
          title: Text(title),
          backgroundColor: const Color(0xFFF5F7FF),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: switch (_step) {
                      0 => _emailStep(),
                      1 => _codeStep(),
                      _ => _passwordStep(),
                    },
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

// -----------------------------------------------------------------------------
// Authentication gate and guest profile
// -----------------------------------------------------------------------------

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.signedInScreen, this.authClient});

  final Widget signedInScreen;
  final GoTrueClient? authClient;

  @override
  Widget build(BuildContext context) {
    final auth = authClient ?? Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = auth.currentSession;

        if (session == null) {
          return Scaffold(
            backgroundColor: const Color(0xFFF3F6FA),
            body: SafeArea(child: _GuestProfile(auth: auth)),
          );
        }

        return KeyedSubtree(
          key: ValueKey(session.user.id),
          child: signedInScreen,
        );
      },
    );
  }
}

class _GuestProfile extends StatelessWidget {
  const _GuestProfile({required this.auth});

  final GoTrueClient auth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 52),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF173A7A), Color(0xFF2862E9)],
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Your journeys, saved your way.',
                      style: TextStyle(color: Color(0xFFDCE7FF), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -30),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE4EAF2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEAF2FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_outline_rounded,
                            color: Color(0xFF2862E9),
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          'Welcome to NextRoute',
                          style: TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Sign in to save your routes and manage your profile.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF748198),
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2862E9),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AuthScreen(auth: auth),
                              ),
                            ),
                            child: Text(
                              'Sign In',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Divider(height: 1, color: Color(0xFFE8EDF4)),
                        const SizedBox(height: 18),
                        const _GuestBenefit(
                          icon: Icons.favorite_border_rounded,
                          color: Color(0xFFEF4E5B),
                          background: Color(0xFFFFECEE),
                          title: 'Save favourite routes',
                          subtitle: 'Keep your regular journeys close at hand',
                        ),
                        const SizedBox(height: 14),
                        const _GuestBenefit(
                          icon: Icons.notifications_none_rounded,
                          color: Color(0xFFE88B17),
                          background: Color(0xFFFFF2DE),
                          title: 'Set commute reminders',
                          subtitle: 'Get notified when it is time to leave',
                        ),
                        const SizedBox(height: 14),
                        const _GuestBenefit(
                          icon: Icons.manage_accounts_outlined,
                          color: Color(0xFF8056E8),
                          background: Color(0xFFF0EAFF),
                          title: 'Manage your profile',
                          subtitle: 'Personalise your NextRoute experience',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestBenefit extends StatelessWidget {
  const _GuestBenefit({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF273449),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF8A96A8), fontSize: 9.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<bool> requireSignIn(
  BuildContext context, {
  GoTrueClient? authClient,
  PasswordCodeLogin? passwordLogin,
}) async {
  final auth = authClient ?? Supabase.instance.client.auth;
  if (auth.currentSession != null) return true;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Sign in to save this route'),
      content: Text(
        'You can explore routes as a guest. Sign in to keep your favourites across devices.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Sign In'),
        ),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return false;
  await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => AuthScreen(auth: auth, passwordLogin: passwordLogin),
    ),
  );
  return auth.currentSession != null;
}

// -----------------------------------------------------------------------------
// Profile editing and password management
// -----------------------------------------------------------------------------

Future<bool?> showChangePasswordDialog(
  BuildContext context, {
  PersonalTravelService? service,
  PasswordCodeLogin? passwordLogin,
  Future<void> Function(String oldPassword, String newPassword)? changePassword,
}) {
  final profileService =
      service ?? (changePassword == null ? PersonalTravelService() : null);
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ChangePasswordDialog(
      onUpdate: (oldPassword, newPassword) async {
        if (changePassword != null) {
          await changePassword(oldPassword, newPassword);
        } else {
          await profileService!.changePassword(
            oldPassword: oldPassword,
            newPassword: newPassword,
            passwordLogin: passwordLogin,
          );
        }
      },
    ),
  );
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.displayName,
    required this.email,
    required this.phoneNumber,
    this.service,
    this.passwordLogin,
    this.changePassword,
  });

  final String displayName;
  final String email;
  final String phoneNumber;
  final PersonalTravelService? service;
  final PasswordCodeLogin? passwordLogin;
  final Future<void> Function(String oldPassword, String newPassword)?
  changePassword;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  PersonalTravelService? _service;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();

  bool _isSaving = false;
  bool _messageIsError = false;
  String? _message;
  String? _pendingEmailChange;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ??
        (widget.changePassword == null ? PersonalTravelService() : null);
    _nameController = TextEditingController(text: widget.displayName);
    _emailController = TextEditingController(text: widget.email);
    _phoneController = TextEditingController(text: widget.phoneNumber);
  }

  Future<void> _changePassword() async {
    final changed = await showChangePasswordDialog(
      context,
      service: _service,
      passwordLogin: widget.passwordLogin,
      changePassword: widget.changePassword,
    );
    if (changed == true && mounted) {
      setState(() {
        _messageIsError = false;
        _message = 'Password updated successfully.';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  void _requestOtpFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pendingEmailChange != null) {
        _otpFocusNode.requestFocus();
      }
    });
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phoneNumber = _phoneController.text.trim();
    final profileChanges = <String, dynamic>{};

    if (name != widget.displayName) {
      profileChanges['display_name'] = name;
    }
    if (phoneNumber != widget.phoneNumber) {
      profileChanges['phone_number'] = phoneNumber;
    }
    final emailChanged = email != widget.email;

    if (profileChanges.isEmpty && !emailChanged) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final unableToUpdateMessage = 'Unable to update profile.';
    final emailChangeFailedMessage = (
      'Profile saved, but email change failed:',
    );

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      if (profileChanges.isNotEmpty) {
        await (_service ?? PersonalTravelService()).updateProfile(
          displayName: profileChanges['display_name'] as String?,
          phoneNumber: profileChanges['phone_number'] as String?,
        );
      }

      if (emailChanged) {
        try {
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(email: email),
          );
        } on AuthException catch (error) {
          if (!mounted) return;
          setState(() {
            _messageIsError = true;
            _message = '$emailChangeFailedMessage ${error.message}';
          });
          return;
        }

        if (!mounted) return;
        setState(() {
          _messageIsError = false;
          _message = null;
          _pendingEmailChange = email;
        });
        _startResendCountdown();
        _requestOtpFocus();
      } else if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = unableToUpdateMessage;
      });
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _verifyEmailChange() async {
    FocusScope.of(context).unfocus();
    final newEmail = _pendingEmailChange;
    final code = _otpController.text.trim();
    if (newEmail == null) return;

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _messageIsError = true;
        _message = 'Please enter the 6-digit verification code.';
      });
      _requestOtpFocus();
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      final auth = Supabase.instance.client.auth;
      final verificationResponse = await auth.verifyOTP(
        type: OtpType.emailChange,
        email: newEmail,
        token: code,
      );
      if (!mounted) return;

      var confirmedEmail = verificationResponse.user?.email;
      if (confirmedEmail?.toLowerCase() != newEmail.toLowerCase()) {
        final refreshResponse = await auth.refreshSession();
        confirmedEmail = refreshResponse.user?.email;
      }

      if (!mounted) return;
      if (confirmedEmail?.toLowerCase() != newEmail.toLowerCase()) {
        setState(() {
          _messageIsError = true;
          _message =
              'Turn off Secure email change in Supabase, then request a new code.';
        });
        return;
      }

      Navigator.pop(context, confirmedEmail);
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = error.message;
      });
      _requestOtpFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _resendEmailChangeCode() async {
    final email = _pendingEmailChange;
    if (email == null || _resendSeconds > 0 || _isSaving) return;

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.emailChange,
        email: email,
      );
      if (!mounted) return;
      _otpController.clear();
      setState(() {
        _messageIsError = false;
        _message = 'Verification code resent.';
      });
      _startResendCountdown();
      _requestOtpFocus();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = error.message;
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildEmailVerificationBody(BuildContext context) {
    final email = _pendingEmailChange!;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 52,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(height: 16),
                Text(
                  'Confirm new email',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Enter the 6-digit code sent to your new email',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('email-change-verification-code'),
                  controller: _otpController,
                  focusNode: _otpFocusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofillHints: const [AutofillHints.oneTimeCode],
                  onSubmitted: (_) => _verifyEmailChange(),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 10,
                  ),
                  decoration: InputDecoration(
                    hintText: 'XXXXXX',
                    counterText: '',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_messageIsError ? Colors.red : Colors.green)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _messageIsError
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _verifyEmailChange,
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('Verify Code'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _resendSeconds == 0 && !_isSaving
                      ? _resendEmailChangeCode
                      : null,
                  child: Text(
                    _resendSeconds == 0
                        ? 'Resend Code'
                        : '${'Resend code in'} '
                              '${_resendSeconds}s',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: Text('Edit Profile'),
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF1E3A8A),
      ),
      body: _pendingEmailChange != null
          ? _buildEmailVerificationBody(context)
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _nameController,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Display name',
                                  prefixIcon: const Icon(Icons.person_outline),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Display name cannot be empty.';
                                  }
                                  if (value.trim().length > 50) {
                                    return 'Display name must be 50 characters or fewer.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: const Icon(Icons.email_outlined),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final email = value?.trim() ?? '';
                                  if (!RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(email)) {
                                    return 'Please enter a valid email address.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.done,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                maxLength: 11,
                                onFieldSubmitted: (_) => _saveProfile(),
                                decoration: InputDecoration(
                                  labelText: 'Phone number',
                                  prefixIcon: const Icon(Icons.phone_outlined),
                                  hintText: '0121111111',
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final phoneNumber = value?.trim() ?? '';
                                  if (phoneNumber.isEmpty) return null;
                                  if (!RegExp(
                                    r'^01\d{8,9}$',
                                  ).hasMatch(phoneNumber)) {
                                    return 'Use 10–11 digits starting with 01.';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        key: const Key('change-password'),
                        onPressed: _isSaving ? null : _changePassword,
                        icon: const Icon(Icons.password_outlined),
                        label: Text('Change password'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: (_messageIsError ? Colors.red : Colors.green)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _messageIsError
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _saveProfile,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.onUpdate});

  final Future<void> Function(String oldPassword, String newPassword) onUpdate;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _saving = false;
  bool _hideOldPassword = true;
  bool _hideNewPassword = true;
  bool _hideConfirmation = true;
  String? _requestError;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _requestError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      await widget.onUpdate(
        _oldPasswordController.text,
        _newPasswordController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (error) {
      if (!mounted) return;
      final isWrongPassword = error.message.toLowerCase().contains(
        'invalid login credentials',
      );
      setState(() {
        _requestError = isWrongPassword
            ? 'Old password is incorrect.'
            : error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requestError = 'Unable to update password. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    required bool hidden,
    required VoidCallback toggleVisibility,
  }) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    suffixIcon: IconButton(
      tooltip: (hidden ? 'Show password' : 'Hide password'),
      onPressed: toggleVisibility,
      icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
    ),
    border: const OutlineInputBorder(),
    errorMaxLines: 3,
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text('Change password'),
        content: SizedBox(
          width: 360,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    key: const Key('old-password'),
                    controller: _oldPasswordController,
                    obscureText: _hideOldPassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.next,
                    decoration: _decoration(
                      label: 'Old password',
                      icon: Icons.lock_outline,
                      hidden: _hideOldPassword,
                      toggleVisibility: () =>
                          setState(() => _hideOldPassword = !_hideOldPassword),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter your old password.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('new-password'),
                    controller: _newPasswordController,
                    obscureText: _hideNewPassword,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    decoration: _decoration(
                      label: 'New password',
                      icon: Icons.lock_reset,
                      hidden: _hideNewPassword,
                      toggleVisibility: () =>
                          setState(() => _hideNewPassword = !_hideNewPassword),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 8) {
                        return 'New password must contain at least 8 characters.';
                      }
                      if (value == _oldPasswordController.text) {
                        return 'New password must be different from the old password.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('confirm-password'),
                    controller: _confirmPasswordController,
                    obscureText: _hideConfirmation,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _saving ? null : _submit(),
                    decoration: _decoration(
                      label: 'Confirm new password',
                      icon: Icons.verified_user_outlined,
                      hidden: _hideConfirmation,
                      toggleVisibility: () => setState(
                        () => _hideConfirmation = !_hideConfirmation,
                      ),
                    ),
                    validator: (value) => value != _newPasswordController.text
                        ? 'New passwords do not match.'
                        : null,
                  ),
                  if (_requestError != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      key: const Key('password-request-error'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _requestError!,
                        softWrap: true,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-password-change'),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text('Update password'),
          ),
        ],
      ),
    );
  }
}
