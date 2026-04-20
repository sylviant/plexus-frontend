import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(5, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(5, (_) => FocusNode());
  bool _isLoading = false;
  
  // Logique du Timer de renvoi
  int _secondsRemaining = 60;
  Timer? _timer;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    setState(() {
      _secondsRemaining = 60;
      _canResend = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        setState(() {
          _canResend = true;
          timer.cancel();
        });
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _controllers) c.dispose();
    for (var f in _focusNodes) f.dispose();
    super.dispose();
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;
    
    try {
      await Provider.of<AuthProvider>(context, listen: false).resendVerificationCode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Un nouveau code a été envoyé !"), backgroundColor: Colors.blueAccent),
        );
        _startTimer(); // Relancer le décompte
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _verify() async {
    String code = _controllers.map((c) => c.text).join();
    if (code.length < 5) return;

    setState(() => _isLoading = true);

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.verifyCode(code);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Email vérifié ! Connectez-vous maintenant."), backgroundColor: Colors.green),
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
    final email = Provider.of<AuthProvider>(context).pendingEmail ?? "votre email";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0, foregroundColor: Colors.black),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 80, color: primaryColor),
            const SizedBox(height: 30),
            const Text('Vérification', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              'Un code à 5 chiffres a été envoyé à :\n$email',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 40),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(5, (index) => _buildOtpBox(index)),
            ),

            const SizedBox(height: 50),

            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('VÉRIFIER', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 25),
            
            // Bouton de renvoi avec Timer
            TextButton(
              onPressed: _canResend ? _resendCode : null,
              child: Text(
                _canResend 
                  ? "Renvoyer le code" 
                  : "Renvoyer le code dans ($_secondsRemaining s)",
                style: TextStyle(
                  color: _canResend ? primaryColor : Colors.grey,
                  fontWeight: _canResend ? FontWeight.bold : FontWeight.normal
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 50,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: "",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF283593), width: 2),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 4) {
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
          if (index == 4 && value.isNotEmpty) {
            _verify();
          }
        },
      ),
    );
  }
}
