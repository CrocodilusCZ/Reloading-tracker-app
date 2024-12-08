import 'package:shooting_companion/services/api_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert'; // Pro práci s JSON¨
import 'package:flutter/material.dart';
import 'package:shooting_companion/database/database_schema.dart';
import 'package:shooting_companion/models/cartridge.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;

  DatabaseHelper._internal();

  Future<void> createAllTables(Database db) async {
    await DatabaseSchema.createTables(db); // Call private static method
  }

  // Statická metoda pro získání zbraní
  static Future<List<Map<String, dynamic>>> getWeapons({int? caliberId}) async {
    final db = await DatabaseHelper().database;

    // Základní SQL dotaz s JOIN pro propojení weapons a calibers přes weapon_calibers
    String query = '''
    SELECT 
      weapons.id AS weapon_id,
      weapons.name AS weapon_name,
      weapons.initial_shots,
      calibers.id AS caliber_id,
      calibers.name AS caliber_name
    FROM weapons
    LEFT JOIN weapon_calibers ON weapons.id = weapon_calibers.weapon_id
    LEFT JOIN calibers ON weapon_calibers.caliber_id = calibers.id
  ''';

    // Pokud je caliberId zadáno, přidáme WHERE klauzuli
    if (caliberId != null) {
      query += ' WHERE calibers.id = ?';
      return await db.rawQuery(query, [caliberId]);
    }

    // Pokud caliberId není zadáno, vrátí všechny zbraně s kalibry
    return await db.rawQuery(query);
  }

