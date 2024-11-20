import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:shooting_companion/screens/dashboard_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_bcrypt/flutter_bcrypt.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:async';
import 'dart:convert'; // Import pro práci s JSON

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
  final _formKey = GlobalKey<FormState>();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  String _loadingText = "Loading";
  Timer? _loadingTimer;

  bool _isLoading = false;
  String? _errorMessage;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    print("[LOGIN] Spouštím autologin...");
    if (await _isTokenValid()) {
      final tokenString = await _secureStorage.read(key: 'auth_token');
      final Map<String, dynamic> tokenData = jsonDecode(tokenString!);

      // Debug výpis načtených dat
      print("[LOGIN] Načtená data z tokenu: $tokenData");

      if (tokenData.containsKey('username')) {
        print(
            "[LOGIN] Automatické přihlášení pro uživatele: ${tokenData['username']}");
      } else {
        print("[LOGIN] Username nebyl nalezen v tokenu.");
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              DashboardScreen(username: tokenData['username']),
        ),
      );
    } else {
      print("[LOGIN] Token není platný.");
    }
  }

  Future<void> _logout() async {
    await _secureStorage.delete(key: 'auth_token');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startLoadingAnimation() {
    _loadingText = "Loading";
    _loadingTimer?.cancel(); // Zrušíme jakýkoliv předchozí časovač
    _loadingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        if (_loadingText.endsWith("...")) {
          _loadingText = "Loading";
        } else {
          _loadingText += ".";
        }
      });
    });
  }

  void _stopLoadingAnimation() {
    _loadingTimer?.cancel();
    _loadingTimer = null;
    setState(() {
      _loadingText = "Loading";
    });
  }

  Future<void> _saveToken(String username) async {
    final expirationDate =
        DateTime.now().add(const Duration(days: 30)).toIso8601String();
    final tokenData = {
      'username': username,
      'expiresAt': expirationDate,
    };

    final tokenString = jsonEncode(tokenData);
    print("[LOGIN] Ukládám token: $tokenString"); // Debug výpis
    await _secureStorage.write(key: 'auth_token', value: tokenString);
  }

  Future<void> _loadSavedCredentials() async {
    final savedUsername = await _secureStorage.read(key: 'username');
    final savedPassword =
        await _secureStorage.read(key: 'password'); // Čteš nehashované heslo

    if (savedUsername != null) {
      setState(() {
        _usernameController.text = savedUsername;
        _rememberMe = true;
      });
    }

    if (savedPassword != null) {
      setState(() {
        _passwordController.text = savedPassword; // Nastavíš nehashované heslo
      });
    }
  }

  Future<bool> _authenticateOfflineUsingHash(String savedHashedPassword) async {
    final salt = savedHashedPassword.substring(0, 29);
    final hashedAttempt = await FlutterBcrypt.hashPw(
      password: _passwordController.text,
      salt: salt,
    );

    return hashedAttempt == savedHashedPassword;
  }

  Future<bool> _authenticateOffline() async {
    final savedUsername = await _secureStorage.read(key: 'username');
    final savedPassword =
        await _secureStorage.read(key: 'password'); // Načítáš nehashované heslo

    if (savedUsername != null &&
        savedPassword != null &&
        savedUsername == _usernameController.text) {
      // Porovnáváš nehashované heslo
      return savedPassword == _passwordController.text;
    }
    return false;
  }

  Future<bool> _authenticateWithBiometrics() async {
    try {
      final bool canCheckBiometrics = await auth.canCheckBiometrics;
      final bool isDeviceSupported = await auth.isDeviceSupported();

      if (!canCheckBiometrics || !isDeviceSupported) {
        print('Zařízení nepodporuje biometrickou autentizaci.');
        return false;
      }

      final List<BiometricType> availableBiometrics =
          await auth.getAvailableBiometrics();

      final bool authenticated = await auth.authenticate(
        localizedReason: 'Ověřte se pomocí otisku prstu nebo Face ID',
        options: const AuthenticationOptions(
          biometricOnly: true,
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );

      return authenticated;
    } catch (e) {
      print('Chyba biometrické autentizace: $e');
      return false;
    }
  }

  Future<bool> _isTokenValid() async {
    print("[LOGIN] Kontroluji token...");
    final tokenString = await _secureStorage.read(key: 'auth_token');
    if (tokenString == null) {
      print("[LOGIN] Token nebyl nalezen.");
      return false;
    }

    final Map<String, dynamic> tokenData = jsonDecode(tokenString);
    final expirationDate = DateTime.parse(tokenData['expiresAt']);
    print("[LOGIN] Token načten: $tokenData");
    print("[LOGIN] Token je platný do: $expirationDate");

    return DateTime.now().isBefore(expirationDate);
  }

  Future<void> _loginWithBiometrics() async {
    try {
      // Kontrola, zda zařízení podporuje biometrickou autentizaci
      final bool canCheckBiometrics = await auth.canCheckBiometrics;
      final bool isDeviceSupported = await auth.isDeviceSupported();

      if (!canCheckBiometrics || !isDeviceSupported) {
        print('Zařízení nepodporuje biometrickou autentizaci.');
        setState(() {
          _errorMessage = 'Zařízení nepodporuje biometrickou autentizaci.';
        });
        return;
      }

      // Provádění autentizace
      final bool authenticated = await auth.authenticate(
        localizedReason: 'Ověřte se pomocí otisku prstu nebo Face ID',
        options: const AuthenticationOptions(
          biometricOnly: true, // Pouze biometrie
          useErrorDialogs: true,
          stickyAuth:
              true, // Nechává autentizaci aktivní, dokud nebude úspěšná nebo zamítnutá
        ),
      );

      if (authenticated) {
        final savedUsername = await _secureStorage.read(key: 'username');
        final savedHashedPassword =
            await _secureStorage.read(key: 'hashed_password');

        if (savedUsername != null && savedHashedPassword != null) {
          print(
              'Uložené přihlašovací údaje: $savedUsername, $savedHashedPassword');
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DashboardScreen(username: savedUsername),
            ),
          );
        } else {
          print('Chybí uložené přihlašovací údaje');
          setState(() {
            _errorMessage = 'Chybí uložené přihlašovací údaje.';
          });
        }
      } else {
        print('Autentizace biometricky selhala');
        setState(() {
          _errorMessage = 'Autentizace biometricky selhala.';
        });
      }
    } catch (e) {
      print('Chyba biometrické autentizace: $e');
      setState(() {
        _errorMessage = 'Chyba při pokusu o autentizaci.';
      });
    }
  }

  Future<void> _loginWithPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _startLoadingAnimation();

    try {
      if (await _isDeviceOnline()) {
        // Volání API pro přihlášení
        final result = await ApiService.login(
          _usernameController.text,
          _passwordController.text,
        );

        print('API Login Response: $result');

        if (result.containsKey('token') && result.containsKey('name')) {
          TextInput.finishAutofillContext(shouldSave: true);

          if (_rememberMe) {
            print('Ukládám username do tokenu: ${result['name']}');
            await _saveToken(result['name']);
          }

          if (!mounted) return;

          print(
              'Přesměrovávám na DashboardScreen s username: ${result['name']}');

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DashboardScreen(username: result['name']),
            ),
          );
        } else {
          print('Login selhalo: ${result['message']}');
          setState(() {
            _errorMessage = result['message'] ?? 'Přihlášení selhalo.';
          });
        }
      } else {
        if (await _authenticateOffline()) {
          final savedToken = await _secureStorage.read(key: 'auth_token');
          final savedData = jsonDecode(savedToken!);

          print(
              'Offline autentizace úspěšná. Přesměrovávám s username: ${savedData['username']}');

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  DashboardScreen(username: savedData['username']),
            ),
          );
        } else {
          print('Offline autentizace selhala.');
          setState(() {
            _errorMessage =
                'Offline přihlášení selhalo. Zkontrolujte uložené údaje.';
          });
        }
      }
    } catch (error) {
      print('Došlo k chybě během přihlášení: $error');
      setState(() {
        _errorMessage = 'Došlo k chybě. Zkuste to znovu.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _stopLoadingAnimation();
    }
  }

  Future<void> _saveCredentials() async {
    if (_rememberMe) {
      await _secureStorage.write(
        key: 'username',
        value: _usernameController.text,
      );
      // Uložit nehashované heslo (nehashuješ ho)
      await _secureStorage.write(
        key: 'password',
        value: _passwordController.text, // Ukládáš nehashované heslo
      );
    }
  }

  Future<void> _clearCredentials() async {
    await _secureStorage.delete(key: 'username');
    await _secureStorage.delete(key: 'hashed_password');
  }

  Future<bool> _authenticateOfflineWithStorage() async {
    final savedUsername = await _secureStorage.read(key: 'username');
    final savedHashedPassword =
        await _secureStorage.read(key: 'hashed_password');

    if (savedUsername != null &&
        savedHashedPassword != null &&
        savedUsername == _usernameController.text) {
      final salt = savedHashedPassword.substring(0, 29);
      final hashedAttempt = await FlutterBcrypt.hashPw(
        password: _passwordController.text,
        salt: salt,
      );

      return hashedAttempt == savedHashedPassword;
    }
    return false;
  }

  Future<bool> _isDeviceOnline() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
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
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Shooting Companion',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Manage Your Reloads and Shooting Activities',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _usernameController,
                      focusNode: _usernameFocusNode,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email
                      ],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) {
                        _usernameFocusNode.unfocus();
                        FocusScope.of(context).requestFocus(_passwordFocusNode);
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Prosím zadejte email';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        labelText: 'E-mail',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey[200],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      autofillHints: const [AutofillHints.password],
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        _passwordFocusNode.unfocus();
                        _loginWithPassword();
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Prosím zadejte heslo';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey[200],
                      ),
                    ),
                    const SizedBox(height: 16),
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
                    ElevatedButton(
                      onPressed: _isLoading ? null : _loginWithPassword,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? Center(
                              child: Text(
                                _loadingText,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            )
                          : const Text('Login with Password'),
                    ),
                    const SizedBox(height: 10),
                    if (_errorMessage != null)
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
