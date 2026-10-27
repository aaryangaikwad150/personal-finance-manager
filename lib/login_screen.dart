import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'firestore_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isSignUp = false;
  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureConfirm = true;
  String? errorMessage;

  bool _validate() {
    setState(() => errorMessage = null);

    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => errorMessage = 'Please fill in email and password.');
      return false;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => errorMessage = 'Please enter a valid email address.');
      return false;
    }
    if (password.length < 6) {
      setState(() => errorMessage = 'Password must be at least 6 characters.');
      return false;
    }

    if (isSignUp) {
      final username = usernameController.text.trim();
      final confirm = confirmPasswordController.text;

      if (username.isEmpty) {
        setState(() => errorMessage = 'Please choose a username.');
        return false;
      }
      if (username.length < 3) {
        setState(() => errorMessage = 'Username must be at least 3 characters.');
        return false;
      }
      if (password != confirm) {
        setState(() => errorMessage = 'Passwords do not match.');
        return false;
      }
    }

    return true;
  }

  Future<void> _submit() async {
    if (!_validate()) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final email = emailController.text.trim();
    final password = passwordController.text;

    bool success;

    if (isSignUp) {
      final username = usernameController.text.trim();
      success = await safeAuthCall(
        context: context,
        operation: () async {
          final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );

          // Save the username separately so it's available before we navigate.
          final uid = credential.user!.uid;
          try {
            await FirebaseFirestore.instance.collection('profiles').doc(uid).set({
              'displayName': username,
              'email': email,
              'memberSince': Timestamp.now(),
            }, SetOptions(merge: true));
          } catch (_) {
            // Profile doc failing to write shouldn't block account creation —
            // the app already falls back to email/blank name elsewhere.
          }

          await credential.user!.updateDisplayName(username);
        },
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.ink,
            content: Text('Account created! Taking you in...', style: TextStyle(color: AppColors.parchment)),
            duration: Duration(seconds: 2),
          ),
        );
        // AppShell picks up the new session automatically via authStateChanges().
      }
    } else {
      success = await safeAuthCall(
        context: context,
        operation: () => FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        ),
      );
    }

    if (mounted) {
      setState(() {
        isLoading = false;
        if (!success) errorMessage ??= 'Please check your details and try again.';
      });
    }
  }

  void _switchMode() {
    setState(() {
      isSignUp = !isSignUp;
      errorMessage = null;
      passwordController.clear();
      confirmPasswordController.clear();
    });
  }

  InputDecoration _decoration(String label, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.sage),
      floatingLabelAlignment: FloatingLabelAlignment.start,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Personal Finance Manager',
                  style: TextStyle(color: AppColors.parchment, fontSize: 24, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  isSignUp ? 'Create your account' : 'Welcome back',
                  style: const TextStyle(color: AppColors.sage, fontSize: 14),
                ),
                const SizedBox(height: 24),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 360,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.parchment,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Toggle tabs
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.sage.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: isSignUp ? _switchMode : null,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: !isSignUp ? AppColors.gold : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Login',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: !isSignUp ? AppColors.ink : AppColors.sage,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: isSignUp ? null : _switchMode,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSignUp ? AppColors.gold : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Sign Up',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isSignUp ? AppColors.ink : AppColors.sage,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (isSignUp) ...[
                        TextField(
                          controller: usernameController,
                          decoration: _decoration('Username'),
                        ),
                        const SizedBox(height: 14),
                      ],

                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _decoration('Email'),
                      ),
                      const SizedBox(height: 14),

                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: _decoration(
                          'Password',
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: AppColors.sage,
                              size: 20,
                            ),
                            onPressed: () => setState(() => obscurePassword = !obscurePassword),
                          ),
                        ),
                      ),

                      if (isSignUp) ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: obscureConfirm,
                          decoration: _decoration(
                            'Confirm Password',
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureConfirm ? Icons.visibility_off : Icons.visibility,
                                color: AppColors.sage,
                                size: 20,
                              ),
                              onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                            ),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                      ],

                      if (!isSignUp)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: isLoading ? null : _showForgotPasswordDialog,
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
                              child: const Text('Forgot password?',
                                  style: TextStyle(color: AppColors.teal, fontSize: 12)),
                            ),
                          ),
                        ),

                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: isLoading ? null : _submit,
                          child: isLoading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: AppColors.ink, strokeWidth: 2),
                          )
                              : Text(
                            isSignUp ? 'Create Account' : 'Login',
                            style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: isLoading ? null : _switchMode,
                          child: Text(
                            isSignUp ? 'Already have an account? Login' : 'New here? Create an account',
                            style: const TextStyle(color: AppColors.teal),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailController = TextEditingController(text: emailController.text.trim());
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.parchment,
        title: const Text('Reset password', style: TextStyle(color: AppColors.ink)),
        content: TextField(
          controller: resetEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Your email', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.sage)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isEmpty) return;
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final success = await safeAuthCall(
                context: context,
                operation: () => FirebaseAuth.instance.sendPasswordResetEmail(email: email),
              );
              navigator.pop();
              if (success) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Password reset email sent. Check your inbox.')),
                );
              }
            },
            child: const Text('Send link', style: TextStyle(color: AppColors.ink)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }
}