// Metoda pro získání zbraní na základě caliberId
  static Future<List<Map<String, dynamic>>> getWeaponsByCaliber(
      int caliberId) async {
    final db = await DatabaseHelper().database;

    // SQL dotaz pro propojení weapons a calibers přes weapon_calibers
    String query = '''
  SELECT 
    weapons.id AS weapon_id,
    weapons.name AS weapon_name,
    calibers.id AS caliber_id,
    calibers.name AS caliber_name
  FROM weapons
  JOIN weapon_calibers ON weapons.id = weapon_calibers.weapon_id
  JOIN calibers ON weapon_calibers.caliber_id = calibers.id
  WHERE calibers.id = ?
  ''';

    // Provede dotaz s daným caliberId
    final result = await db.rawQuery(query, [caliberId]);

    if (result.isEmpty) {
      print('Debug: Žádné zbraně nenalezeny pro caliberId=$caliberId');
    } else {
      print('Debug: Výsledek dotazu pro caliberId=$caliberId: $result');
    }

    return result;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<List<Map<String, dynamic>>> getRanges() async {
    final db = await database;
    return await db.query('ranges');
  }

  Future<void> saveRanges(List<Map<String, dynamic>> ranges) async {
    final db = await database;

    // Začít transakci
    await db.transaction((txn) async {
      // Smazat existující záznamy
      await txn.delete('ranges');

      // Vložit nové záznamy
      for (var range in ranges) {
        await txn.insert(
          'ranges',
          {
            'id': range['id'],
            'name': range['name'],
            'location': range['location'] ?? '',
            'hourly_rate': range['hourly_rate'] ?? 0.0,
            'user_id': range['user_id'] ?? 1,
            'created_at': range['created_at'],
            'updated_at': range['updated_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<Map<String, dynamic>?> getCartridgeByBarcode(String barcode) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'cartridges',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    // Přidat informace o kalibru
    final caliber = await db.query(
      'calibers',
      where: 'id = ?',
      whereArgs: [result.first['caliber_id']],
      limit: 1,
    );

    if (caliber.isNotEmpty) {
      result.first['caliber'] = caliber.first;
    }

    return result.first;
  }

  Future<void> saveWeapons(List<Map<String, dynamic>> weapons) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        for (var weapon in weapons) {
          if (weapon['id'] == null || weapon['name'] == null) {
            print("Neplatná data zbraně: $weapon - přeskočeno.");
            continue;
          }

          // Uložení samotné zbraně
          await txn.insert(
            'weapons',
            {
              'id': weapon['id'],
              'user_id': weapon['user_id'],
              'name': weapon['name'],
              'created_at': weapon['created_at'],
              'updated_at': weapon['updated_at'],
              'initial_shots': weapon['initial_shots'] ?? 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          print("Uložena zbraň: ${weapon['name']} (ID: ${weapon['id']})");

          // Zpracování a uložení kalibrů zbraně
          if (weapon.containsKey('calibers') && weapon['calibers'] is List) {
            final calibers = weapon['calibers'] as List;

            // Nejprve smažeme staré kalibry této zbraně
            await txn.delete(
              'weapon_calibers',
              where: 'weapon_id = ?',
              whereArgs: [weapon['id']],
            );

            // Poté vložíme nové kalibry
            for (var caliber in calibers) {
              if (caliber['id'] == null) {
                print("Neplatný kalibr: $caliber - přeskočeno.");
                continue;
              }

              await txn.insert(
                'weapon_calibers',
                {
                  'weapon_id': weapon['id'],
                  'caliber_id': caliber['id'],
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              print(
                  "Propojen kalibr ID ${caliber['id']} se zbraní ID ${weapon['id']}.");
            }
          }
        }
      });
      print("Všechny zbraně a jejich kalibry byly uloženy.");
    } catch (e) {
      print("Chyba při ukládání zbraní a jejich kalibrů: $e");
    }
  }

  Future<void> updateStockOffline(int cartridgeId, int quantityChange) async {
    final db = await database;

    if (quantityChange == 0) {
      print("QuantityChange je 0, požadavek nebude uložen.");
      return;
    }

    // Načtení aktuální zásoby
    final result = await db.query(
      'cartridges',
      where: 'id = ?',
      whereArgs: [cartridgeId],
    );

    if (result.isNotEmpty) {
      final currentStock =
          int.tryParse(result.first['stock_quantity'].toString()) ?? 0;
      final newStock = currentStock + quantityChange;

      // Aktualizace zásoby
      await db.update(
        'cartridges',
        {'stock_quantity': newStock},
        where: 'id = ?',
        whereArgs: [cartridgeId],
      );

      // Uložení požadavku
      await db.insert(
        'offline_requests',
        {
          'request_type': 'update_stock',
          'data': jsonEncode({'id': cartridgeId, 'quantity': quantityChange}),
          'status': 'pending',
        },
      );
      print("Zásoba cartridge ID $cartridgeId aktualizována na $newStock.");
    } else {
      print("Cartridge ID $cartridgeId nebyla nalezena.");
    }
  }

  // Metoda pro smazání všech tabulek
  Future<void> deleteAllTables() async {
    final db = await database;

    // Seznam názvů tabulek, které chceš smazat
    List<String> tables = [
      'android_metadata',
      'user_profile',
      'components',
      'activities',
      'offline_requests',
      'ranges',
      'cartridges',
      'calibers',
      'requests',
      'weapons'
    ];

    // Odstranění všech tabulek
    for (String table in tables) {
      try {
        await db.execute('DROP TABLE IF EXISTS $table');
        print("Tabulka '$table' byla úspěšně odstraněna.");
      } catch (e) {
        print("Chyba při odstraňování tabulky '$table': $e");
      }
    }
  }

  Future<void> addOfflineRequest(
    BuildContext context,
    String requestType,
    Map<String, dynamic> requestData,
  ) async {
    final db = await database;

    try {
      await db.insert(
        'offline_requests',
        {
          'request_type': requestType,
          'data':
              jsonEncode(requestData), // Použití jsonEncode pro správný JSON
          'status': 'pending',
        },
      );
      print('Požadavek typu $requestType byl přidán do offline_requests.');

      // Zavření dialogu (pokud je potřeba)
      Navigator.pop(context);
    } catch (e) {
      print('Chyba při přidávání offline požadavku: $e');
    }
  }

  Future<void> syncOfflineRequests(BuildContext context) async {
    final db = await database;

    // Načtení všech čekajících požadavků
    final requests = await db.query(
      'offline_requests',
      where: 'status = ?',
      whereArgs: ['pending'],
    );

    print("Synchronizuji ${requests.length} požadavků.");

    for (var request in requests) {
      final requestType = request['request_type'];
      final rawData = request['data'];

      try {
        // Kontrola, zda je rawData typu String
        if (rawData is String) {
          final requestData = jsonDecode(rawData); // Dekódování JSON

          switch (requestType) {
            case 'update_stock':
              // API volání pro synchronizaci zásoby
              await ApiService.syncRequest(
                '/cartridges/${requestData['id']}/update-stock',
                {'quantity': requestData['quantity']},
              );

              // Zobrazení úspěšného snackbaru
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "Synchronizace úspěšná: Náboj ID ${requestData['id']} "
                    "navýšen o ${requestData['quantity']}.",
                  ),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
              break;

            case 'create_activity':
              await ApiService.syncRequest('/activities', requestData);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Aktivita úspěšně synchronizována."),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
              break;

            case 'delete_activity':
              await ApiService.syncRequest(
                '/activities/${requestData['id']}/delete',
                {},
              );

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text("Aktivita ID ${requestData['id']} byla smazána."),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
              break;

            case 'create_shooting_log':
              print("Synchronizuji střelecký záznam: $requestData");
              await ApiService.syncRequest('/shooting_logs', requestData);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Střelecký záznam úspěšně synchronizován."),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
              break;

            default:
              print("Neznámý požadavek: $requestType");
              continue;
          }

          // Aktualizace statusu na "completed"
          await db.update(
            'offline_requests',
            {'status': 'completed'},
            where: 'id = ?',
            whereArgs: [request['id']],
          );
          print("Požadavek ID ${request['id']} synchronizován úspěšně.");
        } else {
          // Pokud rawData není typu String
          print("Neplatná data pro požadavek ID ${request['id']}: $rawData");
          await db.update(
            'offline_requests',
            {'status': 'failed'},
            where: 'id = ?',
            whereArgs: [request['id']],
          );
        }
      } catch (e) {
        print("Chyba při synchronizaci požadavku ID ${request['id']}: $e");

        // Aktualizace statusu na "failed"
        await db.update(
          'offline_requests',
          {'status': 'failed'},
          where: 'id = ?',
          whereArgs: [request['id']],
        );

        // Zobrazení chybového snackbaru
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Chyba při synchronizaci požadavku ID ${request['id']}: $e",
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> getDataById(String tableName, int id) async {
    final db = await database;
    final result = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<String>> _getTableColumns(String tableName) async {
    final db = await database;
    final List<Map<String, dynamic>> tableInfo =
        await db.rawQuery('PRAGMA table_info($tableName)');
    return tableInfo.map((column) => column['name'] as String).toList();
  }

  // Opravená metoda pro čištění dat
  Future<Map<String, dynamic>> cleanData(
      Map<String, dynamic> data, String table) async {
    try {
      // Získáme platné sloupce pro danou tabulku
      List<String> validColumns = await _getTableColumns(
          table); // Opraveno - předáváme pouze název tabulky

      // Vytvoříme novou mapu pro čištěná data
      Map<String, dynamic> cleanedData = {};

      // Projdeme všechna data a zachováme pouze platné sloupce
      data.forEach((key, value) {
        if (validColumns.contains(key)) {
          cleanedData[key] = value;
        }
      });

      return cleanedData;
    } catch (e) {
      print('Chyba při čištění dat pro tabulku $table: $e');
      return data; // V případě chyby vrátíme původní data
    }
  }

  Future<List<Map<String, dynamic>>> getFailedRequests() async {
    final db =
        await database; // Předpokládám, že máš metodu pro získání instance DB
    return await db.query('requests',
        where: 'status = ?',
        whereArgs: ['failed']); // Podle potřeby upravit dotaz
  }

  Future<Database> _initDatabase() async {
    try {
      final dbPath = await getDatabasesPath(); // Používáme getDatabasesPath()
      String fullDbPath = path.join(dbPath, 'reloading_tracker.db');
      print("Inicializuji databázi na cestě: $fullDbPath");

      bool databaseExists = await File(fullDbPath).exists();
      if (databaseExists) {
        print("Databáze již existuje na cestě: $fullDbPath");
      } else {
        print("Databáze neexistuje, bude vytvořena na cestě: $fullDbPath");
      }

      return await openDatabase(
        fullDbPath,
        version: 12,
        onOpen: (db) async {
          print("Databáze byla úspěšně otevřena: $fullDbPath");
          await createAllTables(db);
          await _debugDatabase(db);
        },
      );
    } catch (e) {
      print("Chyba při inicializaci databáze: $e");
      rethrow;
    }
  }

  Future<void> syncCalibersFromApi(List<dynamic> calibers) async {
    final db = await database;

    try {
      print("Začínám synchronizaci kalibrů...");

      await db.transaction((txn) async {
        print("Vyprázdňuji tabulku calibers...");
        await txn.delete('calibers');

        for (var caliber in calibers) {
          // Validace dat
          if (caliber['id'] == null || caliber['name'] == null) {
            print("Chyba: Neplatný kalibr $caliber - přeskočeno.");
            continue;
          }

          final cleanedCaliber = {
            'id': caliber['id'],
            'name': caliber['name'],
            'description': caliber['description'] ?? '',
            'bullet_diameter': caliber['bullet_diameter'] ?? '',
            'case_length': caliber['case_length'] ?? '',
            'max_pressure': caliber['max_pressure'] ?? '',
            'user_id': caliber['user_id'],
            'is_global': caliber['is_global'] ?? 0,
            'created_at': caliber['created_at'],
            'updated_at': caliber['updated_at'],
          };

          print("Vkládám kalibr do tabulky: $cleanedCaliber");

          // Vložení do tabulky calibers
          await txn.insert(
            'calibers',
            cleanedCaliber,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      print("Synchronizace kalibrů dokončena. Počet: ${calibers.length}");
    } catch (e) {
      print("Chyba při synchronizaci kalibrů: $e");
      rethrow;
    }
  }

  //Synchronizace střelnic z API
  Future<void> syncRangesFromApi(List<dynamic> ranges) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        print('Vymazávám tabulku ranges před synchronizací.');
        await txn.delete('ranges');

        for (var range in ranges) {
          final cleanedRange = {
            'id': range['id'],
            'name': range['name'],
            'location': range['location'] ?? '',
            'hourly_rate': range['hourly_rate'] != null
                ? double.tryParse(range['hourly_rate'].toString()) ?? 0.0
                : 0.0,
            'user_id': range['user_id'],
            'created_at': range['created_at'],
            'updated_at': range['updated_at'],
          };

          await txn.insert(
            'ranges',
            cleanedRange,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      print("Synchronizace střelnic dokončena. Počet: ${ranges.length}");
    } catch (e) {
      print("Chyba při synchronizaci střelnic: $e");
    }
  }

  Future<void> syncCartridgesFromApi(List<dynamic> cartridges) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        print('Vymazávám tabulku cartridges před synchronizací.');
        await txn.delete('cartridges');

        for (var cartridgeData in cartridges) {
          if (cartridgeData['id'] == null || cartridgeData['name'] == null) {
            print("Neplatný náboj: $cartridgeData - přeskočeno.");
            continue;
          }

          final caliberId =
              cartridgeData['caliber']?['id'] ?? cartridgeData['caliber_id'];
          final caliberName = cartridgeData['caliber']?['name'] ??
              cartridgeData['caliber_name'];

          // Extrakce dat o komponentách
          final bulletName =
              cartridgeData['bullet']?['name'] ?? cartridgeData['bullet_name'];
          final powderName =
              cartridgeData['powder']?['name'] ?? cartridgeData['powder_name'];
          final primerName =
              cartridgeData['primer']?['name'] ?? cartridgeData['primer_name'];

          final cartridgeMap = {
            'id': cartridgeData['id'],
            'name': cartridgeData['name'],
            'cartridge_type': cartridgeData['type'] ?? 'unknown',
            'caliber_id': caliberId,
            'caliber_name': caliberName,
            'stock_quantity': cartridgeData['stock_quantity'] ?? 0,
            'price': cartridgeData['price']?.toString() ?? '0',
            'manufacturer': cartridgeData['manufacturer'],
            'bullet_specification': cartridgeData['bullet_specification'],
            'bullet_name': bulletName, // Přidáno
            'bullet_weight_grains':
                cartridgeData['bullet']?['weight_grains']?.toString(),
            'powder_name': powderName, // Přidáno
            'powder_weight': cartridgeData['powder_weight']?.toString(),
            'primer_name': primerName, // Přidáno
            'velocity_ms': cartridgeData['velocity_ms']?.toString(),
            'standard_deviation':
                cartridgeData['standard_deviation']?.toString(),
            'oal': cartridgeData['oal']?.toString(),
            'barcode': cartridgeData['barcode'],
            'is_favorite': cartridgeData['is_favorite'] == true ? 1 : 0,
            'created_at': cartridgeData['created_at'],
            'updated_at': cartridgeData['updated_at'],
          };

          await txn.insert(
            'cartridges',
            cartridgeMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      print("Synchronizace nábojů dokončena. Počet: ${cartridges.length}");
    } catch (e) {
      print("Chyba při synchronizaci nábojů: $e");
      throw e;
    }
  }

  Future<String> _getCaliberNameById(Database db, int? caliberId) async {
    if (caliberId == null) return 'Neznámý kalibr';

    final result = await db.query(
      'calibers',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [caliberId],
    );

    if (result.isNotEmpty) {
      return result.first['name'] as String;
    } else {
      return 'Neznámý kalibr';
    }
  }

  Future<void> debugCartridgesAfterSync() async {
    final db = await database;

    try {
      print("=== DEBUG PO SYNCHRONIZACI CARTRIDGES ===");

      // Počet záznamů v tabulce cartridges
      final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM cartridges'));
      print("Počet záznamů v tabulce cartridges: $count");

      // Načtení prvních několika záznamů pro kontrolu
      final cartridges = await db.query('cartridges', limit: 5);
      cartridges.forEach((cartridge) {
        print("Náboj: $cartridge");
      });

      print("=========================================");
    } catch (e) {
      print("Chyba při debugování cartridges: $e");
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    print("Inicializuji databázi pro verzi $version...");
    try {
      await createAllTables(db);
      print("Tabulky byly úspěšně vytvořeny.");
    } catch (e) {
      print("Chyba při inicializaci databáze: $e");
      rethrow;
    }
  }

  Future<void> _debugDatabase(Database db) async {
    try {
      // Kontrola verze
      var version = await db.getVersion();
      print('\n=== DEBUG INFORMACE ===');
      print('Verze databáze: $version');

      // Výpis všech tabulek a jejich struktury
      var tables = await db
          .rawQuery('SELECT name FROM sqlite_master WHERE type = "table"');
      print('\nExistující tabulky:');
      for (var table in tables) {
        String tableName = table['name'] as String;
        print('\n- $tableName:');

        var columns = await db.rawQuery('PRAGMA table_info($tableName)');
        print('  Sloupce:');
        for (var column in columns) {
          print('    - ${column['name']} (${column['type']})');
        }

        // Počet záznamů v tabulce
        var count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $tableName'));
        print('  Počet záznamů: $count');
      }
      print('\n=====================\n');
    } catch (e) {
      print('Chyba při debugování databáze: $e');
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print("Aktualizuji databázi z verze $oldVersion na verzi $newVersion...");
    try {
      if (oldVersion < 10) {
        // Pro verzi 9 provedeme změny schématu
        // Můžete buď přidat sloupec 'type', nebo smazat a znovu vytvořit tabulku
        await db.execute('DROP TABLE IF EXISTS cartridges');
        await createAllTables(db);
        print("Tabulka cartridges byla aktualizována.");
      }
      // Další migrace pro vyšší verze můžete přidat zde
    } catch (e) {
      print("Chyba při aktualizaci databáze: $e");
      rethrow;
    }
  }

  Future<int> insertOrUpdate(String table, Map<String, dynamic> data) async {
    final db = await database;

    try {
      // Definice platných sloupců pro danou tabulku
      List<String> validColumns = await _getTableColumns(table);

      // Vytvoříme novou mapu pro čištěná data
      Map<String, dynamic> cleanedData = {};

      data.forEach((key, value) {
        if (validColumns.contains(key) && value is! Map && value is! List) {
          // Ošetření null hodnot
          cleanedData[key] = value ?? _getDefaultValueForColumn(key);
        }
      });

      if (!cleanedData.containsKey('id') || cleanedData['id'] == null) {
        print(
            'Chyba: ID není definováno pro tabulku $table. Data: $cleanedData');
        throw Exception('ID must be defined for insert or update operations.');
      }

      final existing = await db.query(
        table,
        where: 'id = ?',
        whereArgs: [cleanedData['id']],
      );

      if (existing.isEmpty) {
        print('Vkládám nový záznam do tabulky $table: $cleanedData');
        return await db.insert(table, cleanedData);
      } else {
        print('Aktualizuji záznam v tabulce $table: $cleanedData');
        return await db.update(
          table,
          cleanedData,
          where: 'id = ?',
          whereArgs: [cleanedData['id']],
        );
      }
    } catch (e) {
      print('Chyba při vkládání/aktualizaci do tabulky $table: $e');
      rethrow;
    }
  }

// Funkce pro získání platných sloupců tabulky
  Future<List<Map<String, dynamic>>> fetchCartridgesFromSQLite() async {
    final db = await database;

    final cartridges = await db.rawQuery('''
    SELECT * FROM cartridges
  ''');

    List<Map<String, dynamic>> validatedCartridges = [];
    for (var cartridge in cartridges) {
      try {
        final Map<String, dynamic> mutableCartridge =
            Map<String, dynamic>.from(cartridge);

        // Zachování typu náboje z databáze
        final cartridgeType = mutableCartridge['cartridge_type'];
        print(
            'Debug: Načítám náboj ${mutableCartridge['name']}, typ v DB: $cartridgeType');

        validatedCartridges.add({
          'id': mutableCartridge['id'],
          'name': mutableCartridge['name'] ?? 'Neznámý název',
          'cartridge_type':
              cartridgeType, // Upraveno z 'type' na 'cartridge_type'
          'caliber_name': mutableCartridge['caliber_name'] ?? 'Neznámý kalibr',
          'stock_quantity': int.tryParse(
                  mutableCartridge['stock_quantity']?.toString() ?? '0') ??
              0,
          'price':
              double.tryParse(mutableCartridge['price']?.toString() ?? '0') ??
                  0.0,

          // Tovární náboje
          'manufacturer': mutableCartridge['manufacturer'],
          'bullet_specification': mutableCartridge['bullet_specification'],

          // Přebíjené náboje
          'bullet_name': mutableCartridge['bullet_name'],
          'powder_name': mutableCartridge['powder_name'],
          'powder_weight': mutableCartridge['powder_weight'],
          'primer_name': mutableCartridge['primer_name'],
          'oal': mutableCartridge['oal'],
          'velocity_ms': mutableCartridge['velocity_ms'],

          'barcode': mutableCartridge['barcode'],
          'is_favorite': mutableCartridge['is_favorite'] == 1,
        });
      } catch (e) {
        print('Chyba při zpracování náboje ID ${cartridge['id']}: $e');
      }
    }

    return validatedCartridges;
  }

// Pomocné funkce pro bezpečné parsování
  int _parseIntSafely(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  double _parseDoubleSafely(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  List<Map<String, dynamic>> applyFilter(
      List<Map<String, dynamic>> cartridges) {
    print("=== Debug dat před filtrem ===");
    for (var cartridge in cartridges) {
      print(
          "Náboj: ${cartridge['name']}, stock_quantity=${cartridge['stock_quantity']}, cartridge_type=${cartridge['cartridge_type']}");
    }

    final filtered = cartridges.where((cartridge) {
      return cartridge['stock_quantity'] != null &&
          cartridge['stock_quantity'] > 0;
    }).toList();

    print("=== Debug dat po filtru ===");
    for (var cartridge in filtered) {
      print(
          "Náboj: ${cartridge['name']}, stock_quantity=${cartridge['stock_quantity']}, cartridge_type=${cartridge['cartridge_type']}");
    }

    return filtered;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchCartridges() async {
    try {
      // Fetch data from SQLite or any other source
      final cartridges = await DatabaseHelper().fetchCartridgesFromSQLite();

      // Pokud potřebujete další úpravy nebo čištění dat, můžete je provést zde

      final factory = cartridges
          .where((cartridge) => cartridge['cartridge_type'] == 'factory')
          .toList();
      final reload = cartridges
          .where((cartridge) => cartridge['cartridge_type'] == 'reload')
          .toList();

      return {
        'factory': factory,
        'reload': reload,
      };
    } catch (e) {
      print('Error fetching cartridges: $e');
      return {
        'factory': [],
        'reload': [],
      };
    }
  }

  Future<bool> checkConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult == ConnectivityResult.mobile ||
        connectivityResult == ConnectivityResult.wifi;
  }

  Future<void> syncCartridgesWithApi() async {
    try {
      // Kontrola připojení k internetu
      final isOnline = await checkConnection();

      if (isOnline) {
        print("Synchronizace dat z API...");

        // Načti data z API
        final apiData = await ApiService.getAllCartridges();

        // Synchronizace dat s SQLite
        await syncCartridgesFromApi(
            [...?apiData['factory'], ...?apiData['reload']]);

        // Debug informace
        await debugCartridgeSync();
      } else {
        print("Offline režim, synchronizace přeskočena.");
      }
    } catch (e) {
      print("Chyba při synchronizaci nábojů: $e");
    }
  }

  Future<void> debugCartridgeSync() async {
    final db = await database;

    try {
      print("=== DEBUG SYNCHRONIZACE CARTRIDGES ===");

      // Počet záznamů v tabulce cartridges
      final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM cartridges'));
      print("Počet záznamů v tabulce cartridges: $count");

      // Načtení prvních záznamů pro kontrolu
      final cartridges = await db.query('cartridges', limit: 5);
      cartridges.forEach((cartridge) {
        print("Náboj: $cartridge");
      });

      print("=====================================");
    } catch (e) {
      print("Chyba při debugování synchronizace nábojů: $e");
    }
  }

// Funkce pro výchozí hodnoty sloupců
  dynamic _getDefaultValueForColumn(String columnName) {
    // Zde můžete definovat výchozí hodnoty pro konkrétní sloupce
    // Například:
    if (columnName == 'name' ||
        columnName == 'description' ||
        columnName ==
            'cartridge_type' || // Změněno z 'type' na 'cartridge_type'
        columnName == 'manufacturer' ||
        columnName == 'bullet_specification' ||
        columnName == 'barcode') {
      return '';
    } else if (columnName == 'price' ||
        columnName == 'powder_weight' ||
        columnName == 'velocity_ms' ||
        columnName == 'oal' ||
        columnName == 'standard_deviation') {
      return 0.0;
    } else if (columnName == 'is_public' ||
        columnName == 'stock_quantity' ||
        columnName == 'is_favorite' ||
        columnName == 'total_upvotes' ||
        columnName == 'total_downvotes' ||
        columnName == 'package_size') {
      return 0;
    } else {
      return null; // Pro ostatní sloupce ponecháme null
    }
  }

  // Funkce pro výchozí hodnoty
  dynamic _getDefaultValueForType(value) {
    if (value is String) return '';
    if (value is int) return 0;
    if (value is double) return 0.0;
    if (value is bool) return false;
    return ''; // Pro jiné typy
  }

  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(table, data);
  }

  Future<int> update(String table, Map<String, dynamic> data, String where,
      List<dynamic> whereArgs) async {
    final db = await database;
    return await db.update(table, data, where: where, whereArgs: whereArgs);
  }

  Future<List<Map<String, dynamic>>> getData(String tableName) async {
    final db = await database;
    final data = await db.query(tableName);

    print(
        "Data z tabulky $tableName: ${data.map((e) => e.toString()).join('\n')}"); // Debug
    return data;
  }

  Future<int> delete(
      String table, String where, List<dynamic> whereArgs) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> deleteDatabase() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      String dbPath = path.join(directory.path,
          'reloading_tracker.db'); // Použití 'path.join' a přejmenování proměnné

      // Smazání databáze
      await sqflite.deleteDatabase(dbPath);
      print("Databázový soubor byl smazán: $dbPath");
      _database = null;
    } catch (e) {
      print("Chyba při mazání databáze: $e");
      rethrow;
    }
  }
}
