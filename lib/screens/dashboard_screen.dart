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
import 'package:shooting_companion/widgets/custom_button.dart';
import 'package:shooting_companion/widgets/header_widget.dart';
import 'package:shooting_companion/helpers/snackbar_helper.dart';
import 'package:shooting_companion/helpers/connectivity_helper.dart';
import 'package:shooting_companion/services/sync_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:shooting_companion/widgets/connectivity_monitor.dart';
import 'package:shooting_companion/screens/shooting_logs_overview_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String username;

  const DashboardScreen({super.key, required this.username});
  static const String currentVersion = "1.1.5"; // Aktuální verze aplikace

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ConnectivityHelper _connectivityHelper = ConnectivityHelper();
  late String username;
  bool isRangeInitialized = false;
  late Future<Map<String, List<Map<String, dynamic>>>> _cartridgesFuture;
  bool isOnline = true; // Stav připojení
  bool isSyncing = false; // Stav synchronizace
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  late ConnectivityMonitor _connectivityMonitor;
  late SyncService _syncService;
  bool _previousOnlineState = false;
  int _pendingRequestsCount = 0;
  Timer? _pendingRequestsTimer;
  bool _isUpdatingPendingCount = false;

  @override
  void initState() {
    super.initState();
    _checkVersion();
    username = widget.username;
    _updatePendingRequestsCount();
    DatabaseHelper()
        .setOnOfflineRequestAddedCallback(_updatePendingRequestsCount);

    setState(() {
      isSyncing = true;
    });

    // Nejdřív inicializujeme SyncService
    _syncService = SyncService(
      context,
      onSyncComplete: _updatePendingRequestsCount,
    );

    // Registrujeme SyncService do ConnectivityHelper
    _connectivityHelper.registerSyncService(_syncService);

    // Inicializace _cartridgesFuture pro načtení dat
    _cartridgesFuture = _syncService.syncWithApi().then((_) async {
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

        // Nastavíme synchronizaci na false po dokončení
        if (mounted) {
          setState(() {
            isSyncing = false;
          });
        }

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePendingRequestsCount(); // Aktualizace při návratu na obrazovku
  }

  Future<void> _updatePendingRequestsCount() async {
    if (_isUpdatingPendingCount) return;

    // Zrušit předchozí timer pokud existuje
    _pendingRequestsTimer?.cancel();

    // Nastavit nový timer
    _pendingRequestsTimer = Timer(Duration(milliseconds: 500), () async {
      _isUpdatingPendingCount = true;

      try {
        final db = await DatabaseHelper().database;
        final count = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM offline_requests WHERE status = ?',
          ['pending'],
        ));

        if (mounted) {
          setState(() {
            _pendingRequestsCount = count ?? 0;
          });
        }
      } finally {
        _isUpdatingPendingCount = false;
      }
    });
  }

  Future<void> _checkVersion() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.reloading-tracker.cz/actual_version.txt'),
      );

      if (response.statusCode == 200) {
        final latestVersion = response.body.trim();

        if (latestVersion != DashboardScreen.currentVersion) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('Dostupná nová verze'),
                  content: Text(
                    'Vaše verze: ${DashboardScreen.currentVersion}\n'
                    'Dostupná verze: $latestVersion\n\n'
                    'DŮLEŽITÉ: Před instalací nové verze důrazně doporučujeme '
                    'nejprve odinstalovat stávající verzi aplikace!',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                );
              },
            );
          }
        }
      }
    } catch (e) {
      print('Chyba při kontrole verze: $e');
    }
  }

  void testSQLQuery() async {
    try {
      // Získej cestu k úložišti databází aplikace
      final dbPath = await getDatabasesPath();
      print('Debug: Cesta k databázím: $dbPath');

      // Získej seznam všech souborů v adresáři pro databáze
      final dbDirectory = Directory(dbPath);
      List<FileSystemEntity> dbFiles = dbDirectory.listSync();

      print('Debug: Existující databázové soubory:');
      for (var dbFile in dbFiles) {
        if (dbFile is File) {
          print(' - ${path.basename(dbFile.path)}');
        }
      }

      // Připojení ke konkrétní databázi 'reloading_tracker.db'
      final db = await openDatabase(path.join(dbPath, 'reloading_tracker.db'));
      print('Debug: Připojeno k databázi na adrese: ${db.path}');

      // Ověření, které tabulky jsou dostupné
      final tables = await db
          .rawQuery('SELECT name FROM sqlite_master WHERE type="table";');
      print('Debug: Existující tabulky: $tables');

      // Ověření, zda tabulka 'weapons' existuje
      bool weaponsTableExists =
          tables.any((table) => table['name'] == 'weapons');

      if (!weaponsTableExists) {
        print(
            'Warning: Tabulka weapons nebyla nalezena. Dostupné tabulky: $tables');

        // Dotaz na podrobnosti o tabulkách ve `sqlite_master`
        final detailedTables =
            await db.rawQuery('SELECT * FROM sqlite_master;');
        print(
            'Debug: Podrobné informace o tabulkách ve sqlite_master: $detailedTables');
      } else {
        // Upravený dotaz pro ladění problému s tabulkou 'weapons'
        final result = await db.rawQuery('''
      SELECT 
        weapons.id AS weapon_id,
        weapons.name AS weapon_name,
        calibers.id AS caliber_id,
        calibers.name AS caliber_name
      FROM weapons
      LEFT JOIN weapon_calibers ON weapons.id = weapon_calibers.weapon_id
      LEFT JOIN calibers ON weapon_calibers.caliber_id = calibers.id
      WHERE calibers.id = 35;
      ''');

        print('Debug: Výsledky dotazu na tabulku weapons a calibers: $result');
      }
    } catch (e) {
      print('Error: Chyba při dotazu do databáze: $e');
    }
  }

  Future<void> _logout() async {
    try {
      final secureStorage = FlutterSecureStorage();
      await secureStorage
          .deleteAll(); // Smaže všechna uložená data (tokeny, hesla, atd.)
      Navigator.pushReplacementNamed(
          context, '/login'); // Přesměrování na přihlašovací obrazovku
    } catch (e) {
      SnackbarHelper.show(context, 'Chyba při odhlášení: $e');
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
        // Stačí jen nastavit isRangeInitialized na true,
        // detailní zpracování se děje v ShootingLogScreen
        isRangeInitialized = true;
      });
    } catch (e) {
      print('Error loading ranges: $e');
    }
  }

  void _showSyncSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityMonitor(
        child: Scaffold(
      appBar: AppBar(
        title: Text(
          'Shooting Companion',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
            shadows: [
              Shadow(
                offset: Offset(2, 2),
                color: Colors.black54,
                blurRadius: 4,
              ),
            ],
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.blueGrey,
        actions: [
          StreamBuilder<bool>(
            stream: _connectivityHelper.onConnectionChange,
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? false;
              _previousOnlineState = isOnline;

              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Stack(
                  children: [
                    Tooltip(
                      message: isOnline ? 'Online' : 'Offline',
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          isOnline ? Icons.cloud_done : Icons.cloud_off,
                          key: ValueKey(isOnline),
                          color: isOnline
                              ? Colors.lightBlueAccent
                              : Colors.grey.shade500,
                          size: 28,
                        ),
                      ),
                    ),
                    if (_pendingRequestsCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Text(
                          '$_pendingRequestsCount',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Shooting Companion',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'v${DashboardScreen.currentVersion}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person,
                            size: 16,
                            color: Colors.white70,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              username,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.storage,
                            size: 16,
                            color: Colors.white70,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: FutureBuilder<Map<String, dynamic>>(
                              future: DatabaseHelper().getUserProfile(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return CircularProgressIndicator();
                                }

                                final totalStorageUsed =
                                    snapshot.data!['storage_used'] ?? 0;
                                final storageLimit =
                                    snapshot.data!['storage_limit'] ?? 0;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: totalStorageUsed / storageLimit,
                                        backgroundColor: Colors.white24,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.lightBlueAccent),
                                        minHeight: 4,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '${(totalStorageUsed / 1048576).toStringAsFixed(1)} MB / ${(storageLimit / 1048576).toStringAsFixed(0)} MB',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text(
                '⚙️ Systémové funkce',
                style: TextStyle(
                  color: const Color(0xFFD32F2F),
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'Upozornění: Tyto funkce jsou určeny pouze pro pokročilé uživatele',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ),
            ExpansionTile(
              title: const Text(
                'Správa dat',
                style: const TextStyle(color: Color(0xFF616161)),
              ),
              leading: const Icon(Icons.admin_panel_settings),
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Smazat databázi'),
                  subtitle: const Text('Nevratně smaže všechna data'),
                  onTap: () {
                    Navigator.of(context).pop();
                    showDialog(
                      context: context,
                      builder: (BuildContext context) => AlertDialog(
                        title: const Text('⚠️ Nebezpečná operace'),
                        content: const Text(
                          'Opravdu chcete smazat databázi?\nTato akce je NEVRATNÁ!',
                          style: TextStyle(color: Colors.red),
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Zrušit'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _deleteDatabase();
                            },
                            child: const Text('Smazat',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Export databáze'),
                  onTap: () {
                    Navigator.of(context).pop();
                    exportDatabase();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Sdílet databázi'),
                  onTap: () {
                    Navigator.of(context).pop();
                    shareDatabaseFile();
                  },
                ),
              ],
            ),
            ExpansionTile(
              title: const Text(
                'Vývojářské nástroje',
                style: TextStyle(color: Color(0xFF616161)),
              ),
              leading: const Icon(Icons.code),
              children: [
                ListTile(
                  leading: const Icon(Icons.filter_alt),
                  title: const Text('Test filtru'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    final dbHelper = DatabaseHelper();
                    final cartridges =
                        await dbHelper.fetchCartridgesFromSQLite();
                    print("Test filtru: Načteno ${cartridges.length} nábojů.");
                    final filtered = dbHelper.applyFilter(cartridges);
                    print(
                        "Test filtru: Po aplikaci filtru: ${filtered.length} nábojů.");
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("Výsledky testu filtru"),
                        content: Text(
                          filtered.isEmpty
                              ? "Nebyl nalezen žádný validní náboj."
                              : "Validní náboje:\n${filtered.map((e) => e['name']).join('\n')}",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text("Zavřít"),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.table_chart),
                  title: const Text('Prohlížeč databáze'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => DatabaseViewScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('Test SQL dotazu'),
                  onTap: () {
                    Navigator.of(context).pop();
                    testSQLQuery();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Testovací SQL dotaz byl proveden')),
                    );
                  },
                ),
              ],
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
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Načítání dat...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                const SizedBox(height: 16),
                // In ListView children array, replace existing buttons with:
                CustomButton(
                  icon: Icons.book,
                  text: 'Střelecký deník',
                  color: Colors.teal,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ShootingLogsOverviewScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                CustomButton(
                  icon: Icons.inventory_2,
                  text: 'Inventář nábojů',
                  color: Colors.blueGrey,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FutureBuilder<
                            Map<String, List<Map<String, dynamic>>>>(
                          future: _cartridgesFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Scaffold(
                                  body: Center(
                                      child: CircularProgressIndicator()));
                            }
                            if (snapshot.hasError) {
                              return Scaffold(
                                appBar: AppBar(
                                    title: const Text('Inventář nábojů')),
                                body: Center(
                                    child: Text('Chyba: ${snapshot.error}')),
                              );
                            }
                            return FavoriteCartridgesScreen(
                              factoryCartridges:
                                  snapshot.data?['factory'] ?? [],
                              reloadCartridges: snapshot.data?['reload'] ?? [],
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                CustomButton(
                  icon: Icons.qr_code_scanner,
                  text: 'Úprava zásob',
                  color: Colors.blue,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const BarcodeScannerScreen(source: 'dashboard'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                CustomButton(
                  icon: Icons.inventory,
                  text: 'Sklad komponent',
                  color: Colors.orange,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const InventoryComponentsScreen(),
                    ),
                  ),
                ),
                if (isSyncing) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Probíhá synchronizace dat...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blueGrey),
                  ),
                ],
              ],
            ),
    ));
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

      SnackbarHelper.show(context, 'Databáze byla úspěšně smazána.');

      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      SnackbarHelper.show(context, 'Chyba při mazání databáze: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
