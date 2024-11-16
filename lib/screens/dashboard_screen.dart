import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:shooting_companion/screens/barcode_scanner_screen.dart';
import 'package:shooting_companion/screens/favorite_cartridges_screen.dart';
import 'package:shooting_companion/screens/shooting_log_screen.dart';
import 'package:shooting_companion/screens/inventory_components_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String username; // Přidání parametru username

  const DashboardScreen(
      {super.key, required this.username}); // Konstruktor s username

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late String username;
  bool isRangeInitialized = false;
  late Future<Map<String, List<Map<String, dynamic>>>> _cartridgesFuture;

  @override
  void initState() {
    super.initState();
    username = widget.username; // Přiřazení username z widgetu
    _initializeDashboard();
  }

  Future<void> _initializeDashboard() async {
    _cartridgesFuture = ApiService.getAllCartridges();
    await _loadRanges();
  }

  Future<void> _loadRanges() async {
    try {
      final ranges = await ApiService.getUserRanges();
      setState(() {
        isRangeInitialized = ranges.isNotEmpty;
      });
      if (!isRangeInitialized) {
        _showSnackBar('Nemáte žádné střelnice.');
      }
    } catch (e) {
      _showSnackBar('Chyba při načítání střelnic.');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Shooting Companion - Vítejte, $username'),
        centerTitle: true,
        backgroundColor: Colors.blueGrey,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildButton(
            icon: Icons.book,
            text: 'Střelecký deník',
            color: isRangeInitialized ? Colors.teal : Colors.grey,
            onPressed: () {
              if (!isRangeInitialized) {
                _showSnackBar(
                    'Střelnice nebyly načteny. Pokračujete bez přiřazené střelnice.');
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ShootingLogScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildButton(
            icon: Icons.qr_code_scanner,
            text: 'Sklad',
            color: Colors.blueAccent,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BarcodeScannerScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildButton(
            icon: Icons.inventory_2,
            text: 'Inventář nábojů',
            color: Colors.grey.shade700,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FutureBuilder(
                    future: _cartridgesFuture,
                    builder: (context,
                        AsyncSnapshot<Map<String, List<Map<String, dynamic>>>>
                            snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      } else if (snapshot.hasError) {
                        return Center(
                          child: Text('Chyba: ${snapshot.error}'),
                        );
                      } else if (!snapshot.hasData ||
                          snapshot.data!['factory']!.isEmpty &&
                              snapshot.data!['reload']!.isEmpty) {
                        return const Center(
                          child: Text('Žádné náboje nenalezeny.'),
                        );
                      } else {
                        return FavoriteCartridgesScreen(
                          factoryCartridges: snapshot.data!['factory']!,
                          reloadCartridges: snapshot.data!['reload']!,
                        );
                      }
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildButton(
            icon: Icons.visibility,
            text: 'Stav skladu komponent',
            color: Colors.blueGrey,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const InventoryComponentsScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.person, size: 28, color: Colors.blueGrey),
            const SizedBox(width: 8),
            Text(
              username,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Verze aplikace: Shooting_companion_0.9',
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String text,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
