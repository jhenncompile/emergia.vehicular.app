import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Provider que maneja el estado de autenticación global
class AuthProvider extends ChangeNotifier {
  final AuthService authService;

  bool _isLoading = false;
  bool _isCheckingAuth = true;
  bool _isAuthenticated = false;
  String? _errorMessage;
  String? _userEmail;
  int? _userId;
  int? _roleId;
  String? _userName;

  AuthProvider({required this.authService}) {
    _checkAuthentication();
  }

  // Getters
  bool get isLoading => _isLoading;
  bool get isCheckingAuth => _isCheckingAuth;
  bool get isAuthenticated => _isAuthenticated;
  String? get errorMessage => _errorMessage;
  String? get userEmail => _userEmail;
  int? get userId => _userId;
  int? get roleId => _roleId;
  String? get userName => _userName;

  /// Verifica si hay sesión activa al iniciar
  Future<void> _checkAuthentication() async {
    _isAuthenticated = await authService.isAuthenticated();
    _userId = await authService.getCurrentUserId();
    _roleId = await authService.getCurrentUserRoleId();
    _userName = await authService.getCurrentUserName();
    _userEmail = await authService.getCurrentUserEmail();
    _isCheckingAuth = false;
    notifyListeners();
  }

  /// Login - Conecta con el backend
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await authService.login(email: email, password: password);

      _isAuthenticated = true;
      _userEmail = email;
      _roleId = data['rol_id'] is int
          ? data['rol_id'] as int
          : int.tryParse('${data['rol_id']}');
      _userName = data['nombre']?.toString();
      final rawUserId = data['user_id'];
      if (rawUserId is int) {
        _userId = rawUserId;
      } else {
        _userId = await authService.getCurrentUserId();
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    await authService.logout();
    _isAuthenticated = false;
    _userEmail = null;
    _userId = null;
    _roleId = null;
    _userName = null;
    _errorMessage = null;
    notifyListeners();
  }
}

/// Factory para crear el Provider
