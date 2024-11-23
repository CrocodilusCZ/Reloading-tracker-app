import 'package:flutter/material.dart';
import 'package:shooting_companion/screens/dashboard_screen.dart';
import 'package:shooting_companion/screens/login_screen.dart';

// Globální klíč pro ScaffoldMessenger
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() {
  runApp(const ShootingCompanionApp());
}

class ShootingCompanionApp extends StatelessWidget {
  const ShootingCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey, // Připojení klíče
      title: 'Shooting Companion', // Změněný název aplikace
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/login', // Nastavení výchozí trasy
      routes: {
        '/login': (context) => const LoginScreen(), // Přihlašovací obrazovka
        '/dashboard': (context) =>
            DashboardScreen(username: 'User'), // Příklad další trasy
      },
    );
  }
}
