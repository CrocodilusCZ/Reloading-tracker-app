import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:shooting_companion/screens/barcode_scanner_screen.dart';
import 'package:shooting_companion/screens/favorite_cartridges_screen.dart';
import 'package:shooting_companion/screens/shooting_log_screen.dart';
import 'package:shooting_companion/screens/inventory_components_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart'; // Přidáno pro použití XFile
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert'; // Přidán import pro jsonDecode
import 'package:shooting_companion/screens/database_view_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String username;

  const DashboardScreen({super.key, required this.username});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late String username;
  bool isRangeInitialized = false;
  late Future<Map<String, List<Map<String, dynamic>>>> _cartridgesFuture;
  bool isOnline = true; // Stav připojení
  bool isSyncing = false; // Stav synchronizace
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    username = widget.username;

    // Inicializace _cartridgesFuture pro načtení dat
    _cartridgesFuture = _syncWithApi().then((_) async {
      try {
        // Načti data ze SQLite nebo jiného zdroje po synchronizaci
        final cartridgesFromSQLite =
            await DatabaseHelper().fetchCartridgesFromSQLite();

        print("Načtené náboje z SQLite:");
        for (var cartridge in cartridgesFromSQLite) {
          print(
              "Náboj: ${cartridge['name']}, Typ: ${cartridge['cartridge_type']}, Množství: ${cartridge['stock_quantity']}, Kalibr: ${cartridge['caliber_name']}");
        }

        // Kontrola a oprava chybějících dat
        final cleanedCartridges = cartridgesFromSQLite.map((cartridge) {
          // Zajistí, že cartridge_type a caliber_name nejsou null
          return {
            ...cartridge,
            'cartridge_type': cartridge['cartridge_type'] ?? 'unknown',
            'caliber_name': cartridge['caliber_name'] ?? 'Unknown',
          };
        }).toList();

        // Rozdělení na tovární a přebíjené náboje
        final factory = cleanedCartridges
            .where((cartridge) => cartridge['cartridge_type'] == 'factory')
            .toList();
        final reload = cleanedCartridges
            .where((cartridge) => cartridge['cartridge_type'] == 'reload')
            .toList();

        print("Načteno: Factory=${factory.length}, Reload=${reload.length}");

        // Logování případných neznámých typů
        final unknownCartridges = cleanedCartridges
            .where((cartridge) => cartridge['cartridge_type'] == 'unknown')
            .toList();
        if (unknownCartridges.isNotEmpty) {
          print("Upozornění: Některé náboje mají neznámý typ:");
          for (var cartridge in unknownCartridges) {
            print(
                "Náboj: ${cartridge['name']}, Typ: ${cartridge['cartridge_type']}, Kalibr: ${cartridge['caliber_name']}");
          }
        }

        // Vrácení načtených dat
        return {
          'factory': factory,
          'reload': reload,
        };
      } catch (e) {
        print('Chyba při načítání dat po synchronizaci: $e');
        return {
          'factory': <Map<String, dynamic>>[],
          'reload': <Map<String, dynamic>>[],
        };
      }
    }).catchError((error) {
      print('Chyba při synchronizaci: $error');
      return {
        'factory': <Map<String, dynamic>>[],
        'reload': <Map<String, dynamic>>[],
      };
    });

    // Sleduje změny připojení
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .expand((results) => results)
        .listen((connectivityResult) {
      _checkConnectionStatus(connectivityResult);
    });
  }

  Future<void> _logout() async {
    try {
      final secureStorage = FlutterSecureStorage();
      await secureStorage
          .deleteAll(); // Smaže všechna uložená data (tokeny, hesla, atd.)
      Navigator.pushReplacementNamed(
          context, '/login'); // Přesměrování na přihlašovací obrazovku
    } catch (e) {
      _showSnackBar('Chyba při odhlášení: $e');
    }
  }

  void _checkConnectionStatus(ConnectivityResult connectivityResult) {
    final newIsOnline = connectivityResult != ConnectivityResult.none;

    if (newIsOnline != isOnline) {
      setState(() {
        isOnline = newIsOnline;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOnline
              ? 'Jste online. Data se budou synchronizovat s API.'
              : 'Jste offline. Data budou načtena z lokální databáze.'),
          duration: const Duration(seconds: 3),
        ),
      );

      // Spustí synchronizaci, když aplikace přejde do online režimu
      if (isOnline) {
        _syncOfflineRequests();
      }
    }
  }

  Future<void> shareFile() async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        print('Nepodařilo se získat přístup k externímu úložišti.');
        return;
      }
      final filePath = '${directory.path}/reloading_tracker_export.db';

      final file = File(filePath);

      if (await file.exists()) {
        // Použijte Share.shareXFiles místo Share.shareFiles
        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'Sdílet soubor',
        );
      } else {
        print('Soubor neexistuje na cestě: $filePath');
      }
    } catch (e) {
      print('Chyba při sdílení souboru: $e');
    }
  }

  Future<void> shareDatabaseFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/reloading_tracker_export.db';

      final file = File(filePath);

      if (await file.exists()) {
        // Použijte Share.shareXFiles místo Share.shareFiles
        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'Sdílet databázi',
        );
      } else {
        print('Databázový soubor neexistuje na cestě: $filePath');
      }
    } catch (e) {
      print('Chyba při sdílení databáze: $e');
    }
  }

  Future<void> exportDatabase() async {
    try {
      // Cesta k databázovému souboru
      final directory = await getApplicationDocumentsDirectory();
      final dbPath = path.join(directory.path, 'reloading_tracker.db');

      final databaseFile = File(dbPath);

      if (!await databaseFile.exists()) {
        print('Původní databázový soubor neexistuje na cestě: $dbPath');
        return;
      }

      // Cíl pro export
      final exportPath =
          path.join(directory.path, 'reloading_tracker_export.db');

      // Kopírování databáze
      await databaseFile.copy(exportPath);
      print('Databáze byla exportována na: $exportPath');
    } catch (e) {
      print('Chyba při exportu databáze: $e');
    }
  }

  // Synchronizace kalibrů
  Future<void> syncCalibers() async {
    try {
      final calibers = await ApiService.getCalibers(); // Načtení kalibrů z API
      await DatabaseHelper()
          .syncCalibersFromApi(calibers); // Synchronizace do SQLite
      print("Kalibry byly úspěšně synchronizovány.");
    } catch (e) {
      print("Chyba při synchronizaci kalibrů: $e");
    }
  }

  Future<void> _initializeDashboard() async {
    try {
      setState(() {
        isSyncing = true;
      });

      print("Načítám data z API...");

      // Pokus o načtení dat z API
      final apiData = await ApiService.getAllCartridges();

      // Pokud je načtení z API úspěšné, nastavíme isOnline na true
      setState(() {
        isOnline = true;
      });

      print("Data načtena z API: ${apiData.keys.join(', ')}");

      // Synchronizace s SQLite
      final allCartridges = [...?apiData['factory'], ...?apiData['reload']];
      print("Počet všech nábojů ke synchronizaci: ${allCartridges.length}");
      await DatabaseHelper().syncCartridgesFromApi(allCartridges);

      // Synchronizace kalibrů
      final calibers = await ApiService.getCalibers();
      print("Počet načtených kalibrů: ${calibers.length}");
      await DatabaseHelper().syncCalibersFromApi(calibers);

      // Aplikace filtru na data z API
      print("Aplikuji filtry na data z API...");
      final filteredFactory =
          DatabaseHelper().applyFilter(apiData['factory'] ?? []);
      final filteredReload =
          DatabaseHelper().applyFilter(apiData['reload'] ?? []);

      print(
          "Filtrované náboje: tovární=${filteredFactory.length}, přebíjené=${filteredReload.length}");

      _cartridgesFuture = Future.value({
        'factory': filteredFactory,
        'reload': filteredReload,
      });
    } catch (e) {
      setState(() {
        isOnline = false;
      });

      print("Chyba při načítání dat z API: $e");
      print("Přecházím na načítání dat ze SQLite...");

      try {
        final offlineCartridges =
            await DatabaseHelper().fetchCartridgesFromSQLite();
        print("Načteno ${offlineCartridges.length} nábojů ze SQLite.");

        for (var cartridge in offlineCartridges) {
          print(
              "Náboj: ${cartridge['name']}, stock_quantity=${cartridge['stock_quantity']}, cartridge_type=${cartridge['cartridge_type']}");
        }

        // Aplikace filtru na data z SQLite
        final filteredCartridges =
            DatabaseHelper().applyFilter(offlineCartridges);

        print("Počet nábojů po filtru: ${filteredCartridges.length}");

        // Rozdělení na tovární a přebíjené
        final factory = filteredCartridges
            .where((cartridge) => cartridge['cartridge_type'] == 'factory')
            .toList();
        final reload = filteredCartridges
            .where((cartridge) => cartridge['cartridge_type'] == 'reload')
            .toList();

        print(
            "Rozdělení dokončeno: tovární=${factory.length}, přebíjené=${reload.length}");

        _cartridgesFuture = Future.value({
          'factory': factory,
          'reload': reload,
        });
      } catch (sqliteError) {
        print("Chyba při načítání dat ze SQLite: $sqliteError");

        _cartridgesFuture = Future.value({
          'factory': [],
          'reload': [],
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Chyba při načítání dat: $sqliteError")),
        );
      }
    } finally {
      setState(() {
        isSyncing = false;
      });
    }
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

  Future<void> _syncDataAfterLogin() async {
    try {
      await _syncWithApi();
    } catch (e) {
      _showSnackBar('Chyba při synchronizaci s API: $e');
    }

    // Pokusíme se synchronizovat offline požadavky
    await _syncOfflineRequests();
  }

  Future<void> _syncWithApi() async {
    try {
      print('Synchronizace: Začínám synchronizaci všech dat.');

      // Vytvoření instance DatabaseHelper
      final dbHelper = DatabaseHelper();

      // Synchronizace střelnic
      try {
        print('Synchronizuji střelnice...');
        final ranges = await ApiService.getUserRanges();
        print('Načteno střelnic z API: ${ranges.length}');
        await dbHelper.syncRangesFromApi(ranges);
        print('Střelnice uloženy do SQLite. Počet střelnic: ${ranges.length}');
      } catch (e) {
        print('Chyba při synchronizaci střelnic: $e');
      }

      // Synchronizace nábojů
      try {
        print('Synchronizuji náboje...');
        final cartridges = await ApiService.getAllCartridges();
        print(
            'Načteno nábojů z API: ${cartridges.values.expand((x) => x).length}');
        await dbHelper.syncCartridgesFromApi(
            [...?cartridges['factory'], ...?cartridges['reload']]);
        print('Náboje uloženy do SQLite.');
      } catch (e) {
        print('Chyba při synchronizaci nábojů: $e');
      }

      // Synchronizace kalibrů
      try {
        print('Synchronizuji kalibry...');
        final calibers = await ApiService.getCalibers();
        print('Načteno kalibrů z API: ${calibers.length}');
        await dbHelper.syncCalibersFromApi(calibers);
        print('Kalibry uloženy do SQLite. Počet kalibrů: ${calibers.length}');
      } catch (e) {
        print('Chyba při synchronizaci kalibrů: $e');
      }

      // Synchronizace aktivit
      try {
        print('Synchronizuji aktivity...');
        final activities = await ApiService.getUserActivities();
        print('Načteno aktivit z API: ${activities.length}');
        for (var activity in activities) {
          print('Ukládám aktivitu do SQLite: $activity');
          await dbHelper.insertOrUpdate('activities', activity);
        }
        print('Aktivity uloženy do SQLite.');
      } catch (e) {
        print('Chyba při synchronizaci aktivit: $e');
      }

      // Synchronizace zbraní
      try {
        print('Synchronizuji zbraně...');
        final weapons = await ApiService.getUserWeapons();
        print('Načteno zbraní z API: ${weapons.length}');
        for (var weapon in weapons) {
          print('Ukládám zbraň do SQLite: $weapon');
        }
        await dbHelper.saveWeapons(weapons);
        print('Zbraně uloženy do SQLite.');
      } catch (e) {
        print('Chyba při synchronizaci zbraní: $e');
      }

      print('Synchronizace všech dat dokončena.');
      _showSnackBar('Data byla úspěšně synchronizována.');
    } catch (e) {
      print('Chyba při synchronizaci s API: $e');
      _showSnackBar('Chyba při synchronizaci s API: $e');
    }
  }

  // Synchronizace neodeslaných požadavků
  // Synchronizace neodeslaných požadavků
  Future<void> _syncOfflineRequests() async {
    final db = await DatabaseHelper().database;

    // Přidán log pro začátek synchronizace_syncWithApi
    print('Začínám synchronizaci offline požadavků...');

    // Načtení všech "pending" požadavků
    final requests = await db.query(
      'offline_requests',
      where: 'status = ?',
      whereArgs: ['pending'],
    );

    print('Načteno ${requests.length} offline požadavků k synchronizaci.');

    for (var request in requests) {
      final requestType = request['request_type'];
      final rawData = request['data']; // Hodnota může být Object?

      if (rawData is! String) {
        print('Chyba: Hodnota dat v požadavku není typu String: $rawData');
        continue;
      }

      try {
        final requestData = jsonDecode(rawData); // Zpracuj pouze validní String

        // Přidán log pro aktuální typ požadavku
        print(
            'Synchronizuji požadavek ID ${request['id']} typu $requestType s daty: $requestData');

        // Rozhodni se podle typu požadavku
        switch (requestType) {
          case 'update_stock':
            print(
                'Provádím synchronizaci zásoby pro cartridge ID ${requestData['id']} s množstvím ${requestData['quantity']}');
            await ApiService.syncRequest(
              '/cartridges/${requestData['id']}/update-stock',
              {'quantity': requestData['quantity']},
            );
            break;

          case 'create_activity':
            print('Vytvářím aktivitu s daty: $requestData');
            await ApiService.syncRequest(
              '/activities',
              requestData,
            );
            break;

          case 'delete_activity':
            print('Mažu aktivitu s ID ${requestData['id']}');
            await ApiService.syncRequest(
              '/activities/${requestData['id']}/delete',
              {},
            );
            break;

          default:
            print('Neznámý typ požadavku: $requestType');
            continue;
        }

        // Po úspěchu nastav status na "completed"
        await db.update(
          'offline_requests',
          {'status': 'completed'},
          where: 'id = ?',
          whereArgs: [request['id']],
        );

        print('Požadavek ID ${request['id']} byl synchronizován úspěšně.');
      } catch (e) {
        print('Chyba při synchronizaci požadavku ID ${request['id']}: $e');
      }
    }
    print('Synchronizace offline požadavků dokončena.');
  }

  void _showSyncSnackBar(String message) {
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
        actions: [
          Icon(
            isOnline ? Icons.signal_wifi_4_bar : Icons.signal_wifi_off,
            color: isOnline ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 16),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blueGrey,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.person, size: 64, color: Colors.white),
                  SizedBox(height: 8),
                  Text(
                    username,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Shooting_companion_0.9',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.delete, color: Colors.red),
              title: Text('Smazat databázi'),
              onTap: () {
                Navigator.of(context).pop(); // Zavřít Drawer
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('Potvrdit akci'),
                      content: Text(
                          'Opravdu chcete smazat databázi? Tato akce je nevratná.'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('Zrušit'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _deleteDatabase();
                          },
                          child: Text('Smazat'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.download, color: Colors.green),
              title: Text('Exportovat databázi'),
              onTap: () {
                Navigator.of(context).pop(); // Zavřít Drawer
                exportDatabase();
              },
            ),
            ListTile(
              leading: Icon(Icons.share, color: Colors.blue),
              title: Text('Sdílet databázi'),
              onTap: () {
                Navigator.of(context).pop(); // Zavřít Drawer
                shareDatabaseFile();
              },
            ),
            ListTile(
              leading: Icon(Icons.filter_alt, color: Colors.orange),
              title: Text('Test Filtru'),
              onTap: () async {
                Navigator.of(context).pop(); // Zavřít Drawer
                final dbHelper = DatabaseHelper();
                final cartridges = await dbHelper.fetchCartridgesFromSQLite();
                print("Test filtru: Načteno ${cartridges.length} nábojů.");
                final filtered = dbHelper.applyFilter(cartridges);
                print(
                    "Test filtru: Po aplikaci filtru: ${filtered.length} nábojů.");
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text("Výsledky Testu Filtru"),
                    content: Text(
                      filtered.isEmpty
                          ? "Nebyl nalezen žádný validní náboj."
                          : "Validní náboje:\n${filtered.map((e) => e['name']).join('\n')}",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text("Zavřít"),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.table_chart, color: Colors.purple),
              title: Text('Prohlížet databázi'),
              onTap: () {
                Navigator.of(context).pop(); // Zavřít Drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DatabaseViewScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.exit_to_app, color: Colors.redAccent),
              title: Text('Odhlásit se'),
              onTap: () {
                Navigator.of(context).pop(); // Zavřít Drawer
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Odhlásit se'),
                    content: Text('Opravdu se chcete odhlásit?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Zrušit'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _logout();
                        },
                        child: Text('Odhlásit'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: isSyncing
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
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
                        builder: (context) => Scaffold(
                            appBar: AppBar(
                              title: const Text('Inventář nábojů'),
                              backgroundColor: Colors.blueGrey,
                            ),
                            body: FutureBuilder<
                                Map<String, List<Map<String, dynamic>>>>(
                              future: _cartridgesFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                } else if (snapshot.hasError) {
                                  print(
                                      "Chyba v FutureBuilder: ${snapshot.error}");
                                  return Center(
                                    child: Text(
                                      'Chyba: ${snapshot.error}',
                                      style: const TextStyle(
                                          color: Colors.red, fontSize: 16),
                                    ),
                                  );
                                } else if (!snapshot.hasData ||
                                    (snapshot.data!['factory']?.isEmpty ??
                                            true) &&
                                        (snapshot.data!['reload']?.isEmpty ??
                                            true)) {
                                  print(
                                      "Žádné náboje nenalezeny: ${snapshot.data}");
                                  return const Center(
                                    child: Text(
                                      'Žádné náboje nenalezeny.',
                                      style: TextStyle(
                                          fontSize: 18, color: Colors.grey),
                                    ),
                                  );
                                } else {
                                  print(
                                      "Předáváme data do FavoriteCartridgesScreen:");
                                  print(
                                      "Tovární: ${snapshot.data!['factory']}");
                                  print(
                                      "Přebíjené: ${snapshot.data!['reload']}");
                                  return FavoriteCartridgesScreen(
                                    factoryCartridges:
                                        snapshot.data!['factory']!,
                                    reloadCartridges: snapshot.data!['reload']!,
                                  );
                                }
                              },
                            )),
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

  void _deleteDatabase() async {
    try {
      final dbHelper = DatabaseHelper();

      final directory = await getApplicationDocumentsDirectory();

      final dbPath = path.join(directory.path, 'reloading_tracker.db');

      final file = File(dbPath);
      if (await file.exists()) {
        await file.delete();
      }

      await dbHelper.deleteAllTables();

      _showSnackBar('Databáze byla úspěšně smazána.');

      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      _showSnackBar('Chyba při mazání databáze: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildHeader() {
    print('Rendering header with username: $username');
    return Row(
      children: [
        const Icon(Icons.person, size: 40, color: Colors.blueGrey),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Verze aplikace: Shooting_companion_0.9',
                style: const TextStyle(
                  fontSize: 14, // Zmenšeno z 16
                  color: Colors.grey,
                ),
                overflow:
                    TextOverflow.ellipsis, // Zkrácení textu, pokud se nevejde
              ),
            ],
          ),
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

  @override
  void dispose() {
    _connectivitySubscription.cancel(); // Zrušení sledování připojení
    super.dispose(); // Zavolání nadřazené dispose metody
  }
}
