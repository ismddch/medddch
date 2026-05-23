import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/fcm_service.dart';
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
  bool get isPaymentManager => _user?.isPaymentManager ?? false;
  bool get isManager => _user?.isManager ?? false;

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('saved_user_id');
    if (userId == null) return;
    try {
      final user = await _service.getUserById(userId);
      if (user != null) {
        _user = user;
        notifyListeners();
      } else {
        await prefs.remove('saved_user_id');
      }
    } catch (_) {
      await prefs.remove('saved_user_id');
    }
  }

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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_user_id', user.id);
      FcmService.onUserLoggedIn(user.id);
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
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _service.register(
        name: name,
        phone: phone,
        password: password,
      );
      _isLoading = false;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_user_id', _user!.id);
      FcmService.onUserLoggedIn(_user!.id);
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> updateProfile({String? name, String? imageUrl}) async {
    if (_user == null) return;
    await _service.updateUser(
        userId: _user!.id, name: name, imageUrl: imageUrl);
    _user = _user!.copyWith(name: name, imageUrl: imageUrl);
    notifyListeners();
  }

  Future<ShopModel> changeShopCode(String newCode) async {
    if (_user == null) throw Exception('المستخدم غير مسجل الدخول');
    final shop = await _service.changeShopCode(_user!.id, newCode);
    // After restructure: barberId on customers is no longer linked to shops.
    // We just notify listeners with the shop result for UI feedback.
    notifyListeners();
    return shop;
  }

  Future<void> removeProfileImage() async {
    if (_user == null) return;
    await _service.removeProfileImage(_user!.id);
    _user = _user!.copyWith(clearImage: true);
    notifyListeners();
  }

  void logout() {
    if (_user != null) FcmService.onUserLoggedOut(_user!.id);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.remove('saved_user_id'));
    _user = null;
    _error = null;
    notifyListeners();
  }

  Future<bool> deleteCurrentUserAccount() async {
    if (_user == null) return false;
    _isLoading = true;
    notifyListeners();
    try {
      await _service.deleteUser(_user!.id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_user_id');
      _user = null;
      _error = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'فشل حذف الحساب: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
