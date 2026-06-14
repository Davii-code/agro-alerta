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

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      if (_isSignUp) {
        final user = await AuthService().signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          role: _selectedRole,
        );

        if (user != null) {
          setState(() {
            _successMessage = 'Conta criada com sucesso! Você já pode entrar.';
            _isSignUp = false;
            _passwordController.clear();
          });
        } else {
          setState(() {
            _errorMessage = 'Falha ao criar conta. Tente novamente.';
          });
        }
      } else {
        final user = await AuthService().signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        if (user != null) {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/home');
          }
        } else {
          setState(() {
            _errorMessage = 'Falha ao autenticar. Verifique suas credenciais.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
                        const Icon(Icons.error_outline, color: AgroTheme.statusRed, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: AgroTheme.statusRed, fontSize: 13),
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
                        const Icon(Icons.check_circle_outline, color: AgroTheme.statusGreen, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _successMessage!,
                            style: const TextStyle(color: AgroTheme.statusGreen, fontSize: 13, fontWeight: FontWeight.bold),
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
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgroTheme.textGray, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Digite seu nome completo',
                      prefixIcon: Icon(Icons.person_outline, size: 20),
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
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgroTheme.textGray, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: '(62) 99999-9999',
                      prefixIcon: Icon(Icons.phone_outlined, size: 20),
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
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgroTheme.textGray, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    items: const [
                      DropdownMenuItem(value: 'producer', child: Text('Produtor Rural')),
                      DropdownMenuItem(value: 'extensionist', child: Text('Extensionista / Técnico')),
                    ],
                    onChanged: (val) => setState(() => _selectedRole = val!),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.assignment_ind_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                
                // Shared Fields
                const Text(
                  'E-MAIL',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgroTheme.textGray, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'nome@exemplo.com',
                    prefixIcon: Icon(Icons.alternate_email, size: 20),
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
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgroTheme.textGray, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: '.........',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
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
                    return null;
                  },
                ),
                
                if (!_isSignUp) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {},
                      child: const Text(
                        'Esqueci minha senha?',
                        style: TextStyle(color: AgroTheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
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
