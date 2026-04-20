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

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
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
      final notifProvider = Provider.of<NotificationProvider>(context, listen: false);
      Provider.of<SocketProvider>(context, listen: false).connect(userId, notifProvider);
      notifProvider.fetchNotifications(userId);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.replaceAll('Exception: ', '')), 
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF1A237E);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 280,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, Color(0xFF3949AB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(100)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Hero(
                    tag: 'logo',
                    child: Image.asset(
                      'assets/logo/logo.png',
                      height: 80,
                      errorBuilder: (context, error, stackTrace) => 
                        const Icon(Icons.shopping_bag_rounded, size: 60, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('PLEXUS', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 30),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Connexion', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: primaryColor)),
                    const SizedBox(height: 30),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email_rounded)),
                      validator: (v) => v!.isEmpty ? 'Veuillez saisir votre email' : null,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => context.push('/forgot-password'), child: const Text('Mot de passe oublié ?', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)))),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
                        ),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
                          child: _isLoading 
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('SE CONNECTER', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("OU", style: TextStyle(color: Colors.grey, fontSize: 10))), Expanded(child: Divider())]),
                    const SizedBox(height: 20),
                    
                    // --- BOUTON GOOGLE CORRIGÉ (OVERFLOW + IMAGE) ---
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: OutlinedButton(
                        onPressed: _isGoogleLoading ? null : _handleGoogleSignIn,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          side: BorderSide(color: Colors.grey[200]!, width: 2),
                        ),
                        child: _isGoogleLoading 
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min, // S'assure que le contenu reste centré
                              children: [
                                Image.network(
                                  'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg', 
                                  width: 20,
                                  errorBuilder: (c,e,s) => const Icon(Icons.g_mobiledata, color: primaryColor), // Icône de secours
                                ),
                                const SizedBox(width: 10),
                                const Flexible(
                                  child: Text(
                                    "Continuer avec Google", 
                                    style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Text("Nouveau ici ? "), GestureDetector(onTap: () => context.go('/signup'), child: const Text('Inscrivez-vous', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, decoration: TextDecoration.underline)))]))
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
