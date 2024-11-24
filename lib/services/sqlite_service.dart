import 'package:sqflite/sqflite.dart';
import 'package:shooting_companion/helpers/database_helper.dart';

class SQLiteService {
  static Future<List<Map<String, dynamic>>> getWeaponsByCaliber(
      int caliberId) async {
    final db =
        await DatabaseHelper().database; // Používáme instanci DatabaseHelper

    // Správný SQL dotaz s JOIN na `weapon_calibers` a `calibers`
    final result = await db.rawQuery('''
    SELECT 
      weapons.id AS weapon_id,
      weapons.name AS weapon_name,
      calibers.id AS caliber_id,
      calibers.name AS caliber_name
    FROM weapons
    JOIN weapon_calibers ON weapons.id = weapon_calibers.weapon_id
    JOIN calibers ON weapon_calibers.caliber_id = calibers.id
    WHERE calibers.id = ?
  ''', [caliberId]);

    if (result.isEmpty) {
      print('Debug: Žádné zbraně nenalezeny pro caliberId=$caliberId');
    } else {
      print('Debug: Výsledek dotazu pro caliberId=$caliberId: $result');
    }

    return result;
  }

  static Future<List<Map<String, dynamic>>> getUserActivities() async {
    final db = await openDatabase('app_database.db');
    return await db.query('activities');
  }

  // Přidání metody pro načtení cartridge podle ID
  static Future<Map<String, dynamic>?> getCartridgeById(int id) async {
    final db = await DatabaseHelper().database; // Otevře SQLite databázi
    final result = await db.query(
      'cartridges', // Název tabulky
      where: 'id = ?', // Filtr na základě ID
      whereArgs: [id], // Hodnota pro nahrazení otazníku
    );

    if (result.isNotEmpty) {
      return result.first; // Vrátí první nalezený záznam
    } else {
      return null; // Vrátí null, pokud žádný záznam neexistuje
    }
  }
}
