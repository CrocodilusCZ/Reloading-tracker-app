import 'package:flutter/material.dart';
import 'package:simple_login_app/services/api_service.dart'; // Import API služby
import 'package:simple_login_app/screens/barcode_scanner_screen.dart'; // Import BarcodeScannerScreen
import 'package:simple_login_app/screens/favorite_cartridges_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String username;

  const DashboardScreen({super.key, required this.username});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<dynamic>> _factoryCartridgesFuture;
  bool _showFactoryCartridges = false; // Přidání proměnné pro zobrazení

  @override
  void initState() {
    super.initState();
    _factoryCartridgesFuture = ApiService.getFactoryCartridges();
  }

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
                'Uživatel: ${widget.username}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          const Spacer(), // Přidání mezery mezi textem a tlačítky
          Center(
            // Centrování tlačítek
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center, // Vertikální centrování sloupce
              crossAxisAlignment:
                  CrossAxisAlignment.center, // Horizontální centrování sloupce
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const BarcodeScannerScreen(), // Spuštění obrazovky pro skenování čárových kódů
                      ),
                    );
                  },
                  child: const Text('Skenovat Čárový Kód'),
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
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showFactoryCartridges =
                          !_showFactoryCartridges; // Přepnutí zobrazení seznamu
                    });
                  },
                  child: Text(_showFactoryCartridges
                      ? 'Skrýt tovární náboje'
                      : 'Zobrazit tovární náboje'),
                ),
                const SizedBox(height: 16),
                // Zobrazení seznamu továrních nábojů, pokud je _showFactoryCartridges true
                if (_showFactoryCartridges)
                  FutureBuilder<List<dynamic>>(
                    future: _factoryCartridgesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      } else if (snapshot.hasError) {
                        return Text('Chyba při načítání: ${snapshot.error}');
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Text('Žádné tovární náboje nenalezeny.');
                      } else {
                        // Zobrazit seznam továrních nábojů
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: snapshot.data!.length,
                          itemBuilder: (context, index) {
                            final cartridge = snapshot.data![index];
                            return ListTile(
                              title: Text(cartridge['name']),
                              subtitle: Text(
                                  'Kalibr: ${cartridge['caliber']['name']}'),
                            );
                          },
                        );
                      }
                    },
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
