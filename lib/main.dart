import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/database_service.dart';
import 'services/sync_service.dart';
import 'services/mip_service.dart';
import 'shared/theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/new_sampling_screen.dart';
import 'screens/radar_screen.dart';
import 'screens/history_screen.dart';
import 'screens/onboarding_screen.dart';

// Credentials are injected at build time and never committed:
//   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
// See README.md. With no values the app boots in offline demo mode.
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive first: every write in the app lands here before it ever touches the
  // network, so storage must be ready even if everything else fails.
  await DatabaseService().init();

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      debugPrint('Supabase: conectado.');
    } catch (e) {
      debugPrint('Supabase: falha ao inicializar ($e). Seguindo offline.');
    }
  } else {
    debugPrint('Supabase: sem credenciais de build. Modo offline.');
  }

  // Refresh the MIP economics cache once at boot; it falls back to the last
  // cached copy, then to bundled constants, so it never blocks startup.
  await MipService().refresh();

  SyncService().start();

  final seenOnboarding = DatabaseService().hasSeenOnboarding();

  runApp(AgroAlertaApp(seenOnboarding: seenOnboarding));
}

class AgroAlertaApp extends StatelessWidget {
  final bool seenOnboarding;

  const AgroAlertaApp({super.key, this.seenOnboarding = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agro Alerta GO',
      theme: AgroTheme.themeData,
      debugShowCheckedModeBanner: false,
      initialRoute: seenOnboarding ? '/login' : '/onboarding',
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/new-sampling': (context) => const NewSamplingScreen(),
        '/radar': (context) => const RadarScreen(),
        '/history': (context) => const HistoryScreen(),
      },
    );
  }
}
