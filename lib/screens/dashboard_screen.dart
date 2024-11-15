import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:shooting_companion/screens/barcode_scanner_screen.dart';
import 'package:shooting_companion/screens/favorite_cartridges_screen.dart';
import 'package:shooting_companion/screens/shooting_log_screen.dart';
import 'package:shooting_companion/screens/inventory_components_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String username;

  const DashboardScreen({super.key, required this.username});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, List<Map<String, dynamic>>>> _cartridgesFuture;
  bool _showFactoryCartridges = false;

  @override
  void initState() {
    super.initState();
    // Načtení všech nábojů najednou
    _cartridgesFuture = ApiService.getAllCartridges();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shooting Companion'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Align(
              alignment: Alignment.topLeft,
              child: Column(
                // Přidán Column widget pro zarovnání dvou textů vertikálně
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uživatel: ${widget.username}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Verze aplikace: Shooting_companion_0.9',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildButton(
                  icon: Icons.book,
                  text: 'Sken & spotřeba',
                  color: const Color(0xFF2F4F4F),
                  onPressed: () {
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
                  text: 'Sken & Navýšení skladu',
                  color: const Color(0xFF4682B4),
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
                  color: const Color(0xFF696969),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FutureBuilder(
                          future: ApiService.getAllCartridges(),
                          builder: (context,
                              AsyncSnapshot<
                                      Map<String, List<Map<String, dynamic>>>>
                                  snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            } else if (snapshot.hasError) {
                              return Center(
                                  child: Text('Chyba: ${snapshot.error}'));
                            } else if (!snapshot.hasData) {
                              return const Center(
                                  child: Text('Žádné náboje nenalezeny.'));
                            } else {
                              List<Map<String, dynamic>> factoryCartridges =
                                  snapshot.data!['factory']!;
                              List<Map<String, dynamic>> reloadCartridges =
                                  snapshot.data!['reload']!;
                              return FavoriteCartridgesScreen(
                                factoryCartridges: factoryCartridges,
                                reloadCartridges: reloadCartridges,
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
                  color: const Color(0xFF708090),
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
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String text,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 300,
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
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 24,
              color: Colors.white,
            ),
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
