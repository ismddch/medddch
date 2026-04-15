import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseService _service = SupabaseService();

  UserModel? _user;
  bool _isLoading = false;
  String? _error;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;
  bool get isBarber => _user?.isBarber ?? false;
  bool get isAdmin => _user?.isAdmin ?? false;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<bool> login(String phone, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _service.login(phone, password);
      if (user == null) {
        _error = 'رقم الهاتف أو كلمة المرور غير صحيحة';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      _user = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'خطأ في تسجيل الدخول: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String phone,
    required String password,
    required String barberCode,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _service.register(
        name: name,
        phone: phone,
        password: password,
        barberCode: barberCode,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void logout() {
    _user = null;
    _error = null;
    notifyListeners();
  }
}
