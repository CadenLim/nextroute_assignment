import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../localization/app_language.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isRegister = false;
  bool _isLoading = false;
  bool _hidePassword = true;
  bool _verificationMessageIsError = false;
  String? _pendingVerificationEmail;
  String? _verificationMessage;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final displayName = _displayNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (_isRegister && displayName.isEmpty) {
      _showMessage(context.tr('Please enter your name.'));
      return;
    }

    if (email.isEmpty || !email.contains('@')) {
      _showMessage(context.tr('Please enter a valid email address.'));
      return;
    }

    if (password.length < 6) {
      _showMessage(context.tr('Password must contain at least 6 characters.'));
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isRegister) {
        final response = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {'display_name': displayName},
        );

        if (!mounted) return;

        if (response.session == null) {
          setState(() {
            _pendingVerificationEmail = email;
            _verificationMessage = null;
          });
          _startResendCountdown();
        } else {
          _showMessage(context.tr('Account created successfully.'));
        }
      } else {
        await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (!mounted) return;
        _showMessage(context.tr('Signed in successfully.'));
      }
    } on AuthException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage(context.tr('Something went wrong. Please try again.'));
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
    FocusScope.of(context).unfocus();
    final code = _otpController.text.trim();
    final email = _pendingVerificationEmail;

    if (email == null) return;
    if (!RegExp(r'^\d{8}$').hasMatch(code)) {
      setState(() {
        _verificationMessageIsError = true;
        _verificationMessage = context.tr(
          'Please enter the 8-digit verification code.',
        );
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _verificationMessage = null;
    });

    try {
      final response = await _supabase.auth.verifyOTP(
        type: OtpType.signup,
        email: email,
        token: code,
      );

      if (!mounted) return;
      if (response.session == null) {
        setState(() {
          _pendingVerificationEmail = null;
          _isRegister = false;
        });
        _showMessage(context.tr('Email verified successfully.'));
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _verificationMessageIsError = true;
        _verificationMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verificationMessageIsError = true;
        _verificationMessage = context.tr(
          'Something went wrong. Please try again.',
        );
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
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      if (!mounted) return;
      _otpController.clear();
      setState(() {
        _verificationMessageIsError = false;
        _verificationMessage = context.tr('Verification code resent.');
      });
      _startResendCountdown();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _verificationMessageIsError = true;
        _verificationMessage = error.message;
      });
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

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Widget _buildVerificationScreen(BuildContext context) {
    final email = _pendingVerificationEmail!;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
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
                        context.tr('Verify your email'),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.tr('Enter the 8-digit code sent to'),
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
                        controller: _otpController,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        textAlign: TextAlign.center,
                        maxLength: 8,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        autofillHints: const [AutofillHints.oneTimeCode],
                        onSubmitted: (_) => _verifyCode(),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 10,
                        ),
                        decoration: InputDecoration(
                          labelText: context.tr('Verification code'),
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
                            color: (_verificationMessageIsError
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
                              : Text(context.tr('Verify Code')),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _resendSeconds == 0 && !_isLoading
                            ? _resendCode
                            : null,
                        child: Text(
                          _resendSeconds == 0
                              ? context.tr('Resend Code')
                              : '${context.tr('Resend code in')} '
                                  '${_resendSeconds}s',
                        ),
                      ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : _changeVerificationEmail,
                        child: Text(context.tr('Change email address')),
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
    if (_pendingVerificationEmail != null) {
      return _buildVerificationScreen(context);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
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
                        context.tr(
                          _isRegister ? 'Create Account' : 'Welcome Back',
                        ),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.tr(
                          _isRegister
                              ? 'Create your NextRoute account'
                              : 'Sign in to continue to NextRoute',
                        ),
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 28),
                      if (_isRegister) ...[
                        TextField(
                          controller: _displayNameController,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: context.tr('Display name'),
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
                          labelText: context.tr('Email'),
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
                          labelText: context.tr('Password'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(
                                    () => _hidePassword = !_hidePassword,
                              );
                            },
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
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
                                  context.tr(
                                    _isRegister ? 'Register' : 'Sign In',
                                  ),
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
                          context.tr(
                            _isRegister
                                ? 'Already have an account? Sign In'
                                : 'New user? Create an account',
                          ),
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
    );
  }
}
