import 'package:flutter/material.dart';
import 'package:shooting_companion/screens/dashboard_screen.dart';
import 'package:shooting_companion/screens/login_screen.dart';

void main() {
  runApp(const ShootingCompanionApp());
}

class ShootingCompanionApp extends StatelessWidget {
  const ShootingCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
