import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  bool get _isSupabaseInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  UserModel? _mockUser;

  UserModel? get currentUser {
    if (_isSupabaseInitialized) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;
      return UserModel(
        id: user.id,
        email: user.email ?? '',
        phone: user.phone ?? '',
        name: user.userMetadata?['name'] ?? 'Usuário',
        role: user.userMetadata?['role'] ?? 'producer',
        createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
      );
    } else {
      return _mockUser;
    }
  }

  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String role,
  }) async {
    if (_isSupabaseInitialized) {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {
          'name': name,
          'phone': phone,
          'role': role,
        },
      );
      if (response.user != null) {
        return UserModel(
          id: response.user!.id,
          email: email,
          phone: phone,
          name: name,
          role: role,
          createdAt: DateTime.now(),
        );
      }
      return null;
    } else {
      _mockUser = UserModel(
        id: 'mock-user-id',
        email: email,
        phone: phone,
        name: name,
        role: role,
        createdAt: DateTime.now(),
      );
      return _mockUser;
    }
  }

  Future<UserModel?> signIn({
    required String email,
    required String password,
  }) async {
    // Check for demo bypass credentials
    if (email == 'test@agro.com' && password == '123456') {
      _mockUser = UserModel(
        id: 'mock-user-id',
        email: email,
        phone: '(62) 99999-9999',
        name: 'Davi Gonçalves (Simulado)',
        role: 'producer',
        createdAt: DateTime.now(),
      );
      return _mockUser;
    }

    if (_isSupabaseInitialized) {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user != null) {
        final profileRes = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', response.user!.id)
            .maybeSingle();
        if (profileRes != null) {
          return UserModel.fromJson(profileRes);
        }
        return UserModel(
          id: response.user!.id,
          email: response.user!.email ?? '',
          phone: '',
          name: 'Usuário',
          role: 'producer',
          createdAt: DateTime.now(),
        );
      }
      return null;
    } else {
      // Allow testing without live credentials
      _mockUser = UserModel(
        id: 'mock-user-id',
        email: email,
        phone: '(62) 99999-9999',
        name: 'Davi Gonçalves',
        role: 'producer',
        createdAt: DateTime.now(),
      );
      return _mockUser;
    }
  }

  Future<void> signOut() async {
    if (_isSupabaseInitialized) {
      await Supabase.instance.client.auth.signOut();
    } else {
      _mockUser = null;
    }
  }
}
