  import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../localization/app_language.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.displayName,
    required this.email,
    required this.phoneNumber,
  });

  final String displayName;
  final String email;
  final String phoneNumber;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  final _otpController = TextEditingController();

  bool _isSaving = false;
  bool _messageIsError = false;
  String? _message;
  String? _pendingEmailChange;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.displayName);
    _emailController = TextEditingController(text: widget.email);
    _phoneController = TextEditingController(text: widget.phoneNumber);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
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

    final unableToUpdateMessage = context.tr('Unable to update profile.');
    final emailChangeFailedMessage = context.tr(
      'Profile saved, but email change failed:',
    );

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      if (profileChanges.isNotEmpty) {
        profileChanges['updated_at'] = DateTime.now().toIso8601String();
        await Supabase.instance.client
            .from('profiles')
            .update(profileChanges)
            .eq('id', user.id);
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

    if (!RegExp(r'^\d{8}$').hasMatch(code)) {
      setState(() {
        _messageIsError = true;
        _message = context.tr(
          'Please enter the 8-digit verification code.',
        );
      });
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
          _message = context.tr(
            'Turn off Secure email change in Supabase, then request a new code.',
          );
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = context.tr('Something went wrong. Please try again.');
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
        _message = context.tr('Verification code resent.');
      });
      _startResendCountdown();
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
                  context.tr('Confirm new email'),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr('Enter the 8-digit code sent to your new email'),
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
                  onSubmitted: (_) => _verifyEmailChange(),
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
                        : Text(context.tr('Verify Code')),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _resendSeconds == 0 && !_isSaving
                      ? _resendEmailChangeCode
                      : null,
                  child: Text(
                    _resendSeconds == 0
                        ? context.tr('Resend Code')
                        : '${context.tr('Resend code in')} '
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
        title: Text(context.tr('Edit Profile')),
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
                            labelText: context.tr('Display name'),
                            prefixIcon: const Icon(Icons.person_outline),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return context.tr(
                                'Display name cannot be empty.',
                              );
                            }
                            if (value.trim().length > 50) {
                              return context.tr(
                                'Display name must be 50 characters or fewer.',
                              );
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
                            labelText: context.tr('Email'),
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (!RegExp(
                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                            ).hasMatch(email)) {
                              return context.tr(
                                'Please enter a valid email address.',
                              );
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
                            labelText: context.tr('Phone number'),
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
                              return context.tr(
                                'Use 10–11 digits starting with 01.',
                              );
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
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
                    label: Text(context.tr('Save')),
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
