import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/add_screen.dart';
import 'screens/settings_screen.dart';
import 'services/storage_service.dart';
import 'providers/master_password_provider.dart';
import 'models/credential.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Redirect to Settings on first launch if not yet configured
  final isConfigured = await StorageService.isConfigured();

  runApp(PasswordManagerApp(isConfigured: isConfigured));
}

class PasswordManagerApp extends StatelessWidget {
  final bool isConfigured;

  const PasswordManagerApp({super.key, required this.isConfigured});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: isConfigured ? '/' : '/settings',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/add',
          builder: (context, state) => AddScreen(
            credential: state.extra as Credential?,
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );

    return ChangeNotifierProvider(
      // MasterPasswordProvider auto-clears when app goes to background
      create: (_) => MasterPasswordProvider(),
      child: MaterialApp.router(
        title: 'Password Manager',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        routerConfig: router,
      ),
    );
  }
}
