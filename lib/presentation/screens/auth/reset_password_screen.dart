import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Validation de la force du mot de passe
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Entrez un mot de passe';
    if (value.length < 8) return 'Minimum 8 caractères';
    if (!RegExp(r'(?=.*[a-z])(?=.*[0-9])').hasMatch(value)) {
      return 'Lettres et chiffres requis';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Les mots de passe ne correspondent pas"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Provider.of<AuthProvider>(context, listen: false)
          .resetPassword(_codeController.text, _passwordController.text);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Mot de passe mis à jour avec succès !"), backgroundColor: Colors.green),
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF283593);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0, foregroundColor: Colors.black),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nouveau mot de passe',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Créez un mot de passe sécurisé pour votre compte.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 40),

              // Code de vérification
              TextFormField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: 'Code reçu par mail',
                  prefixIcon: const Icon(Icons.security, color: primaryColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
                keyboardType: TextInputType.number,
                validator: (v) => v!.length < 5 ? 'Code invalide' : null,
              ),
              const SizedBox(height: 20),

              // Nouveau Mot de passe
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline, color: primaryColor),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
                validator: _validatePassword,
              ),
              const SizedBox(height: 20),

              // Confirmation
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirmer le mot de passe',
                  prefixIcon: const Icon(Icons.lock_reset, color: primaryColor),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
                validator: (v) => v != _passwordController.text ? 'Les mots de passe diffèrent' : null,
              ),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('RÉINITIALISER LE MOT DE PASSE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
