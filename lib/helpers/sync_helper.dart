import 'dart:convert';
import 'package:shooting_companion/helpers/database_helper.dart';

import 'package:shooting_companion/helpers/connectivity_helper.dart';

Future<void> syncData() async {
  bool online = await isOnline();

  if (online) {
    // Pokud je připojení k internetu, synchronizujeme data
    print("Jsi online, synchronizujeme data...");
    await syncOfflineDataToServer();
  } else {
    // Pokud není připojení k internetu, data jsou uložená offline
    print("Jsi offline, data budou synchronizována později.");
  }
}

Future<void> syncOfflineDataToServer() async {
  final db = DatabaseHelper();

  // Získání všech čekajících požadavků na server
  List<Map<String, dynamic>> offlineRequests =
      await db.getData('offline_requests');

  for (var request in offlineRequests) {
    bool success = await sendToServer(request['data']);

    // Pokud se odeslání podaří, aktualizujeme status na 'sent'
    if (success) {
      await db.update(
          'offline_requests', {'status': 'sent'}, 'id = ?', [request['id']]);
    } else {
      // Pokud odeslání selže, nastavíme status na 'failed'
      await db.update(
          'offline_requests', {'status': 'failed'}, 'id = ?', [request['id']]);
    }
  }
}

Future<bool> sendToServer(String data) async {
  // Tento kód bude sloužit k odeslání dat na server (např. HTTP POST request)
  // Tady použij API pro synchronizaci s tvým backendem
  // Pokud se odeslání podaří, vrátí true, jinak false
  print("Odesílám data na server: $data");
  // Simulace úspěšného odeslání
  return true;
}

Future<void> saveOfflineRequest(
    String requestType, Map<String, dynamic> data) async {
  final db = DatabaseHelper();

  Map<String, dynamic> offlineRequestData = {
    'request_type': requestType,
    'data': json.encode(data), // Uložení dat jako JSON
    'status': 'pending',
  };

  // Uložení požadavku do databáze
  await db.insert('offline_requests', offlineRequestData);
}
