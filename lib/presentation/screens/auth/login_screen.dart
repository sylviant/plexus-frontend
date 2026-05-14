import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/socket_provider.dart';
import 'package:plexus/core/providers/notification_provider.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static const Color _primary     = Color(0xFF1A237E);
  static const Color _primaryMid  = Color(0xFF3949AB);
  static const Color _surface     = Color(0xFFF4F6FB);
  static const Color _border      = Color(0xFFE2E8F0);
  static const Color _textMain    = Color(0xFF0F172A);
  static const Color _textSub     = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.login(_emailController.text, _passwordController.text);
      _onLoginSuccess(auth);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.signInWithGoogle();
      _onLoginSuccess(auth);
    } catch (e) {
      _showError("Échec de la connexion Google");
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _onLoginSuccess(AuthProvider auth) {
    if (auth.currentUser != null && mounted) {
      final userId = auth.currentUser!.id;
      final notifProvider =
          Provider.of<NotificationProvider>(context, listen: false);
      Provider.of<SocketProvider>(context, listen: false)
          .connect(userId, notifProvider);
      notifProvider.fetchNotifications(userId);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  // LOGO
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [_primary, _primaryMid]),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Image.asset('assets/logo/logo.png', errorBuilder: (c,e,s) => const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 40)),
                        ),
                        const SizedBox(height: 14),
                        const Text('PLEXUS', style: TextStyle(color: _primary, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 6)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: _primary.withOpacity(0.07), blurRadius: 30, offset: const Offset(0, 10))],
                    ),
                    padding: const EdgeInsets.all(28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Connexion', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _textMain)),
                          const SizedBox(height: 28),
                          
                          _styledField(_emailController, 'Adresse e-mail', Icons.alternate_email_rounded),
                          const SizedBox(height: 20),
                          
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: _inputDecoration(
                              hint: 'Mot de passe',
                              icon: Icons.lock_outline_rounded,
                              suffix: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: _textSub, size: 20),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                          ),
                          
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(onPressed: () => context.push('/forgot-password'), child: const Text('Mot de passe oublié ?', style: TextStyle(color: _primaryMid))),
                          ),
                          
                          const SizedBox(height: 20),
                          
                          SizedBox(
                            width: double.infinity, height: 55,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _submit,
                              style: ElevatedButton.styleFrom(backgroundColor: _primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('SE CONNECTER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          
                          const SizedBox(height: 25),
                          const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("OU")), Expanded(child: Divider())]),
                          const SizedBox(height: 25),

                          // BOUTON GOOGLE CORRIGÉ (OVERFLOW + IMAGE)
                          SizedBox(
                            width: double.infinity, height: 55,
                            child: OutlinedButton(
                              onPressed: _isGoogleLoading ? null : _handleGoogleSignIn,
                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), side: const BorderSide(color: _border, width: 1.5)),
                              child: _isGoogleLoading 
                                ? const CircularProgressIndicator()
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.g_mobiledata_rounded, color: _primary, size: 30),
                                      const SizedBox(width: 8),
                                      const Flexible(
                                        child: Text(
                                          "Continuer avec Google",
                                          style: TextStyle(color: _textMain, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                            ),
                          ),
                        ],
                      ),
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

  Widget _styledField(TextEditingController c, String h, IconData i) {
    return TextFormField(
      controller: c,
      decoration: _inputDecoration(hint: h, icon: i),
      validator: (v) => v!.isEmpty ? 'Requis' : null,
    );
  }

  InputDecoration _inputDecoration({required String hint, required IconData icon, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: _textSub, size: 20),
      suffixIcon: suffix,
      filled: true, fillColor: _surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size; final Color color;
  const _Blob({required this.size, required this.color});
  @override Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
