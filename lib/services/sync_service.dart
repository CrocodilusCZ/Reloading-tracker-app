import 'dart:convert';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:shooting_companion/helpers/snackbar_helper.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:flutter/material.dart';

class SyncService {
  final BuildContext context;

  SyncService(this.context);

  // Synchronizace dat po přihlášení uživatele
// Tato metoda kombinuje dvě různé operace:
// 1. Synchronizaci dat s API (stahování dat z API do SQLite).
// 2. Zpracování neodeslaných požadavků uložených offline.
  Future<void> _syncDataAfterLogin() async {
    try {
      // Nejprve synchronizujeme aktuální data z API
      await syncWithApi();
    } catch (e) {
      // Pokud dojde k chybě při synchronizaci s API, informujeme uživatele
      SnackbarHelper.show(context, 'Chyba při synchronizaci s API: $e');
    }

    // Poté zpracujeme všechny neodeslané požadavky uložené offline
    // Tato část se provede bez ohledu na výsledek předchozí synchronizace API
    await syncOfflineRequests();
  }

  // Synchronizace s API
  Future<void> syncWithApi() async {
    try {
      print('Synchronizace: Začínám synchronizaci všech dat.');

      final dbHelper = DatabaseHelper();

      // Synchronizace střelnic
      await _syncRanges(dbHelper);

      // Synchronizace nábojů
      await _syncCartridges(dbHelper);

      // Synchronizace kalibrů
      await _syncCalibers(dbHelper);

      // Synchronizace aktivit
      await _syncActivities(dbHelper);

      // Synchronizace zbraní
      await _syncWeapons(dbHelper);

      print('Synchronizace všech dat dokončena.');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data byla úspěšně synchronizována.')));
    } catch (e) {
      print('Chyba při synchronizaci všech dat: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Chyba při synchronizaci: $e')));
    }
  }

  // Synchronizace kalibrů
  Future<void> _syncCalibers(DatabaseHelper dbHelper) async {
    try {
      print('Synchronizuji kalibry...');
      final calibers = await ApiService.getCalibers();
      await dbHelper.syncCalibersFromApi(calibers);
      print('Kalibry uloženy do SQLite.');
    } catch (e) {
      print('Chyba při synchronizaci kalibrů: $e');
    }
  }

  // Synchronizace střelnic
  Future<void> _syncRanges(DatabaseHelper dbHelper) async {
    try {
      print('Synchronizuji střelnice...');
      final ranges = await ApiService.getUserRanges();
      await dbHelper.syncRangesFromApi(ranges);
      print('Střelnice uloženy do SQLite.');
    } catch (e) {
      print('Chyba při synchronizaci střelnic: $e');
    }
  }

  // Synchronizace nábojů
  Future<void> _syncCartridges(DatabaseHelper dbHelper) async {
    try {
      print('Synchronizuji náboje...');
      final cartridges = await ApiService.getAllCartridges();
      await dbHelper.syncCartridgesFromApi(
          [...?cartridges['factory'], ...?cartridges['reload']]);
      print('Náboje uloženy do SQLite.');
    } catch (e) {
      print('Chyba při synchronizaci nábojů: $e');
    }
  }

  // Synchronizace aktivit
  Future<void> _syncActivities(DatabaseHelper dbHelper) async {
    try {
      print('Synchronizuji aktivity...');
      final activities = await ApiService.getUserActivities();
      for (var activity in activities) {
        await dbHelper.insertOrUpdate('activities', activity);
      }
      print('Aktivity uloženy do SQLite.');
    } catch (e) {
      print('Chyba při synchronizaci aktivit: $e');
    }
  }

  // Synchronizace zbraní
  Future<void> _syncWeapons(DatabaseHelper dbHelper) async {
    try {
      print('Synchronizuji zbraně...');
      final weapons = await ApiService.getUserWeapons();
      await dbHelper.saveWeapons(
        weapons.map((weapon) => weapon as Map<String, dynamic>).toList(),
      );
      print('Zbraně uloženy do SQLite.');
    } catch (e) {
      print('Chyba při synchronizaci zbraní: $e');
    }
  }

  // Synchronizace neodeslaných požadavků
  Future<void> syncOfflineRequests() async {
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
}
