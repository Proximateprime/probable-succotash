import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/supabase_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    Key? key,
    this.startInSignUpMode = false,
  }) : super(key: key);

  final bool startInSignUpMode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _passwordVisible = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.startInSignUpMode;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _statusMessage = 'Please fill all fields';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _statusIsError = false;
    });

    try {
      final supabase = context.read<SupabaseService>();
      final response = await supabase.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final signedInUserId = response.user?.id ?? supabase.currentUserId;
      if (signedInUserId != null) {
        await supabase.ensureCurrentUserProfile();
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home_dashboard');
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Sign in failed: $e';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    if (_emailController.text.isEmpty) {
      setState(() {
        _statusMessage = 'Enter your email to receive a reset link.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _statusIsError = false;
    });

    try {
      final supabase = context.read<SupabaseService>();
      await supabase.resetPassword(email: _emailController.text.trim());
      setState(() {
        _statusMessage = 'Check your inbox for a password reset link.';
        _statusIsError = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Reset password failed: $e';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResendConfirmation() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _statusMessage = 'Enter your email first, then tap resend.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _statusIsError = false;
    });

    try {
      final supabase = context.read<SupabaseService>();
      await supabase.resendSignupConfirmation(email: email);
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Confirmation email resent. Check inbox/spam for $email.';
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not resend confirmation: $e';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignUp() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _statusMessage = 'Please fill all fields';
        _statusIsError = true;
      });
      return;
    }

    if (_passwordController.text.length < 6) {
      setState(() {
        _statusMessage = 'Password must be at least 6 characters';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _statusIsError = false;
    });

    try {
      final supabase = context.read<SupabaseService>();
      final response = await supabase.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final newUserId = response.user?.id ?? supabase.currentUserId;

      if (newUserId != null) {
        await supabase.ensureCurrentUserProfile();
      }

      if (response.session != null || supabase.currentUserId != null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/home_dashboard');
        return;
      }

      if (!mounted) return;
      setState(() {
        _isSignUp = false;
        _statusMessage =
            'Account created. Check your email to confirm, then sign in.';
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final errorText = e.toString();
        if (errorText.toLowerCase().contains('already registered')) {
          _statusMessage = 'That email already has an account. Try signing in.';
        } else {
          _statusMessage = 'Sign up failed: $e';
        }
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              const SizedBox(height: 32),
              const Icon(
                Icons.location_on_outlined,
                size: 64,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(height: 16),
              const Text(
                'SprayMap Pro',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
              const Text(
                'Precision Coverage Tracking',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 48),
              AppCard(
                child: Column(
                  children: [
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                        ),
                      ),
                      obscureText: !_passwordVisible,
                      autofillHints: _isSignUp
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _isLoading
                          ? null
                          : (_isSignUp ? _handleSignUp() : _handleSignIn()),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading ? null : _handleForgotPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading ? null : _handleResendConfirmation,
                  child: const Text('Resend confirmation email'),
                ),
              ),
              const SizedBox(height: 8),
              if (_statusMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      color: _statusIsError ? Colors.red : Colors.green,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 24),
              AppPrimaryButton(
                onPressed: _isLoading
                    ? null
                    : (_isSignUp ? _handleSignUp : _handleSignIn),
                isLoading: _isLoading,
                label: _isSignUp ? 'Sign Up' : 'Sign In',
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_isSignUp
                      ? 'Already have an account? '
                      : "Don't have an account? "),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(_isSignUp ? 'Sign In' : 'Sign Up'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
