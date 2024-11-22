import 'package:shooting_companion/services/api_service.dart';
import 'package:shooting_companion/helpers/database_helper.dart';

class WeaponService {
  // Metoda pro načtení zbraní dle kalibru
  static Future<List<Map<String, dynamic>>> fetchWeaponsByCaliber(
      int caliberId) async {
    print('Načítám zbraně pro kalibr ID: $caliberId');

    bool isOnline = await ApiService.isOnline(); // Zjištění online režimu

    if (isOnline) {
      try {
        // Pokus o načtení zbraní z API
        print('Pokouším se načíst zbraně online...');
        final weapons = await ApiService.getUserWeaponsByCaliber(caliberId);
        print('Načtené zbraně z API: $weapons');

        // Uložení zbraní do offline databáze
        await DatabaseHelper().saveWeapons(
          weapons.map((weapon) => weapon as Map<String, dynamic>).toList(),
        );
        print('Zbraně byly uloženy do offline databáze.');

        return weapons.cast<Map<String, dynamic>>();
      } catch (e) {
        print('Chyba při online načítání: $e. Přecházím na offline režim.');
      }
    }

    // Fallback: Načtení z offline databáze
    try {
      print('Načítám zbraně z offline databáze...');
      final localWeapons =
          await DatabaseHelper.getWeapons(caliberId: caliberId);
      print('Načtené zbraně z offline databáze: $localWeapons');
      return localWeapons;
    } catch (e) {
      print('Chyba při načítání zbraní z offline databáze: $e');
      return [];
    }
  }
}
