import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/database_service.dart';
import 'services/sync_service.dart';
import 'shared/theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/new_sampling_screen.dart';
import 'screens/radar_screen.dart';

// Environment variables can be injected at build time, e.g.:
// --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://lavidarlbbixpktbdybl.supabase.co');
const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxhdmlkYXJsYmJpeHBrdGJkeWJsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg1OTI3MjgsImV4cCI6MjA5NDE2ODcyOH0.-Gd0C4hwJyhVrPX8lc9RenUe1Um7u4YtOb7cym2lipA');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Database Service (Hive storage for offline-first)
  try {
    await DatabaseService().init();
    print("Database Service: Hive initialized successfully.");
  } catch (e) {
    print("Database Service: Failed to initialize Hive: $e");
  }

  // Optional: Initialize Supabase connection
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      print("Supabase: Connected successfully.");
    } catch (e) {
      print("Supabase: Initialization failed: $e");
    }
  } else {
    print("Supabase: Running in Offline Simulation Mode (No URL/Key provided).");
  }

  // Start Background Sync Service
  SyncService().startPeriodicSync();

  runApp(const AgroAlertaApp());
}

class AgroAlertaApp extends StatelessWidget {
  const AgroAlertaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroAlerta',
      theme: AgroTheme.themeData,
      debugShowCheckedModeBanner: false,
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/new-sampling': (context) => const NewSamplingScreen(),
        '/radar': (context) => const RadarScreen(),
      },
    );
  }
}
