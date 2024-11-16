import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:shooting_companion/screens/dashboard_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_bcrypt/flutter_bcrypt.dart';
import 'package:local_auth/local_auth.dart';

final _secureStorage = FlutterSecureStorage();

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final LocalAuthentication auth = LocalAuthentication();

  bool _isLoading = false;
  String? _errorMessage;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final savedUsername = await _secureStorage.read(key: 'username');

    print('Loaded saved username: $savedUsername');

    if (savedUsername != null) {
      setState(() {
        _usernameController.text = savedUsername;
        _rememberMe = true;
      });
    }
  }

  //Metoda pro kontrolu hashe
  Future<bool> _authenticateOfflineUsingHash(String savedHashedPassword) async {
    final salt = savedHashedPassword.substring(0, 29);
    final hashedAttempt = await FlutterBcrypt.hashPw(
      password: _passwordController.text,
      salt: salt,
    );

    return hashedAttempt == savedHashedPassword;
  }

  //Metoda pro biometrickou autentizaci
  Future<bool> _authenticateWithBiometrics() async {
    try {
      final bool canCheckBiometrics = await auth.canCheckBiometrics;
      final bool isDeviceSupported = await auth.isDeviceSupported();

      print(
          'Biometrická podpora: $canCheckBiometrics, Podpora zařízení: $isDeviceSupported');

      if (!canCheckBiometrics || !isDeviceSupported) {
        print('Zařízení nepodporuje biometrickou autentizaci.');
        return false;
      }

      final List<BiometricType> availableBiometrics =
          await auth.getAvailableBiometrics();
      print('Dostupné biometrické metody: $availableBiometrics');

      final bool authenticated = await auth.authenticate(
        localizedReason: 'Ověřte se pomocí otisku prstu nebo Face ID',
        options: const AuthenticationOptions(
          biometricOnly: true,
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );

      print('Výsledek autentizace: $authenticated');
      return authenticated;
    } catch (e) {
      print('Chyba biometrické autentizace: $e');
      return false;
    }
  }

  Future<void> _loginWithBiometrics() async {
    final authenticated = await _authenticateWithBiometrics();
    if (authenticated) {
      print('Biometrická autentizace úspěšná.');

      // Načtení uložených přihlašovacích údajů
      final savedUsername = await _secureStorage.read(key: 'username');
      final savedHashedPassword =
          await _secureStorage.read(key: 'hashed_password');

      if (savedUsername != null && savedHashedPassword != null) {
        // Přímo ověření uloženého hashe bez nutnosti hesla
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DashboardScreen(username: savedUsername),
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'Chybí uložené přihlašovací údaje.';
        });
      }
    } else {
      setState(() {
        _errorMessage = 'Biometrická autentizace selhala.';
      });
    }
  }

  Future<void> _loginWithPassword() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (await _isDeviceOnline()) {
        final result = await ApiService.login(
          _usernameController.text,
          _passwordController.text,
        );

        if (result.containsKey('token') && result.containsKey('name')) {
          if (_rememberMe) {
            await _saveCredentials();
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DashboardScreen(username: result['name']),
            ),
          );
        } else {
          setState(() {
            _errorMessage = result['message'] ?? 'Přihlášení selhalo.';
          });
        }
      } else {
        if (await _authenticateOffline()) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  DashboardScreen(username: _usernameController.text),
            ),
          );
        } else {
          setState(() {
            _errorMessage =
                'Offline přihlášení selhalo. Zkontrolujte uložené údaje.';
          });
        }
      }
    } catch (error) {
      setState(() {
        _errorMessage = 'Došlo k chybě. Zkuste to znovu.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Uložení přihlašovacích údajů do Secure Storage
  Future<void> _saveCredentials() async {
    if (_rememberMe) {
      await _secureStorage.write(
        key: 'username',
        value: _usernameController.text,
      );

      // Uložení hashovaného hesla pro offline autentizaci
      final salt = await FlutterBcrypt.salt();
      final hashedPassword = await FlutterBcrypt.hashPw(
        password: _passwordController.text,
        salt: salt,
      );

      await _secureStorage.write(key: 'hashed_password', value: hashedPassword);
    }
  }

  /// Vymazání uložených přihlašovacích údajů
  Future<void> _clearCredentials() async {
    await _secureStorage.delete(key: 'username');
    await _secureStorage.delete(key: 'hashed_password');
  }

  /// Offline ověření uživatele
  Future<bool> _authenticateOffline() async {
    final savedUsername = await _secureStorage.read(key: 'username');
    final savedHashedPassword =
        await _secureStorage.read(key: 'hashed_password');

    print('Offline authentication:');
    print('Stored username: $savedUsername');
    print('Stored hashed password: $savedHashedPassword');
    print('Input username: ${_usernameController.text}');
    print('Input password: ${_passwordController.text}');

    if (savedUsername != null &&
        savedHashedPassword != null &&
        savedUsername == _usernameController.text) {
      final salt = savedHashedPassword.substring(0, 29);
      final hashedAttempt = await FlutterBcrypt.hashPw(
        password: _passwordController.text,
        salt: salt,
      );

      print('Generated hash for input password: $hashedAttempt');
      return hashedAttempt == savedHashedPassword;
    }
    return false;
  }

  /// Zjištění dostupnosti internetu
  Future<bool> _isDeviceOnline() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      print('Device is online.');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      print('Device is offline.');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Shooting Companion',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage Your Reloads and Shooting Activities',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Pole pro uživatelské jméno
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'E-mail',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                ),
                const SizedBox(height: 16),
                // Pole pro heslo
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                // "Remember Me" checkbox
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: (bool? value) {
                        setState(() {
                          _rememberMe = value ?? false;
                        });
                      },
                    ),
                    const Text('Remember me'),
                  ],
                ),
                const SizedBox(height: 20),
                // Tlačítko pro biometrické přihlášení
                if (_rememberMe)
                  ElevatedButton.icon(
                    onPressed: _loginWithBiometrics,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Login with Biometrics'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                const SizedBox(height: 20),
                // Tlačítko pro přihlášení heslem
                ElevatedButton(
                  onPressed: _loginWithPassword,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Login with Password'),
                ),
                const SizedBox(height: 10),
                // Zobrazení chybové zprávy
                if (_errorMessage != null)
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
