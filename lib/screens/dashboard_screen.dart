import 'package:flutter/material.dart';
import 'package:simple_login_app/screens/qr_scan_screen.dart';  // Import QRScanScreen
import 'package:simple_login_app/screens/favorite_cartridges_screen.dart';

class DashboardScreen extends StatelessWidget {
  final String username;

  const DashboardScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Domovská Stránka'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Align(
              alignment: Alignment.topLeft, // Zarovnání textu nahoře vlevo
              child: Text(
                'Uživatel: $username',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          const Spacer(), // Přidání mezery mezi textem a tlačítky
          Center( // Centrování tlačítek
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, // Vertikální centrování sloupce
              crossAxisAlignment: CrossAxisAlignment.center, // Horizontální centrování sloupce
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const QRScanScreen(),  // Spuštění obrazovky pro skenování QR
                      ),
                    );
                  },
                  child: const Text('QR'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FavoriteCartridgesScreen(),
                      ),
                    );
                  },
                  child: const Text('Inventář'),
                ),
              ],
            ),
          ),
          const Spacer(), // Přidání mezery mezi tlačítky a spodní částí obrazovky
        ],
      ),
    );
  }
}
