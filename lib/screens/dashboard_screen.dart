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
  bool isRangeInitialized = false;

  @override
  void initState() {
    super.initState();
    // Načtení všech nábojů najednou
    _cartridgesFuture = ApiService.getAllCartridges();

    // Simulace načítání střelnic a nastavení `isRangeInitialized`
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        final ranges = await ApiService.getUserRanges();
        if (ranges.isNotEmpty) {
          setState(() {
            isRangeInitialized = true; // Střelnice nalezeny
          });
        } else {
          setState(() {
            isRangeInitialized = false; // Žádné střelnice nenalezeny
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nemáte žádné střelnice.')),
          );
        }
      } catch (e) {
        print('Chyba při načítání střelnic: $e');
        setState(() {
          isRangeInitialized = false; // Chyba při načítání
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chyba při načítání střelnic.')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.track_changes,
              size: 28,
              color: Colors.white,
            ),
            SizedBox(width: 8),
            Text(
              'Shooting Companion',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blueGrey,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 28, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Text(
                      widget.username,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                ),
              ],
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
                  text: 'Střelecký deník',
                  color: isRangeInitialized
                      ? const Color(0xFF2F4F4F)
                      : Colors.grey,
                  onPressed: () {
                    if (!isRangeInitialized) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Střelnice nebyly načteny. Pokračujete bez přiřazené střelnice.'),
                        ),
                      );
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
    VoidCallback? onPressed, // Povolení nullable
  }) {
    return SizedBox(
      width: 300,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed, // Akceptuje null
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
