import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:plexus/core/models/user_type.dart';
import 'package:plexus/core/providers/user_provider.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:plexus/core/api_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  ChatUser? _currentUser;
  bool _isApproved = false;
  late UserProvider _userProvider;
  String? _pendingEmail; 

  String? _myReferralCode;
  double _referralEarnings = 0.0;
  double _referralSavings = 0.0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  String? get token => _token;
  ChatUser? get currentUser => _currentUser;
  bool get isAuthenticated => _token != null;
  bool get isApproved => _isApproved;
  String? get pendingEmail => _pendingEmail;
  String? get myReferralCode => _myReferralCode;
  double get referralEarnings => _referralEarnings;
  double get referralSavings => _referralSavings;

  AuthProvider();

  void updateUserProvider(UserProvider userProvider) {
    _userProvider = userProvider;
  }

  void updateLocalUserData(Map<String, dynamic> userData) {
    if (_currentUser == null) return;
    _currentUser = ChatUser(
      id: userData['id']?.toString() ?? _currentUser!.id,
      firstName: userData['name'] ?? _currentUser!.firstName,
      profileImage: userData['profileImage'] ?? _currentUser!.profileImage,
    );
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/auth/login');
    try {
      final response = await http.post(
        url, 
        headers: {'Content-Type': 'application/json'}, 
        body: json.encode({'email': email, 'password': password})
      ).timeout(const Duration(seconds: 30)); // AUGMENTÉ À 30S

      if (response.statusCode == 200) {
        await _handleAuthResponse(json.decode(response.body));
      } else {
        throw Exception(json.decode(response.body)['msg'] ?? 'Identifiants incorrects');
      }
    } catch (e) { 
      throw Exception(ApiConfig.handleNetworkError(e));
    }
  }

  Future<void> signInWithGoogle({String? referralCode, String? role}) async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? firebaseUser = userCredential.user;

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
        ).timeout(const Duration(seconds: 30)); // AUGMENTÉ À 30S

        if (response.statusCode == 200) {
          await _handleAuthResponse(json.decode(response.body));
        } else {
          throw Exception('Le serveur PLEXUS a rejeté la connexion Google');
        }
      }
    } catch (e) {
      throw Exception("Erreur Google : ${e.toString()}");
    }
  }

  Future<void> _handleAuthResponse(Map<String, dynamic> responseData) async {
    _token = responseData['token'] ?? _token;
    final user = responseData['user'];
    if (user != null) {
      final String userId = (user['_id'] ?? user['id']).toString();
      _currentUser = ChatUser(id: userId, firstName: user['name'], profileImage: user['profileImage']);
      _isApproved = user['isApproved'] ?? false;
      _myReferralCode = user['referralCode'];
      _referralEarnings = (user['totalReferralEarnings'] ?? 0.0).toDouble();
      _referralSavings = (user['totalReferralSavings'] ?? 0.0).toDouble();
      if (user['role'] != null) {
        _userProvider.setUserType(user['role'] == 'seller' ? UserType.seller : UserType.client);
      }
    }
    notifyListeners();
  }

  Future<void> signUp(String name, String email, String password, String role, {String? phone, String? address, File? idFront, File? idBack, File? selfie, String? referralCode}) async {
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
        if (idFront != null) request.files.add(await http.MultipartFile.fromPath('idFront', idFront.path));
        if (idBack != null) request.files.add(await http.MultipartFile.fromPath('idBack', idBack.path));
        if (selfie != null) request.files.add(await http.MultipartFile.fromPath('selfie', selfie.path));
      }
      var streamedResponse = await request.send().timeout(const Duration(seconds: 45)); // TEMPS SUPPLÉMENTAIRE POUR LES IMAGES
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 201) {
        _pendingEmail = email; 
        notifyListeners();
      } else {
        throw Exception(json.decode(response.body)['msg'] ?? 'Erreur d\'inscription');
      }
    } catch (e) { rethrow; }
  }

  Future<void> logout() async {
    _token = null; _currentUser = null;
    await _googleSignIn.signOut();
    notifyListeners();
  }
}
