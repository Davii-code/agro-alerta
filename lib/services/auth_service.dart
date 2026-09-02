import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

/// Result of a sign-in / sign-up attempt.
///
/// The screens need to tell three cases apart: success, a credential problem the
/// user can fix, and a connectivity problem they cannot. Throwing [AuthException]
/// straight to the widget layer conflated the last two.
class AuthResult {
  final UserModel? user;
  final String? errorMessage;

  const AuthResult.success(this.user) : errorMessage = null;
  const AuthResult.failure(this.errorMessage) : user = null;

  bool get isSuccess => user != null;
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Supabase.instance throws when initialize() never ran, which is how the whole
  /// app distinguishes "configured backend" from "offline demo".
  bool get isSupabaseInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  UserModel? _mockUser;

  /// True when the signed-in identity is a local stub rather than a real
  /// auth.users row. Sync must refuse to push records owned by such an id,
  /// because `auth.uid() = observer_id` in the RLS policy can never match it.
  bool get isMockSession => _mockUser != null && !isSupabaseInitialized;

  UserModel? get currentUser {
    if (isSupabaseInitialized) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return _mockUser;
      return UserModel(
        id: user.id,
        email: user.email ?? '',
        phone: user.phone ?? '',
        name: user.userMetadata?['name'] ?? 'Usuário',
        role: user.userMetadata?['role'] ?? 'producer',
        createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
      );
    }
    return _mockUser;
  }

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String role,
  }) async {
    if (!isSupabaseInitialized) {
      return const AuthResult.failure(
        'O aplicativo não está conectado ao servidor. '
        'Cadastro só é possível com internet.',
      );
    }

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        // Consumed by the handle_new_user() trigger to populate public.profiles.
        data: {'name': name, 'phone': phone, 'role': role},
      );

      if (response.user == null) {
        return const AuthResult.failure(
          'Não foi possível criar a conta. Tente novamente.',
        );
      }

      return AuthResult.success(UserModel(
        id: response.user!.id,
        email: email,
        phone: phone,
        name: name,
        role: role,
        createdAt: DateTime.now(),
      ));
    } on AuthException catch (e) {
      return AuthResult.failure(_translate(e.message));
    } catch (_) {
      return const AuthResult.failure(
        'Sem conexão com o servidor. Verifique sua internet.',
      );
    }
  }

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    // Demo bypass. Debug builds only: in a release APK this branch does not
    // exist, so the fixed credentials cannot be used to get in.
    if (kDebugMode && email == 'test@agro.com' && password == '123456') {
      _mockUser = UserModel(
        id: 'mock-user-id',
        email: email,
        phone: '(62) 99999-9999',
        name: 'Davi Gonçalves (Simulado)',
        role: 'producer',
        createdAt: DateTime.now(),
      );
      return AuthResult.success(_mockUser);
    }

    if (!isSupabaseInitialized) {
      // Release builds refuse to invent an identity: a mock id breaks RLS on
      // sync and silently strands every record the producer creates.
      if (!kDebugMode) {
        return const AuthResult.failure(
          'O aplicativo não está conectado ao servidor. '
          'Entre em contato com o suporte.',
        );
      }
      _mockUser = UserModel(
        id: 'mock-user-id',
        email: email,
        phone: '(62) 99999-9999',
        name: 'Produtor (Simulado)',
        role: 'producer',
        createdAt: DateTime.now(),
      );
      return AuthResult.success(_mockUser);
    }

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        return const AuthResult.failure('E-mail ou senha incorretos.');
      }

      final profileRes = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', response.user!.id)
          .maybeSingle();

      if (profileRes != null) {
        return AuthResult.success(UserModel.fromJson(profileRes));
      }

      // Auth row exists but the profiles trigger has not landed yet.
      return AuthResult.success(UserModel(
        id: response.user!.id,
        email: response.user!.email ?? '',
        phone: '',
        name: 'Usuário',
        role: 'producer',
        createdAt: DateTime.now(),
      ));
    } on AuthException catch (e) {
      return AuthResult.failure(_translate(e.message));
    } catch (_) {
      return const AuthResult.failure(
        'Sem conexão com o servidor. Verifique sua internet.',
      );
    }
  }

  Future<void> signOut() async {
    _mockUser = null;
    if (isSupabaseInitialized) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  /// Sends the password-reset email. Backs the "Esqueci minha senha" link,
  /// which used to be a button wired to an empty callback.
  /// Returns null on success, or a message to show the user.
  Future<String?> requestPasswordReset(String email) async {
    if (!isSupabaseInitialized) {
      return 'Sem conexao com o servidor. Tente quando tiver internet.';
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      return null;
    } on AuthException catch (e) {
      return _translate(e.message);
    } catch (_) {
      return 'Nao foi possivel enviar o e-mail. Tente de novo.';
    }
  }

  /// Supabase returns English strings; producers read Portuguese.
  String _translate(String message) {
    final m = message.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'E-mail ou senha incorretos.';
    }
    if (m.contains('email not confirmed')) {
      return 'Confirme seu e-mail antes de entrar.';
    }
    if (m.contains('user already registered')) {
      return 'Este e-mail já possui cadastro.';
    }
    if (m.contains('password') && m.contains('6')) {
      return 'A senha precisa ter pelo menos 6 caracteres.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Muitas tentativas. Aguarde um minuto e tente de novo.';
    }
    return 'Não foi possível entrar. Tente novamente.';
  }
}
