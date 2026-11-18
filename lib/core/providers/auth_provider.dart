import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:plexus/core/models/user_type.dart';
import 'package:plexus/core/providers/user_provider.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:plexus/core/api_config.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plexus/l10n/l10n.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  ChatUser? _currentUser;
  bool _isApproved = false;
  late UserProvider _userProvider;
  String? _pendingEmail;

  String? _myReferralCode;
  double _referralEarnings = 0.0;
  double _referralSavings = 0.0;

  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  String? get token => _token;
  ChatUser? get currentUser => _currentUser;
  bool get isAuthenticated => _token != null;
  bool get isApproved => _isApproved;
  String? get pendingEmail => _pendingEmail;
  String? get myReferralCode => _myReferralCode;
  double get referralEarnings => _referralEarnings;
  double get referralSavings => _referralSavings;

  AuthProvider() {
    _loadPersistedData();
  }

  void updateUserProvider(UserProvider userProvider) {
    _userProvider = userProvider;
  }

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedToken = prefs.getString('auth_token');
    final String? savedUserJson = prefs.getString('user_data');

    if (savedToken != null && savedUserJson != null) {
      _token = savedToken;
      final userData = json.decode(savedUserJson);
      await _applyUserData(userData);
      notifyListeners();
    }
  }

  Future<void> _saveDataLocally(String token, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_data', json.encode(user));
  }

  Future<void> _clearLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');
  }

  void updateLocalUserData(Map<String, dynamic> userData) async {
    if (_currentUser == null) return;
    _currentUser = ChatUser(
      id: userData['id']?.toString() ?? _currentUser!.id,
      firstName: userData['name'] ?? _currentUser!.firstName,
      profileImage: userData['profileImage'] ?? _currentUser!.profileImage,
    );
    _isApproved = userData['isApproved'] ?? _isApproved;
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('user_data', json.encode(userData));
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/auth/login');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveDataLocally(data['token'], data['user']);
        await _handleAuthResponse(data);
      } else {
        throw Exception(json.decode(response.body)['msg'] ?? l10n.identifiantsIncorrects);
      }
    } catch (e) {
      throw Exception(ApiConfig.handleNetworkError(e));
    }
  }

  // ✅ CORRIGÉ : gestion Web (signInWithPopup) + Mobile (google_sign_in)
  Future<void> signInWithGoogle({String? referralCode, String? role}) async {
    try {
      fb.UserCredential userCredential;

      if (kIsWeb) {
        // ✅ Web : signInWithPopup — obligatoire sur Flutter Web
        final fb.GoogleAuthProvider googleProvider = fb.GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        // ✅ Mobile : méthode classique avec google_sign_in
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return;
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final fb.AuthCredential credential = fb.GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        userCredential = await _auth.signInWithCredential(credential);
      }

      final fb.User? firebaseUser = userCredential.user;
      if (firebaseUser != null) {
        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/auth/google'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'name': firebaseUser.displayName,
            'email': firebaseUser.email,
            'uid': firebaseUser.uid,
            'photo': firebaseUser.photoURL,
            'referredByCode': referralCode,
            'role': role ?? 'client',
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          await _saveDataLocally(data['token'], data['user']);
          await _handleAuthResponse(data);
        } else {
          throw Exception(l10n.leServeurPlexusARejete);
        }
      }
    } catch (e) {
      throw Exception(l10n.erreurGoogleLogin('$e'));
    }
  }

  Future<void> _handleAuthResponse(Map<String, dynamic> responseData) async {
    _token = responseData['token'] ?? _token;
    final user = responseData['user'];
    if (user != null) {
      await _applyUserData(user);
    }
    notifyListeners();
  }

  Future<void> _applyUserData(Map<String, dynamic> user) async {
    final String userId = (user['_id'] ?? user['id']).toString();
    _currentUser = ChatUser(
      id: userId,
      firstName: user['name'],
      profileImage: user['profileImage'],
    );
    _isApproved = user['isApproved'] ?? false;
    _myReferralCode = user['referralCode'];
    _referralEarnings = (user['totalReferralEarnings'] ?? 0.0).toDouble();
    _referralSavings = (user['totalReferralSavings'] ?? 0.0).toDouble();
    if (user['role'] != null) {
      _userProvider.setUserType(
          user['role'] == 'seller' ? UserType.seller : UserType.client);
    }
  }

  Future<void> signUp(
    String name,
    String email,
    String password,
    String role, {
    String? phone,
    String? address,
    File? idFront,
    File? idBack,
    File? selfie,
    String? referralCode,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/auth/register');
    try {
      var request = http.MultipartRequest('POST', url);
      request.fields['name'] = name;
      request.fields['email'] = email;
      request.fields['password'] = password;
      request.fields['role'] = role;
      if (referralCode != null) request.fields['referredByCode'] = referralCode;
      if (role == 'seller') {
        request.fields['phone'] = phone ?? '';
        request.fields['address'] = address ?? '';
        if (idFront != null) {
          request.files.add(await http.MultipartFile.fromPath('idFront', idFront.path));
        }
        if (idBack != null) {
          request.files.add(await http.MultipartFile.fromPath('idBack', idBack.path));
        }
        if (selfie != null) {
          request.files.add(await http.MultipartFile.fromPath('selfie', selfie.path));
        }
      }
      var streamedResponse =
          await request.send().timeout(const Duration(seconds: 30));
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 201) {
        _pendingEmail = email;
        notifyListeners();
      } else {
        throw Exception(
            json.decode(response.body)['msg'] ?? l10n.erreurDInscription);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> verifyCode(String code) async {
    if (_pendingEmail == null) return;
    final url = Uri.parse('${ApiConfig.baseUrl}/auth/verify');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': _pendingEmail, 'code': code}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        _pendingEmail = null;
        notifyListeners();
      } else {
        throw Exception(json.decode(response.body)['msg'] ?? l10n.codeInvalide2);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> resendVerificationCode() async {
    if (_pendingEmail == null) return;
    final url = Uri.parse('${ApiConfig.baseUrl}/auth/resend-code');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': _pendingEmail}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception(
            json.decode(response.body)['msg'] ?? l10n.erreurLorsDuRenvoi);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> requestPasswordReset(String email) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/auth/forgot-password');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        _pendingEmail = email;
        notifyListeners();
      } else {
        throw Exception(json.decode(response.body)['msg'] ?? l10n.emailInconnu);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> resetPassword(String code, String newPassword) async {
    if (_pendingEmail == null) return;
    final url = Uri.parse('${ApiConfig.baseUrl}/auth/reset-password');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _pendingEmail,
          'code': code,
          'newPassword': newPassword,
        }),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        _pendingEmail = null;
        notifyListeners();
      } else {
        throw Exception(json.decode(response.body)['msg'] ?? l10n.codeInvalide2);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    _userProvider.setUserType(UserType.undefined);
    await _clearLocalData();
    if (!kIsWeb) await _googleSignIn.signOut();
    notifyListeners();
  }

  Future<void> updateFcmToken(String fcmToken) async {
    if (_currentUser == null) return;
    try {
      await http.put(
        Uri.parse('${ApiConfig.baseUrl}/users/${_currentUser!.id}/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({'fcmToken': fcmToken}),
      );
    } catch (e) {
      debugPrint("Erreur Token: $e");
    }
  }
}