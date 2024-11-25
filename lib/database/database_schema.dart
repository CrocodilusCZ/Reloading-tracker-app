import 'package:sqflite/sqflite.dart';

class DatabaseSchema {
  static Future<void> createTables(Database db) async {
    // Add static and underscore
    print("Začínám vytvářet tabulky...");
    try {
      await db.execute('''CREATE TABLE IF NOT EXISTS user_profile (
        id INTEGER PRIMARY KEY,
        name TEXT,
        email TEXT,
        last_sync DATETIME
      )''');
      print("Tabulka user_profile vytvořena.");

      await db.execute('''CREATE TABLE IF NOT EXISTS components (
        id INTEGER PRIMARY KEY,
        name TEXT,
        type TEXT,
        quantity INTEGER
      )''');
      print("Tabulka components vytvořena.");

      await db.execute('''CREATE TABLE IF NOT EXISTS activities (
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        activity_name TEXT NOT NULL,
        note TEXT,
        created_at DATETIME,
        updated_at DATETIME,
        is_global INTEGER,
        date DATETIME
      )''');
      print("Tabulka activities vytvořena.");

      await db.execute('''CREATE TABLE IF NOT EXISTS offline_requests (
        id INTEGER PRIMARY KEY,
        request_type TEXT,
        data TEXT,
        status TEXT
      )''');
      print("Tabulka offline_requests vytvořena.");

      await db.execute('''CREATE TABLE IF NOT EXISTS ranges (
        id INTEGER PRIMARY KEY,
        name TEXT,
        location TEXT,
        hourly_rate REAL,
        user_id INTEGER,
        created_at DATETIME,
        updated_at DATETIME
      )''');
      print("Tabulka ranges vytvořena.");

      await db.execute('''CREATE TABLE IF NOT EXISTS cartridges (
        id INTEGER PRIMARY KEY,
        load_step_id INTEGER NULL,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT NULL,
        is_public INTEGER DEFAULT 0,
        bullet_id INTEGER NULL,
        primer_id INTEGER NULL,
        powder_weight REAL NULL,
        stock_quantity INTEGER DEFAULT 0,
        brass_id INTEGER NULL,
        velocity_ms REAL NULL,
        oal REAL NULL,
        standard_deviation REAL NULL,
        is_favorite INTEGER DEFAULT 0,
        price REAL NULL,
        caliber_id INTEGER NULL,
        powder_id INTEGER NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        type TEXT NULL,
        manufacturer TEXT NULL,
        bullet_specification TEXT NULL,
        total_upvotes INTEGER DEFAULT 0,
        total_downvotes INTEGER DEFAULT 0,
        barcode TEXT NULL,
        package_size INTEGER NULL
      )''');
      print("Tabulka cartridges vytvořena.");

      await db.execute('''CREATE TABLE IF NOT EXISTS calibers (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        bullet_diameter TEXT,
        case_length TEXT,
        max_pressure TEXT,
        user_id INTEGER,
        is_global INTEGER DEFAULT 0,
        created_at DATETIME,
        updated_at DATETIME
    )''');
      print("Tabulka calibers vytvořena.");

      await db.execute('''CREATE TABLE IF NOT EXISTS weapons (
        id INTEGER PRIMARY KEY,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        created_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL,
        initial_shots INTEGER DEFAULT 0
      )''');
      print("Tabulka weapons vytvořena.");

      // Nová tabulka pro vztah mezi zbraněmi a kalibry
      await db.execute('''CREATE TABLE IF NOT EXISTS weapon_calibers (
        weapon_id INTEGER NOT NULL,
        caliber_id INTEGER NOT NULL,
        PRIMARY KEY (weapon_id, caliber_id),
        FOREIGN KEY (weapon_id) REFERENCES weapons (id),
        FOREIGN KEY (caliber_id) REFERENCES calibers (id)
      )''');
      print("Tabulka weapon_calibers vytvořena.");

      await db.execute('''CREATE TABLE IF NOT EXISTS requests (
        id INTEGER PRIMARY KEY,
        request_type TEXT,
        data TEXT,
        status TEXT
      )''');
      print("Tabulka requests vytvořena.");
    } catch (e) {
      print("Chyba při vytváření tabulek: $e");
      rethrow;
    }
    print("Všechny tabulky byly zkontrolovány/vytvořeny.");
  }
}
