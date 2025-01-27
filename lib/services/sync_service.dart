import 'dart:convert';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:shooting_companion/helpers/snackbar_helper.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:flutter/material.dart';

class SyncService {
  final BuildContext context;
  final VoidCallback onSyncComplete;
  bool _isSynchronizing = false;
  bool _isSyncingOfflineRequests = false;

  SyncService(this.context, {required this.onSyncComplete});

  void handleOnlineStateChange(bool isOnline) {
    if (isOnline && !_isSynchronizing && !_isSyncingOfflineRequests) {
      print('Připojení obnoveno, spouštím synchronizaci...');
      syncOfflineRequests().then((_) {
        return syncWithApi();
      }).then((_) {
        print('Kompletní synchronizace dokončena');
        onSyncComplete(); // Zavolá _updatePendingRequestsCount v DashboardScreen
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
    if (_isSynchronizing) {
      print('Synchronizace již probíhá, přeskakuji...');
      return;
    }

    _isSynchronizing = true;
    final dbHelper = DatabaseHelper();

    try {
      print('Synchronizace: Začínám synchronizaci všech dat.');

      // Seznam synchronizačních operací
      final syncOperations = [
        _syncUserProfile(dbHelper),
        _syncRanges(dbHelper),
        _syncCartridges(dbHelper),
        _syncCalibers(dbHelper),
        _syncActivities(dbHelper),
        _syncWeapons(dbHelper),
        _syncTargetPhotos(dbHelper),
      ];

      // Provedení všech synchronizací
      await Future.wait(syncOperations);

      print('Synchronizace všech dat dokončena.');
      _showSuccessMessage('Data byla úspěšně synchronizována');
    } catch (e) {
      print('Chyba při synchronizaci všech dat: $e');
      _showErrorMessage('Chyba při synchronizaci: $e');
    } finally {
      _isSynchronizing = false;
    }
  }

// Helper metody pro notifikace
  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  // Synchronizace uživatelského profilu
  Future<void> _syncUserProfile(DatabaseHelper dbHelper) async {
    try {
      print('Synchronizuji uživatelský profil...');
      final profileData =
          await ApiService.getUserProfile(); // Musí se přidat do ApiService
      await dbHelper.insertOrUpdate('user_profile', profileData);
      print('Uživatelský profil uložen do SQLite.');
    } catch (e) {
      print('Chyba při synchronizaci profilu: $e');
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
      print('Starting target photos sync...');
      final unsyncedPhotos = await dbHelper.getUnsyncedPhotos();
      print('Found ${unsyncedPhotos.length} unsynced photos');

      for (var photo in unsyncedPhotos) {
        try {
          print('Processing photo ID: ${photo['id']}');

          // Prepare request data
          final requestData = {
            'photo_path': photo['photo_path'],
            'notes': photo['note'],
            'created_at': photo['created_at'],
            'cartridge_id': photo['cartridge_id'].toString(),
          };

          // Add optional fields if present
          if (photo['weapon_id'] != null) {
            requestData['weapon_id'] = photo['weapon_id'];
          }
          if (photo['distance'] != null) {
            requestData['distance'] = photo['distance'];
          }
          if (photo['moa_data'] != null) {
            requestData['moa_data'] = photo['moa_data'];
          }

          print('Uploading photo with data: $requestData');
          await ApiService.uploadTargetPhoto(requestData);

          // Mark as synced only after successful upload
          await dbHelper.markPhotoAsSynced(photo['id'] as int);
          print('Successfully synced photo ID: ${photo['id']}');
        } catch (e, stackTrace) {
          print('Error syncing photo ID ${photo['id']}: $e');
          print('Stack trace: $stackTrace');
        }
      }
      print('Target photos sync completed');
    } catch (e, stackTrace) {
      print('Error in target photos sync process: $e');
      print('Stack trace: $stackTrace');
    }
  }

  // Synchronizace neodeslaných požadavků
  Future<void> syncOfflineRequests() async {
    if (_isSyncingOfflineRequests) {
      print('Synchronizace offline požadavků již probíhá, přeskakuji...');
      return;
    }

    _isSyncingOfflineRequests = true;
    final db = await DatabaseHelper().database;

    try {
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
              'Synchronizuji požadavek ID ${request['id']} typu $requestType');

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

            case 'create_factory_cartridge':
              await ApiService.createFactoryCartridge(requestData);
              break;

            default:
              print('Neznámý typ požadavku: $requestType');
              continue;
          }

          await db.update(
            'offline_requests',
            {'status': 'completed'},
            where: 'id = ?',
            whereArgs: [request['id']],
          );

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
    } catch (e) {
      print('Chyba při synchronizaci offline požadavků: $e');
    } finally {
      _isSyncingOfflineRequests = false;
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
