import 'package:flutter/foundation.dart';
import 'package:plexus/core/models/user_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProvider with ChangeNotifier {
  UserType _userType = UserType.undefined;
  bool _isLoading = true;

  UserType get userType => _userType;
  bool get isLoading => _isLoading;

  UserProvider() {
    _loadUserType();
  }

  Future<void> _loadUserType() async {
    final prefs = await SharedPreferences.getInstance();
    final userTypeIndex = prefs.getInt('userType') ?? UserType.undefined.index;
    _userType = UserType.values[userTypeIndex];
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _saveUserType(UserType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userType', type.index);
  }

  void setUserType(UserType type) {
    _userType = type;
    _saveUserType(type);
    notifyListeners();
  }
}
