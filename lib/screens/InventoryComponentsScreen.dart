import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';

class InventoryComponentsScreen extends StatefulWidget {
  const InventoryComponentsScreen({super.key});

  @override
  _InventoryComponentsScreenState createState() =>
      _InventoryComponentsScreenState();
}

class _InventoryComponentsScreenState extends State<InventoryComponentsScreen> {
  late Future<Map<String, List<Map<String, dynamic>>>>
      _inventoryComponentsFuture;

  @override
  void initState() {
    super.initState();
    // Načítání komponent z API
    _inventoryComponentsFuture = ApiService.getInventoryComponents();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Přehled komponent'),
        backgroundColor: Colors.blueGrey,
      ),
      body: FutureBuilder(
        future: _inventoryComponentsFuture,
        builder: (context,
            AsyncSnapshot<Map<String, List<Map<String, dynamic>>>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Chyba: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            print('Inventory components response: ${snapshot.data}');
            return const Center(child: Text('Žádné komponenty nenalezeny.'));
          } else {
            return ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildSection('Střely', snapshot.data!['bullets']!),
                const SizedBox(height: 16),
                _buildSection('Prachy', snapshot.data!['powders']!),
                const SizedBox(height: 16),
                _buildSection('Zápalky', snapshot.data!['primers']!),
                const SizedBox(height: 16),
                _buildSection('Nábojnice', snapshot.data!['brasses']!),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> items) {
    return ExpansionTile(
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      children: items.map((item) {
        String subtitleText = 'Skladem: ${item['stock_quantity']}';

        // Pokud se jedná o nábojnice (brasses), zobraz kalibr, pokud existuje
        if (title == 'Nábojnice') {
          final caliber = item['caliber']; // Získání objektu kalibru
          // Logování objektu caliber pro ladění
          print('Caliber data for brass ${item['name']}: $caliber');

          if (caliber != null && caliber['name'] != null) {
            subtitleText =
                'Kalibr: ${caliber['name']} | Skladem: ${item['stock_quantity']}';
          } else {
            subtitleText =
                'Kalibr: Neznámý | Skladem: ${item['stock_quantity']}';
          }
        }

        return ListTile(
          title: Text(item['name'] ?? 'Neznámý'),
          subtitle: Text(subtitleText),
          trailing: Text('Cena: ${item['price'] ?? 'N/A'}'),
        );
      }).toList(),
    );
  }
}
