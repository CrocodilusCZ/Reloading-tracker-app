import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart'; // Zajistěte, že máte správnou cestu k vaší API službě

class InventoryComponentsScreen extends StatelessWidget {
  const InventoryComponentsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Přehled Skladových Zásob Komponent'),
        backgroundColor: Colors.blueGrey,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: ApiService
            .getInventoryComponents(), // Volání API pro získání komponent
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Chyba: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return const Center(
                child: Text('Žádné skladové zásoby nebyly nalezeny.'));
          }

          final data = snapshot.data!;
          final List<Map<String, dynamic>> bullets =
              List<Map<String, dynamic>>.from(data['bullets']);
          final List<Map<String, dynamic>> powders =
              List<Map<String, dynamic>>.from(data['powders']);
          final List<Map<String, dynamic>> primers =
              List<Map<String, dynamic>>.from(data['primers']);
          final List<Map<String, dynamic>> brasses =
              List<Map<String, dynamic>>.from(data['brasses']);

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildComponentSection(
                      'Střely', bullets, 'bullets'), // Pro sekci střel
                  const SizedBox(height: 20),
                  _buildComponentSection(
                      'Prachy', powders, 'powders'), // Pro sekci prachů
                  const SizedBox(height: 20),
                  _buildComponentSection(
                      'Zápalky', primers, 'primers'), // Pro sekci zápalek
                  const SizedBox(height: 20),
                  _buildComponentSection(
                      'Nábojnice', brasses, 'brasses'), // Pro sekci nábojnic
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildComponentSection(
      String title, List<Map<String, dynamic>> components, String type) {
    List<DataColumn> columns;
    List<DataRow> rows;

    switch (type) {
      case 'bullets':
        columns = const [
          DataColumn(label: Text('Název')),
          DataColumn(label: Text('Váha (grains)')),
          DataColumn(label: Text('Výrobce')),
          DataColumn(label: Text('Průměr (inches)')),
          DataColumn(label: Text('Cena (Kč)')),
          DataColumn(label: Text('Skladová Zásoba (ks)')),
        ];

        rows = List.generate(
          components.length,
          (index) => DataRow.byIndex(
            index: index,
            color: MaterialStateProperty.resolveWith<Color?>(
              (Set<MaterialState> states) {
                // Střídání barev pro zebra efekt
                return index % 2 == 0 ? Colors.grey[200] : null;
              },
            ),
            cells: [
              DataCell(Text(components[index]['name'] ?? 'Neznámý')),
              DataCell(Text(
                  components[index]['weight_grains']?.toString() ?? 'Neznámá')),
              DataCell(Text(components[index]['manufacturer'] ?? 'Neznámý')),
              DataCell(Text(components[index]['diameter_inches']?.toString() ??
                  'Neznámá')),
              DataCell(
                  Text(components[index]['price']?.toString() ?? 'Neznámá')),
              DataCell(Text(components[index]['stock_quantity']?.toString() ??
                  'Neznámá')),
            ],
          ),
        );
        break;

      case 'powders':
        columns = const [
          DataColumn(label: Text('Výrobce')),
          DataColumn(label: Text('Název')),
          DataColumn(label: Text('Skladem gramů')),
        ];

        rows = List.generate(
          components.length,
          (index) => DataRow.byIndex(
            index: index,
            color: MaterialStateProperty.resolveWith<Color?>(
              (Set<MaterialState> states) {
                // Střídání barev pro zebra efekt
                return index % 2 == 0 ? Colors.grey[200] : null;
              },
            ),
            cells: [
              DataCell(Text(components[index]['manufacturer'] ?? 'Neznámý')),
              DataCell(Text(components[index]['name'] ?? 'Neznámý')),
              DataCell(Text(components[index]['stock_quantity']?.toString() ??
                  'Neznámá')),
            ],
          ),
        );
        break;

      case 'primers':
        columns = const [
          DataColumn(label: Text('Kategorie')),
          DataColumn(label: Text('Název')),
          DataColumn(label: Text('Cena (Kč)')),
          DataColumn(label: Text('Skladová Zásoba (ks)')),
        ];

        rows = List.generate(
          components.length,
          (index) => DataRow.byIndex(
            index: index,
            color: MaterialStateProperty.resolveWith<Color?>(
              (Set<MaterialState> states) {
                // Střídání barev pro zebra efekt
                return index % 2 == 0 ? Colors.grey[200] : null;
              },
            ),
            cells: [
              DataCell(Text(components[index]['categories'] ?? 'Neznámá')),
              DataCell(Text(components[index]['name'] ?? 'Neznámý')),
              DataCell(
                  Text(components[index]['price']?.toString() ?? 'Neznámá')),
              DataCell(Text(components[index]['stock_quantity']?.toString() ??
                  'Neznámá')),
            ],
          ),
        );
        break;

      case 'brasses':
        columns = const [
          DataColumn(label: Text('Kalibr')),
          DataColumn(label: Text('Název')),
          DataColumn(label: Text('Skladová Zásoba (ks)')),
        ];

        rows = List.generate(
          components.length,
          (index) => DataRow.byIndex(
            index: index,
            color: MaterialStateProperty.resolveWith<Color?>(
              (Set<MaterialState> states) {
                // Střídání barev pro zebra efekt
                return index % 2 == 0 ? Colors.grey[200] : null;
              },
            ),
            cells: [
              DataCell(
                  Text(components[index]['caliber']?['name'] ?? 'Neznámý')),
              DataCell(Text(components[index]['name'] ?? 'Neznámý')),
              DataCell(Text(components[index]['stock_quantity']?.toString() ??
                  'Neznámá')),
            ],
          ),
        );
        break;

      default:
        columns = [];
        rows = [];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        components.isEmpty
            ? const Text('Nenalezeny žádné položky.')
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: columns,
                  rows: rows,
                ),
              ),
      ],
    );
  }
}
