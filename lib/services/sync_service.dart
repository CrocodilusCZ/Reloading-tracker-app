import 'dart:convert';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:shooting_companion/helpers/snackbar_helper.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:flutter/material.dart';

class SyncService {
  final BuildContext context;

  SyncService(this.context);

  void handleOnlineStateChange(bool isOnline) {
    if (isOnline) {
      print('Připojení obnoveno, spouštím synchronizaci...');
      syncOfflineRequests().then((_) {
        print('Synchronizace dokončena');
      }).catchError((error) {
        print('Chyba při synchronizaci: $error');
      });
    }
  }

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

      await _syncTargetPhotos(dbHelper);

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

  Future<void> _syncTargetPhotos(DatabaseHelper dbHelper) async {
    try {
      print('Synchronizuji fotky terčů...');
      final unsyncedPhotos = await dbHelper.getUnsyncedPhotos();

      for (var photo in unsyncedPhotos) {
        try {
          await ApiService.uploadTargetPhoto({
            'photo_path': photo.photoPath,
            'note': photo.note,
            'created_at': photo.createdAt.toIso8601String()
          });

          await dbHelper.markPhotoAsSynced(photo.id);
          print('Foto terče ID ${photo.id} úspěšně synchronizováno.');
        } catch (e) {
          print('Chyba při synchronizaci fota terče ID ${photo.id}: $e');
        }
      }
      print('Synchronizace fotek terčů dokončena.');
    } catch (e) {
      print('Chyba při synchronizaci fotek terčů: $e');
    }
  }

  // Synchronizace neodeslaných požadavků
  Future<void> syncOfflineRequests() async {
    final db = await DatabaseHelper().database;
    print('Začínám synchronizaci offline požadavků...');

    final requests = await db.query(
      'offline_requests',
      where: 'status = ?',
      whereArgs: ['pending'],
    );

    int syncedCount = 0;
    Map<String, int> syncedTypes = {};

    print('Načteno ${requests.length} offline požadavků k synchronizaci.');

    for (var request in requests) {
      final requestType = request['request_type'];
      final rawData = request['data'];

      if (rawData is! String) {
        print('Chyba: Hodnota dat v požadavku není typu String: $rawData');
        continue;
      }

      try {
        final requestData = jsonDecode(rawData);
        print(
            'Synchronizuji požadavek ID ${request['id']} typu $requestType s daty: $requestData');

        // Process request based on type
        switch (requestType) {
          case 'update_stock':
            await ApiService.syncRequest(
              '/cartridges/${requestData['id']}/update-stock',
              {'quantity': requestData['quantity']},
            );
            break;

          case 'create_activity':
            await ApiService.syncRequest('/activities', requestData);
            break;

          case 'delete_activity':
            await ApiService.syncRequest(
              '/activities/${requestData['id']}/delete',
              {},
            );
            break;

          case 'create_shooting_log':
            await ApiService.syncRequest('/shooting-logs', requestData);
            break;

          case 'upload_target_photo':
            await ApiService.syncRequest(
              '/cartridges/${requestData['cartridge_id']}/targets',
              requestData,
            );
            break;

          default:
            print('Neznámý typ požadavku: $requestType');
            continue;
        }

        // After successful API call, update DB status
        await db.update(
          'offline_requests',
          {'status': 'completed'},
          where: 'id = ?',
          whereArgs: [request['id']],
        );

        // Only after DB update, increment counters
        syncedCount++;
        String type = request['request_type'] as String;
        syncedTypes[type] = (syncedTypes[type] ?? 0) + 1;

        print('Požadavek ID ${request['id']} byl synchronizován úspěšně.');
      } catch (e) {
        print('Chyba při synchronizaci požadavku ID ${request['id']}: $e');
      }
    }

    if (syncedCount > 0) {
      String details = syncedTypes.entries
          .map((e) => '${e.value}x ${_getReadableType(e.key)}')
          .join(', ');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          duration: Duration(seconds: 4),
          content: Row(
            children: [
              AnimatedRotation(
                turns: 1,
                duration: Duration(milliseconds: 500),
                child: Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Synchronizace dokončena\n$details',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: EdgeInsets.all(8),
        ),
      );
    }
  }

  String _getReadableType(String type) {
    switch (type) {
      case 'upload_target_photo':
        return 'fotka terče';
      case 'update_stock':
        return 'aktualizace skladu';
      case 'create_activity':
        return 'aktivita';
      default:
        return type;
    }
  }
}
