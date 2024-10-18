import 'package:flutter/material.dart';
//import 'package:shooting_companion/services/api_service.dart';
import 'package:shooting_companion/screens/login_screen.dart'; // Opravený import pro LoginScreen
//import 'package:shooting_companion/screens/favorite_cartridges_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Login App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoginScreen(), // Ujistěte se, že je tu LoginScreen
    );
  }
}
