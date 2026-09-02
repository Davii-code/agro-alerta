import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../shared/theme.dart';

/// Three screens shown once, on first launch.
///
/// The app asks a producer to do something they have never done in an app -
/// count insects and trust a colour - so the vocabulary is established before
/// they are dropped into an empty dashboard. Skipping is always one tap away.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.wifi_off,
      color: AgroTheme.primary,
      title: 'Funciona sem internet',
      body: 'Conte as pragas no meio da lavoura, mesmo sem sinal. '
          'O aplicativo guarda tudo no celular e envia sozinho quando o sinal voltar.',
    ),
    _OnboardingPage(
      icon: Icons.traffic,
      color: AgroTheme.statusYellow,
      title: 'Uma cor, uma decisão',
      body: 'Verde: tudo certo, siga monitorando.\n'
          'Amarelo: fique de olho, conte de novo em poucos dias.\n'
          'Vermelho: aplicar já se paga, procure seu extensionista.',
    ),
    _OnboardingPage(
      icon: Icons.groups_outlined,
      color: AgroTheme.info,
      title: 'Você não está sozinho',
      body: 'Quando dois ou mais produtores confirmam a mesma praga por perto, '
          'todo mundo da região recebe um aviso no WhatsApp. '
          'Ninguém vê o talhão do outro.',
    ),
  ];

  Future<void> _finish() async {
    await DatabaseService().markOnboardingSeen();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Pular'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _pages[i],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? AgroTheme.primary : AgroTheme.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: ElevatedButton(
                onPressed: () {
                  if (isLast) {
                    _finish();
                  } else {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: Text(isLast ? 'COMEÇAR' : 'CONTINUAR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _OnboardingPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 66, color: color),
          ),
          const SizedBox(height: 36),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AgroTheme.textDark,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              color: AgroTheme.textGray,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
