import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/socket_provider.dart';
import 'package:plexus/core/providers/notification_provider.dart';
import 'package:provider/provider.dart';
import 'package:plexus/l10n/l10n.dart';

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
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _logoScaleAnim;

  // ── Design tokens ─────────────────────────────────────────────
  static const Color _primary = Color(0xFF1A237E);
  static const Color _primaryMid = Color(0xFF3949AB);
  static const Color _primarySoft = Color(0xFF5C6BC0);
  static const Color _surface = Color(0xFFF6F7FC);
  static const Color _border = Color(0xFFE3E7F0);
  static const Color _textMain = Color(0xFF0F172A);
  static const Color _textSub = Color(0xFF667085);
  static const Color _danger = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.1, 1.0, curve: Curves.easeOutCubic),
    ));
    _logoScaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
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
      _showError(l10n.echecDeLaConnexionGoogle);
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
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg.replaceAll('Exception: ', ''),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 4,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 360;

    return Scaffold(
      backgroundColor: _surface,
      body: Stack(
        children: [
          // Ambient background blobs — signature decorative layer
          Positioned(
            top: -90,
            right: -60,
            child: _Blob(size: 220, color: _primaryMid.withOpacity(0.10)),
          ),
          Positioned(
            top: 120,
            left: -80,
            child: _Blob(size: 180, color: _primarySoft.withOpacity(0.08)),
          ),
          Positioned(
            bottom: -100,
            right: -40,
            child: _Blob(size: 240, color: _primary.withOpacity(0.06)),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 20 : 28,
                    vertical: 20,
                  ),
                  child: ConstrainedBox(
                    constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 40),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 20),
                            _buildLogo(),
                            const SizedBox(height: 36),
                            _buildFormCard(isCompact),
                            const SizedBox(height: 28),
                            _buildSignupRow(),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return ScaleTransition(
      scale: _logoScaleAnim,
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_primary, _primaryMid],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _primary.withOpacity(0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Image.asset(
              'assets/logo/logo.png',
              errorBuilder: (c, e, s) => const Icon(
                Icons.shopping_bag_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'PLEXUS',
            style: TextStyle(
              color: _primary,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 7,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'MARKETPLACE',
            style: TextStyle(
              color: _textSub,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(bool isCompact) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _border, width: 1),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.06),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      padding: EdgeInsets.all(isCompact ? 22 : 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.connexion,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: _textMain,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.bienvenueIdentifiezVousPourContinuer,
              style: TextStyle(fontSize: 13.5, color: _textSub, height: 1.4),
            ),
            const SizedBox(height: 28),
            _styledLabel(l10n.adresseEMail),
            const SizedBox(height: 8),
            _styledField(
              controller: _emailController,
              focusNode: _emailFocus,
              hint: l10n.exempleDomaineCom,
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 18),
            _styledLabel(l10n.motDePasse),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              obscureText: _obscurePassword,
              style: const TextStyle(
                color: _textMain,
                fontWeight: FontWeight.w500,
                fontSize: 14.5,
              ),
              validator: (v) => (v == null || v.isEmpty) ? l10n.requis : null,
              decoration: _inputDecoration(
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: _textSub,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => context.push('/forgot-password'),
                child: Text(
                  l10n.motDePasseOublie2,
                  style: TextStyle(
                    color: _primaryMid,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildPrimaryButton(),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: Divider(color: _border, thickness: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'OU',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _textSub,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: _border, thickness: 1)),
              ],
            ),
            const SizedBox(height: 24),
            _buildGoogleButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: _isLoading
              ? null
              : const LinearGradient(
            colors: [_primary, _primaryMid],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          color: _isLoading ? _primary.withOpacity(0.6) : null,
          boxShadow: _isLoading
              ? []
              : [
            BoxShadow(
              color: _primary.withOpacity(0.28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          child: _isLoading
              ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.4,
            ),
          )
              : Text(
            l10n.seConnecter,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: _isGoogleLoading ? null : _handleGoogleSignIn,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          side: const BorderSide(color: _border, width: 1.5),
          backgroundColor: Colors.white,
        ),
        child: _isGoogleLoading
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            color: _primary,
            strokeWidth: 2.4,
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _GoogleMark(),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                l10n.continuerAvecGoogle,
                style: TextStyle(
                  color: _textMain,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignupRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l10n.pasEncoreDeCompte,
          style: TextStyle(color: _textSub, fontSize: 14),
        ),
        GestureDetector(
          onTap: () => context.go('/signup'),
          child: Text(
            l10n.sInscrire,
            style: TextStyle(
              color: _primary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _styledLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: _textMain,
    ),
  );

  Widget _styledField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: _textMain,
        fontWeight: FontWeight.w500,
        fontSize: 14.5,
      ),
      decoration: _inputDecoration(hint: hint, icon: icon),
      validator: (v) => (v == null || v.isEmpty) ? l10n.requis : null,
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _textSub.withOpacity(0.7), fontSize: 14),
      prefixIcon: Icon(icon, color: _textSub, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _primaryMid, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _danger, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _danger, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }
}

/// Soft ambient background circle used for the decorative gradient-mesh layer.
class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// Lightweight multi-color "G" mark so the Google button doesn't rely on
/// [Icons.g_mobiledata_rounded], with no external asset dependency.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE3E7F0), width: 1),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Color(0xFF4285F4),
          height: 1,
        ),
      ),
    );
  }
}