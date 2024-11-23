import 'package:flutter/material.dart';
import 'package:shooting_companion/helpers/database_helper.dart';

class DatabaseViewScreen extends StatefulWidget {
  @override
  _DatabaseViewScreenState createState() => _DatabaseViewScreenState();
}

class _DatabaseViewScreenState extends State<DatabaseViewScreen> {
  List<Map<String, dynamic>> _data = [];
  String _selectedTable = 'weapons';
  final DatabaseHelper _dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await _dbHelper.getData(_selectedTable);
      setState(() {
        _data = data;
      });
    } catch (e) {
      print('Chyba při načítání dat: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Data z tabulky: $_selectedTable'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _selectedTable = value;
              });
              _loadData();
            },
            itemBuilder: (context) => [
              'weapons',
              'cartridges',
              'calibers',
              'offline_requests',
              'weapon_calibers',
            ].map((table) {
              return PopupMenuItem(
                value: table,
                child: Text(table),
              );
            }).toList(),
          ),
        ],
      ),
      body: _data.isEmpty
          ? Center(
              child: Text('Tabulka $_selectedTable neobsahuje žádná data.'))
          : ListView.builder(
              itemCount: _data.length,
              itemBuilder: (context, index) {
                final row = _data[index];
                return Card(
                  margin: EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(row.toString()),
                  ),
                );
              },
            ),
    );
  }
}
