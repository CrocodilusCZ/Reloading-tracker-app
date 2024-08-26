import 'package:flutter/material.dart';
//import 'package:simple_login_app/services/api_service.dart';
import 'package:simple_login_app/screens/login_screen.dart'; // Opravený import pro LoginScreen
//import 'package:simple_login_app/screens/favorite_cartridges_screen.dart'; 

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
