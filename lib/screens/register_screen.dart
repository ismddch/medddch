import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../utils/theme.dart';
import 'main_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      password: _passCtrl.text.trim(),
    );

    if (success && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء حساب'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () {
            context.read<AuthProvider>().clearError();
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // ─── Header ─────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'حساب جديد',
                    style: GoogleFonts.cairo(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'أدخل بياناتك للتسجيل',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ─── Error ──────────────────────────
                  Consumer<AuthProvider>(
                    builder: (_, auth, __) {
                      if (auth.error == null) return const SizedBox.shrink();
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.danger.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          auth.error!,
                          style: GoogleFonts.cairo(
                            color: AppTheme.danger,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),

                  // ─── Name ───────────────────────────
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'الاسم الكامل',
                      prefixIcon:
                          Icon(Icons.person_outline, color: AppTheme.accent),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'أدخل اسمك' : null,
                  ),
                  const SizedBox(height: 14),

                  // ─── Phone ──────────────────────────
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      hintText: 'رقم الهاتف',
                      prefixIcon:
                          Icon(Icons.phone_outlined, color: AppTheme.accent),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'أدخل رقم الهاتف';
                      final digits = v.trim().replaceAll(RegExp(r'\D'), '');
                      if (digits.length < 8) return 'رقم الهاتف يجب أن يكون 8 أرقام على الأقل';
                      if (!RegExp(r'^[234]').hasMatch(digits)) return 'يجب أن يبدأ الرقم بـ 2 أو 3 أو 4';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // ─── Password ───────────────────────
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: 'كلمة المرور',
                      prefixIcon: const Icon(Icons.lock_outline,
                          color: AppTheme.accent),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppTheme.textMuted,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'أدخل كلمة المرور';
                      if (v.length < 6) return 'كلمة المرور قصيرة جداً';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  const SizedBox(height: 32),

                  // ─── Register Button ────────────────
                  Consumer<AuthProvider>(
                    builder: (_, auth, __) {
                      return SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: auth.isLoading ? null : _register,
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('تسجيل'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
