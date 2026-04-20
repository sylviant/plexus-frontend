import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // IP DU SERVEUR
  static const String baseUrl = 'http://192.168.1.131:5000/api';

  Future<void> _login() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _emailController.text,
          'password': _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final String token = data['token'];
        
        // On sauvegarde le VRAI token généré par le serveur
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('admin_token', token);
        
        if (mounted) Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        final msg = json.decode(response.body)['msg'] ?? "Identifiants incorrects";
        _showError(msg);
      }
    } catch (e) {
      _showError("Erreur de connexion au serveur ($e)");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings, size: 80, color: Color(0xFF283593)),
              const SizedBox(height: 20),
              const Text("PLEXUS ADMIN", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF283593))),
              const SizedBox(height: 40),
              TextField(controller: _emailController, decoration: const InputDecoration(labelText: "Email Admin", border: OutlineInputBorder())),
              const SizedBox(height: 20),
              TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: "Mot de passe", border: OutlineInputBorder())),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF283593), foregroundColor: Colors.white),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("SE CONNECTER"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
