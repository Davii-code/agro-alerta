import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../shared/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  String _selectedRole = 'producer';
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Backs the "Esqueci minha senha" link, which was previously a button with
  /// an empty onPressed - it looked functional and did nothing.
  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Digite seu e-mail acima para receber o link.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final error = await AuthService().requestPasswordReset(email);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = error;
      _successMessage =
          error == null ? 'Enviamos um link de recuperação para $email.' : null;
    });
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    // AuthService now returns an AuthResult with a Portuguese message instead of
    // throwing AuthException, so a wrong password and a dead connection can be
    // told apart and neither reaches the producer as an English SDK string.
    if (_isSignUp) {
      final result = await AuthService().signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        role: _selectedRole,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (result.isSuccess) {
          _successMessage = 'Conta criada! Agora entre com seu e-mail e senha.';
          _isSignUp = false;
          _passwordController.clear();
        } else {
          _errorMessage = result.errorMessage;
        }
      });
      return;
    }

    final result = await AuthService().signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.pushReplacementNamed(context, '/home');
      return;
    }

    setState(() {
      _isLoading = false;
      _errorMessage = result.errorMessage;
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgroTheme.lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                
                // Tractor Logo container in white rounded square
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.agriculture,
                    color: AgroTheme.primary,
                    size: 36,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Welcome Text Headers
                Text(
                  _isSignUp ? 'Criar Nova Conta' : 'Bem-vindo de volta!',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AgroTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isSignUp 
                      ? 'Preencha os dados abaixo para se cadastrar.'
                      : 'Acesse sua conta para continuar o monitoramento de sua lavoura.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AgroTheme.textGray,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AgroTheme.statusRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AgroTheme.statusRed, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: AgroTheme.statusRed, fontSize: 15, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_successMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AgroTheme.statusGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: AgroTheme.statusGreen, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _successMessage!,
                            style: const TextStyle(color: AgroTheme.statusGreen, fontSize: 15, fontWeight: FontWeight.bold, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Signup Fields (Conditional)
                if (_isSignUp) ...[
                  const Text(
                    'NOME COMPLETO',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AgroTheme.textGray, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Digite seu nome completo',
                      prefixIcon: Icon(Icons.person_outline, size: 22),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Insira seu nome completo';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  
                  const Text(
                    'TELEFONE WHATSAPP',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AgroTheme.textGray, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: '(62) 99999-9999',
                      prefixIcon: Icon(Icons.phone_outlined, size: 22),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Insira seu WhatsApp';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'TIPO DE USUÁRIO',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AgroTheme.textGray, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    items: const [
                      DropdownMenuItem(value: 'producer', child: Text('Produtor Rural')),
                      DropdownMenuItem(value: 'extensionist', child: Text('Extensionista / Técnico')),
                    ],
                    onChanged: (val) => setState(() => _selectedRole = val!),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.assignment_ind_outlined, size: 22),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                
                // Shared Fields
                const Text(
                  'E-MAIL',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AgroTheme.textGray, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'nome@exemplo.com',
                    prefixIcon: Icon(Icons.alternate_email, size: 22),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Insira seu e-mail';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 20),
                
                const Text(
                  'SENHA',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AgroTheme.textGray, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: '.........',
                    prefixIcon: const Icon(Icons.lock_outline, size: 22),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Insira sua senha';
                    }
                    // Stated up front rather than bounced back by the server.
                    if (_isSignUp && value.length < 6) {
                      return 'A senha precisa ter pelo menos 6 caracteres';
                    }
                    return null;
                  },
                ),
                
                if (!_isSignUp) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading ? null : _handleForgotPassword,
                      child: const Text(
                        'Esqueci minha senha',
                        style: TextStyle(color: AgroTheme.primaryDark, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ),
                  ),
                ],
                
                const SizedBox(height: 28),
                
                // Submit Button matching ACESSAR CONTA ->
                _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AgroTheme.primary),
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _handleSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AgroTheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_isSignUp ? 'CRIAR CONTA' : 'ACESSAR CONTA'),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                        ),
                      ),
                      
                const SizedBox(height: 16),
                
                // Toggle signin/signup
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _isSignUp = !_isSignUp;
                        _errorMessage = null;
                        _successMessage = null;
                      });
                    },
                    child: Text(
                      _isSignUp ? 'Já tem uma conta? Entrar' : 'Não tem uma conta? Cadastre-se',
                      style: const TextStyle(
                        color: AgroTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
