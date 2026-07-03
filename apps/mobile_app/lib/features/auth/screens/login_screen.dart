import 'package:mobile_app/core/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../../dashboard/dashboard_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthService();

  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    final input = _email.text.trim();
    final password = _password.text.trim();

    if (input.isEmpty || password.isEmpty) {
      setState(() => _error = "Email/Phone and password cannot be empty");
      return;
    }

    final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    final phoneRegExp = RegExp(r'^\d{10}$');
    
    bool isPhone = phoneRegExp.hasMatch(input);
    bool isEmail = emailRegExp.hasMatch(input);

    if (!isEmail && !isPhone) {
      setState(() => _error = "Please enter a valid email or 10-digit phone");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // If user typed a phone number, append the dummy domain to login
      final loginEmail = isPhone ? '$input@catering.app' : input;
      await _auth.signIn(loginEmail, password);

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          // Attempt to set online status. If the column doesn't exist yet, ignore the error locally.
          await Supabase.instance.client
              .from('profiles')
              .update({'is_online': true})
              .eq('id', user.id);
        } catch (e) {
          debugPrint(
            'Online status update failed (SQL column might be missing): $e',
          );
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Login successful"),
          backgroundColor: AppTheme.activeEmerald,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } on AuthException catch (e) {
      setState(() {
        _error = e.message.contains("Invalid login credentials")
            ? "Incorrect phone number/email or password"
            : e.message;
      });
    } catch (_) {
      setState(() {
        _error = "Something went wrong. Please try again.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: AppTheme.background,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 80),
                // Logo or Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.softShadow,
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: const Icon(
                    Icons.restaurant_menu,
                    size: 80,
                    color: AppTheme.pendingAmber,
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Catering Ops',
                  style: TextStyle(
                    color: AppTheme.titleColor,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const Text(
                  'Premium Management Suite',
                  style: TextStyle(color: AppTheme.labelColor, fontSize: 16),
                ),
                const SizedBox(height: 60),

                // Form Container
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppTheme.softShadow,
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Column(
                    children: [
                      _buildTextField(
                        controller: _email,
                        label: 'Email or Phone Number',
                        icon: Icons.person_outline,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: _password,
                        label: 'Password',
                        icon: Icons.lock_outline,
                        obscureText: true,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppTheme.errorRed,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 30),
                      _buildLoginButton(),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SignUpScreen(),
                      ),
                    );
                  },
                  child: RichText(
                    text: const TextSpan(
                      text: "Don't have an account? ",
                      style: TextStyle(color: AppTheme.labelColor),
                      children: [
                        TextSpan(
                          text: 'Sign Up',
                          style: TextStyle(
                            color: AppTheme.pendingAmber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTheme.titleColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.labelColor),
        prefixIcon: Icon(icon, color: AppTheme.labelColor),
        filled: true,
        fillColor: AppTheme.background,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.pendingAmber, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _loading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.titleColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
          shadowColor: AppTheme.titleColor.withOpacity(0.2),
        ),
        child: _loading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'LOGIN',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
      ),
    );
  }
}
