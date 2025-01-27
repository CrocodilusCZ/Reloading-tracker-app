import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'package:shooting_companion/screens/cartridge_detail_screen.dart';
import 'package:shooting_companion/screens/shooting_log_screen.dart';
import 'package:shooting_companion/screens/target_photo_screen.dart';
import 'package:shooting_companion/screens/barcode_scanner_screen.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class FilterOptions {
  String? weaponName;
  String? cartridgeName;
  String? rangeName;
  DateTime? dateFrom;
  DateTime? dateTo;
  String sortOrder = 'newest'; // Add this line

  bool get hasFilters =>
      weaponName != null ||
      cartridgeName != null ||
      rangeName != null ||
      dateFrom != null ||
      dateTo != null;

  void reset() {
    weaponName = null;
    cartridgeName = null;
    rangeName = null;
    dateFrom = null;
    dateTo = null;
    sortOrder = 'newest'; // Add this line
  }
}

class ShootingLogsOverviewScreen extends StatefulWidget {
  const ShootingLogsOverviewScreen({super.key});

  @override
  State<ShootingLogsOverviewScreen> createState() =>
      _ShootingLogsOverviewScreenState();
}

class _ShootingLogsOverviewScreenState
    extends State<ShootingLogsOverviewScreen> {
  final filterOptions = FilterOptions();
  List<dynamic> logs = [];
  List<dynamic> targets = [];
  bool isLoading = true;
  bool showTargets = false;
  String selectedSort = 'newest';
  List<Map<String, dynamic>> activities = [];
  static const String _targetsKey = 'cached_targets';
  static const String _targetsCacheTimeKey = 'targets_cache_time';
  static const Duration _cacheValidity = Duration(days: 7);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool clearCache = false}) async {
    setState(() => isLoading = true);
    try {
      if (clearCache && showTargets) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_targetsKey);
      }

      final dbHelper = DatabaseHelper();
      activities = await dbHelper.getData('activities');
      await Future.wait([
        _loadLogs(),
        _loadTargets(),
      ]);
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _debugLoadTiming() async {
    final stopwatch = Stopwatch()..start();
    await _loadTargets();
    print('First load took: ${stopwatch.elapsedMilliseconds}ms');

    stopwatch.reset();
    await _loadTargets();
    print('Second load took: ${stopwatch.elapsedMilliseconds}ms');
  }

  Future<void> _addNewTarget(Map<String, dynamic> target) async {
    final prefs = await SharedPreferences.getInstance();

    // Clear cache to force reload from API
    await prefs.remove(_targetsKey);
    await prefs.remove(_targetsCacheTimeKey);

    // Force reload targets from API
    await _loadTargets();
  }

  Future<void> _loadTargets({bool forceRefresh = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Kontrola cache pouze pokud není vynucený refresh
      if (!forceRefresh) {
        final cachedData = prefs.getString(_targetsKey);
        final cacheTimeStr = prefs.getString(_targetsCacheTimeKey);

        if (cachedData != null && cacheTimeStr != null) {
          final cacheTime = DateTime.parse(cacheTimeStr);
          if (DateTime.now().difference(cacheTime) < _cacheValidity) {
            setState(() => targets = json.decode(cachedData));
            print('Using cached targets');
            return;
          }
        }
      }

      print('Loading targets from API...');
      final data = await ApiService.getTargets();
      if (!mounted) return;

      setState(() => targets = data);

      // Aktualizovat cache
      await prefs.setString(_targetsKey, json.encode(data));
      await prefs.setString(
          _targetsCacheTimeKey, DateTime.now().toIso8601String());
      print('Cache updated');
    } catch (e) {
      print('Error: $e');
      _showError('Nepodařilo se načíst terče: $e');
    }
  }

  Future<void> _showEntryTypeSelection() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jak chcete přidat záznam?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.security),
              title: const Text('Začít výběrem zbraně'),
              subtitle: const Text('Vyberte zbraň a pak kompatibilní náboj'),
              onTap: () {
                Navigator.pop(context);
                _showWeaponFirstFlow();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.track_changes),
              title: const Text('Začít výběrem náboje'),
              subtitle: const Text('Vyberte náboj a pak kompatibilní zbraň'),
              onTap: () {
                Navigator.pop(context);
                _showCartridgeSelectionDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWeaponFirstFlow() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      // Update weapons query to include calibers
      final weapons = await db.rawQuery('''
      SELECT 
        w.id,
        w.name,
        GROUP_CONCAT(c.name) as calibers
      FROM weapons w
      LEFT JOIN weapon_calibers wc ON w.id = wc.weapon_id
      LEFT JOIN calibers c ON wc.caliber_id = c.id
      GROUP BY w.id
      ORDER BY w.name
    ''');

      if (!context.mounted) return;
      Navigator.pop(context); // Remove loading

      final selectedWeapon = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => Dialog(
          child: Column(
            children: [
              AppBar(
                title: const Text('Vyberte zbraň'),
                backgroundColor: Colors.blueGrey,
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Hledat zbraň...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    // TODO: Implement search
                  },
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: weapons.length,
                  itemBuilder: (context, index) {
                    final weapon = weapons[index];
                    final calibersStr = weapon['calibers']?.toString() ?? '';
                    final calibers =
                        calibersStr.isEmpty ? [] : calibersStr.split(',');

                    return ListTile(
                      leading: const Icon(Icons.security),
                      title:
                          Text(weapon['name']?.toString() ?? 'Neznámá zbraň'),
                      subtitle: Text(calibers.isEmpty
                          ? 'Žádné kalibry'
                          : 'Kalibry: ${calibers.join(', ')}'),
                      onTap: () => Navigator.pop(context, weapon),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

      if (selectedWeapon != null) {
        final cartridges = await _getCartridgesForWeapon(selectedWeapon['id']);

        if (!context.mounted) return;
        final selectedCartridge = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => Dialog(
            child: Column(
              children: [
                AppBar(
                  title: const Text('Vyberte náboj'),
                  backgroundColor: Colors.blueGrey,
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: cartridges.length,
                    itemBuilder: (context, index) {
                      final cartridge = cartridges[index];
                      return ListTile(
                        leading: const Icon(Icons.track_changes),
                        title: Text(cartridge['name']),
                        subtitle: Text(
                            '${cartridge['caliber_name']} - ${cartridge['stock_quantity']} ks'),
                        onTap: () => Navigator.pop(context, cartridge),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );

        if (selectedCartridge != null && context.mounted) {
          await _showShootingLogForm(
            selectedCartridge,
            preselectedWeapon: selectedWeapon, // Add selected weapon here
          );
        }
      }
    } catch (e) {
      print('Error in weapon first flow: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba: $e')),
      );
    }
  }

  Future<void> _loadLogs() async {
    try {
      final data = await ApiService.getShootingLogs();
      if (mounted) {
        setState(() => logs = data);
      }
    } catch (e) {
      _showError('Nepodařilo se načíst záznamy: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.red.shade800,
        action: SnackBarAction(
          label: 'Zkusit znovu',
          textColor: Colors.white,
          onPressed: _loadData,
        ),
      ),
    );
  }

  Future<void> _showCartridgeSelectionDialog() async {
    try {
      // Show loading dialog immediately
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Load data in parallel
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      final Future<List<Map<String, dynamic>>> cartridgesFuture =
          db.rawQuery('''
      SELECT 
        c.id,
        c.name,
        c.stock_quantity,
        c.caliber_id,
        cal.name as caliber_name
      FROM cartridges c
      LEFT JOIN calibers cal ON c.caliber_id = cal.id
      ORDER BY c.name
    ''');

      // Get results
      final cartridges = await cartridgesFuture;

      // Remove loading dialog
      if (!context.mounted) return;
      Navigator.pop(context);

      if (cartridges.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Žádné náboje nenalezeny v databázi')),
        );
        return;
      }

      // Show cartridge selection dialog
      final selectedCartridge = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('Vyberte náboj'),
                backgroundColor: Colors.blueGrey,
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: cartridges.length,
                  itemBuilder: (context, index) {
                    final cartridge = cartridges[index];
                    return ListTile(
                      leading: const Icon(Icons.track_changes),
                      title: Text(cartridge['name'] ?? 'Neznámý náboj'),
                      subtitle: Text(
                          '${cartridge['caliber_name'] ?? 'Neznámý kalibr'} - ${cartridge['stock_quantity'] ?? '0'} ks'),
                      onTap: () => Navigator.pop(context, cartridge),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

      if (selectedCartridge != null && context.mounted) {
        await _showShootingLogForm(selectedCartridge);
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Remove loading if error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při načítání nábojů: $e')),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _getCartridgesForWeapon(
      int weaponId) async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;

    return await db.rawQuery('''
    SELECT 
      c.id,
      c.name,
      c.stock_quantity,
      cal.id as caliber_id,
      cal.name as caliber_name
    FROM cartridges c
    JOIN calibers cal ON c.caliber_id = cal.id
    JOIN weapon_calibers wc ON cal.id = wc.caliber_id
    WHERE wc.weapon_id = ?
    ORDER BY c.name
  ''', [weaponId]);
  }

  Future<List<Map<String, dynamic>>> _getWeaponsForCaliber(
      int caliberId) async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;

    return await db.rawQuery('''
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
  }

  Future<void> _showShootingLogForm(
    Map<String, dynamic> cartridge, {
    Map<String, dynamic>? preselectedWeapon,
  }) async {
    try {
      // Load data
      final weapons = preselectedWeapon != null
          ? [preselectedWeapon]
          : await _getWeaponsForCaliber(cartridge['caliber_id']);
      final dbHelper = DatabaseHelper();
      final activities = await dbHelper.getData('activities');
      final userRanges = await ApiService.getUserRanges() ?? [];

      if (weapons.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Žádné zbraně nebyly nalezeny pro tento kalibr')),
        );
        return;
      }

      // Form controllers
      final ammoCountController = TextEditingController();
      final dateController = TextEditingController(
          text: DateTime.now().toIso8601String().substring(0, 10));
      final noteController = TextEditingController();

      // Form state
      String? selectedWeapon = preselectedWeapon?['id']?.toString();
      String? selectedActivity;
      String? selectedRange;

      if (!context.mounted) return;
      final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.add_chart, color: Colors.blueGrey),
                      const SizedBox(width: 12),
                      const Text('Přidat záznam',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Form content
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                      left: 16,
                      right: 16,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          // Weapon & Ammo
                          if (preselectedWeapon != null)
                            _buildInfoField('Zbraň', preselectedWeapon['name'],
                                Icons.security)
                          else
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Zbraň *',
                                prefixIcon: Icon(Icons.security),
                              ),
                              value: selectedWeapon,
                              items: weapons
                                  .map((w) => DropdownMenuItem(
                                        value: w['weapon_id'].toString(),
                                        child: Text(w['weapon_name']),
                                      ))
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => selectedWeapon = value),
                            ),
                          const SizedBox(height: 8),
                          _buildInfoField(
                              'Náboj',
                              '${cartridge['name']} (${cartridge['caliber_name']})',
                              Icons.track_changes),

                          const SizedBox(height: 16),
                          // Activity details in row
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: ammoCountController,
                                  decoration: const InputDecoration(
                                    labelText: 'Počet *',
                                    prefixIcon:
                                        Icon(Icons.format_list_numbered),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  decoration: const InputDecoration(
                                    labelText: 'Aktivita *',
                                    prefixIcon: Icon(Icons.category),
                                  ),
                                  value: selectedActivity,
                                  items: activities
                                      .map((a) => DropdownMenuItem(
                                            value: a['id'].toString(),
                                            child: Text(a['activity_name']),
                                          ))
                                      .toList(),
                                  onChanged: (value) =>
                                      setState(() => selectedActivity = value),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),
                          // Date and Range in row
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: dateController,
                                  decoration: const InputDecoration(
                                    labelText: 'Datum *',
                                    prefixIcon: Icon(Icons.calendar_today),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  decoration: const InputDecoration(
                                    labelText: 'Střelnice',
                                    prefixIcon: Icon(Icons.location_on),
                                  ),
                                  value: selectedRange,
                                  isExpanded: true, // Add this line
                                  items: [
                                    const DropdownMenuItem(
                                      value: '',
                                      child: Text('Bez střelnice'),
                                    ),
                                    ...userRanges.map((r) => DropdownMenuItem(
                                          value: r['name'],
                                          child: Text(
                                            r['name'],
                                            overflow: TextOverflow
                                                .ellipsis, // Add this line
                                            maxLines: 1, // Add this line
                                          ),
                                        )),
                                  ],
                                  onChanged: (value) =>
                                      setState(() => selectedRange = value),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),
                          TextField(
                            controller: noteController,
                            decoration: const InputDecoration(
                              labelText: 'Poznámka',
                              prefixIcon: Icon(Icons.note),
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Actions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            if ((selectedWeapon == null &&
                                    preselectedWeapon == null) ||
                                ammoCountController.text.isEmpty ||
                                selectedActivity == null ||
                                dateController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Vyplňte povinná pole!')),
                              );
                              return;
                            }
                            Navigator.pop(context, {
                              'weapon_id': preselectedWeapon != null
                                  ? preselectedWeapon['id']
                                  : int.parse(selectedWeapon!),
                              'cartridge_id': cartridge['id'],
                              'shots_fired':
                                  int.parse(ammoCountController.text),
                              'activity_type': selectedActivity,
                              'date': dateController.text,
                              'range': selectedRange,
                              'note': noteController.text,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Uložit'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Handle result
      if (result != null) {
        if (!context.mounted) return;
        try {
          await ApiService.createShootingLog(result);
          if (!context.mounted) return;
          await _loadData();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Záznam byl úspěšně uložen')),
          );
        } catch (e) {
          print('Error saving shooting log: $e');
          if (!context.mounted) return;
          await dbHelper.addOfflineRequest('create_shooting_log', result);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Záznam uložen pro pozdější synchronizaci')),
          );
        }
      }
    } catch (e) {
      print('Error in _showShootingLogForm: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba: $e')),
      );
    }
  }

  Widget _buildInfoField(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueGrey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  //Metoda pro fitrování terčů
  List<Map<String, dynamic>> _getFilteredTargets() {
    var filteredTargets = List<Map<String, dynamic>>.from(targets);

    // Filter by weapon
    if (filterOptions.weaponName != null) {
      filteredTargets = filteredTargets
          .where(
              (target) => target['weapon']['name'] == filterOptions.weaponName)
          .toList();
    }

    // Filter by cartridge
    if (filterOptions.cartridgeName != null) {
      filteredTargets = filteredTargets
          .where((target) =>
              target['cartridge']?['name'] == filterOptions.cartridgeName)
          .toList();
    }

    // Filter by date range
    if (filterOptions.dateFrom != null) {
      filteredTargets = filteredTargets.where((target) {
        final targetDate = DateTime.parse(target['created_at']);
        return (targetDate.isAfter(filterOptions.dateFrom!) ||
                targetDate.isAtSameMomentAs(filterOptions.dateFrom!)) &&
            (filterOptions.dateTo == null ||
                targetDate.isBefore(filterOptions.dateTo!) ||
                targetDate.isAtSameMomentAs(filterOptions.dateTo!));
      }).toList();
    }

    // Sort
    filteredTargets.sort((a, b) {
      final dateA = DateTime.parse(a['created_at']);
      final dateB = DateTime.parse(b['created_at']);
      return selectedSort == 'newest'
          ? dateB.compareTo(dateA)
          : dateA.compareTo(dateB);
    });

    return filteredTargets;
  }

  //Metoda pro filtrování střeleckých záznamů
  List<Map<String, dynamic>> _getFilteredLogs() {
    print('Filtering logs... Total count: ${logs.length}');
    var filteredLogs = List<Map<String, dynamic>>.from(logs);

    // Apply filters
    if (filterOptions.weaponName != null) {
      print('Applying weapon filter: ${filterOptions.weaponName}');
      filteredLogs = filteredLogs
          .where((log) => log['weapon']['name'] == filterOptions.weaponName)
          .toList();
    }

    if (filterOptions.cartridgeName != null) {
      print('Applying cartridge filter: ${filterOptions.cartridgeName}');
      filteredLogs = filteredLogs
          .where(
              (log) => log['cartridge']?['name'] == filterOptions.cartridgeName)
          .toList();
    }

    if (filterOptions.rangeName != null) {
      print('Applying range filter: ${filterOptions.rangeName}');
      filteredLogs = filteredLogs
          .where((log) => log['range'] == filterOptions.rangeName)
          .toList();
    }

    if (filterOptions.dateFrom != null) {
      print(
          'Applying date range filter: ${filterOptions.dateFrom} - ${filterOptions.dateTo ?? "now"}');
      filteredLogs = filteredLogs.where((log) {
        final logDate = DateTime.parse(log['activity_date']);
        final isAfterStart = logDate.isAfter(filterOptions.dateFrom!) ||
            logDate.isAtSameMomentAs(filterOptions.dateFrom!);
        final isBeforeEnd = filterOptions.dateTo == null ||
            logDate.isBefore(filterOptions.dateTo!) ||
            logDate.isAtSameMomentAs(filterOptions.dateTo!);
        return isAfterStart && isBeforeEnd;
      }).toList();
    }

    // Sort logs by date and time
    print('Sorting logs... Direction: ${selectedSort}');
    filteredLogs.sort((a, b) {
      // Compare activity dates first
      final dateA = DateTime.parse(a['activity_date']);
      final dateB = DateTime.parse(b['activity_date']);

      // Get creation timestamps
      final createdAtA = DateTime.parse(a['created_at']);
      final createdAtB = DateTime.parse(b['created_at']);

      if (dateA.year == dateB.year &&
          dateA.month == dateB.month &&
          dateA.day == dateB.day) {
        // Same day - sort by creation time
        return selectedSort == 'newest'
            ? createdAtB.compareTo(createdAtA)
            : createdAtA.compareTo(createdAtB);
      }

      // Different days - sort by activity date
      return selectedSort == 'newest'
          ? dateB.compareTo(dateA)
          : dateA.compareTo(dateB);
    });

    print('Filtered logs count: ${filteredLogs.length}');
    return filteredLogs;
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.filter_list, color: Colors.blueGrey),
                    const SizedBox(width: 12),
                    const Text(
                      'Filtry',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (filterOptions.hasFilters)
                      TextButton.icon(
                        onPressed: () {
                          setState(() => filterOptions.reset());
                          setModalState(() {});
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('Vymazat'),
                      ),
                  ],
                ),
              ),

              // Filter content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFilterSection(
                        'Zbraň a střelivo',
                        [
                          _buildFilterTile(
                            icon: Icons.security,
                            title: 'Zbraň',
                            value: filterOptions.weaponName ?? 'Všechny',
                            onTap: () async {
                              final weapons = _getUniqueValues(
                                logs,
                                (log) => log['weapon']['name'],
                              );
                              final selected = await _showSelectionDialog(
                                context,
                                'Vyberte zbraň',
                                weapons,
                                filterOptions.weaponName,
                              );
                              if (selected != null) {
                                setState(
                                    () => filterOptions.weaponName = selected);
                                setModalState(() {});
                              }
                            },
                          ),
                          _buildFilterTile(
                            icon: Icons.track_changes,
                            title: 'Náboj',
                            value: filterOptions.cartridgeName ?? 'Všechny',
                            onTap: () async {
                              final cartridges = _getUniqueValues(
                                logs.where((log) => log['cartridge'] != null),
                                (log) => log['cartridge']['name'],
                              );
                              final selected = await _showSelectionDialog(
                                context,
                                'Vyberte náboj',
                                cartridges,
                                filterOptions.cartridgeName,
                              );
                              if (selected != null) {
                                setState(() =>
                                    filterOptions.cartridgeName = selected);
                                setModalState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildFilterSection(
                        'Místo a čas',
                        [
                          _buildFilterTile(
                            icon: Icons.location_on,
                            title: 'Střelnice',
                            value: filterOptions.rangeName ?? 'Všechny',
                            onTap: () async {
                              final ranges = _getUniqueValues(
                                logs.where((log) => log['range'] != null),
                                (log) => log['range'],
                              );
                              final selected = await _showSelectionDialog(
                                context,
                                'Vyberte střelnici',
                                ranges,
                                filterOptions.rangeName,
                              );
                              if (selected != null) {
                                setState(
                                    () => filterOptions.rangeName = selected);
                                setModalState(() {});
                              }
                            },
                          ),
                          _buildFilterTile(
                            icon: Icons.calendar_today,
                            title: 'Datum',
                            value: filterOptions.dateFrom != null
                                ? '${DateFormat('dd.MM.yyyy').format(filterOptions.dateFrom!)} - '
                                    '${filterOptions.dateTo != null ? DateFormat('dd.MM.yyyy').format(filterOptions.dateTo!) : 'nyní'}'
                                : 'Všechny',
                            onTap: () async {
                              final dateRange = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                                initialDateRange: filterOptions.dateFrom != null
                                    ? DateTimeRange(
                                        start: filterOptions.dateFrom!,
                                        end: filterOptions.dateTo ??
                                            DateTime.now(),
                                      )
                                    : null,
                              );
                              if (dateRange != null) {
                                setState(() {
                                  filterOptions.dateFrom = dateRange.start;
                                  filterOptions.dateTo = dateRange.end;
                                });
                                setModalState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Actions
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey,
                          foregroundColor: Colors.white, // Add this line
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Zavřít'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// Helper method for selection dialogs
  Future<String?> _showSelectionDialog(
    BuildContext context,
    String title,
    List<String> items,
    String? selectedItem,
  ) {
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        title: const Text('Všechny'),
                        leading: Icon(
                          Icons.check,
                          color: selectedItem == null
                              ? Colors.blueGrey
                              : Colors.transparent,
                        ),
                        onTap: () => Navigator.pop(context, null),
                      ),
                      ...items.map((item) => ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            title: Text(item),
                            leading: Icon(
                              Icons.check,
                              color: selectedItem == item
                                  ? Colors.blueGrey
                                  : Colors.transparent,
                            ),
                            onTap: () => Navigator.pop(context, item),
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// Helper method to get unique values from logs
  List<String> _getUniqueValues(
    Iterable<dynamic> items,
    String Function(dynamic) selector,
  ) {
    return items.map(selector).where((item) => item != null).toSet().toList()
      ..sort();
  }

  Widget _buildFilterHeader() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: _showFilterDialog,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.filter_list, color: Colors.blueGrey),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filtry',
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (filterOptions.hasFilters) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (filterOptions.weaponName != null)
                            _buildFilterChip(
                                'Zbraň: ${filterOptions.weaponName}'),
                          if (filterOptions.cartridgeName != null)
                            _buildFilterChip(
                                'Náboj: ${filterOptions.cartridgeName}'),
                          if (filterOptions.rangeName != null)
                            _buildFilterChip(
                                'Střelnice: ${filterOptions.rangeName}'),
                          if (filterOptions.dateFrom != null)
                            _buildFilterChip(
                                'Datum: ${DateFormat('dd.MM.yyyy').format(filterOptions.dateFrom!)} - '
                                '${filterOptions.dateTo != null ? DateFormat('dd.MM.yyyy').format(filterOptions.dateTo!) : 'nyní'}'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (filterOptions.hasFilters)
                IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey[600]),
                  onPressed: () => setState(() => filterOptions.reset()),
                ),
              IconButton(
                icon: Icon(
                  selectedSort == 'newest'
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  color: Colors.grey[600],
                ),
                onPressed: () => setState(() {
                  selectedSort = selectedSort == 'newest' ? 'oldest' : 'newest';
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildFilterTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.blueGrey, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.blueGrey.withOpacity(0.5),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.blueGrey.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.blueGrey[700],
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    // Find activity name from activities list
    final activity = activities.firstWhere(
      (a) => a['id'].toString() == log['activity_type'].toString(),
      orElse: () => {'activity_name': 'Neznámá aktivita'},
    );
    final activityName = activity['activity_name'];

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          // TODO: Navigate to detail
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: activityName == 'Střelba'
                          ? Colors.green.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      activityName,
                      style: TextStyle(
                        color: activityName == 'Střelba'
                            ? Colors.green
                            : Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    DateFormat('dd.MM.yyyy').format(
                      DateTime.parse(log['activity_date']),
                    ),
                    style: const TextStyle(color: Color(0xFF2C3E50)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      log['weapon']['name'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.track_changes,
                            size: 16, color: Colors.blueGrey),
                        const SizedBox(width: 4),
                        Text(
                          '${log['ammo_count']} ks',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (log['cartridge'] != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CartridgeDetailScreen(
                              cartridge: log['cartridge'],
                            ),
                          ),
                        );
                      },
                      child: _buildTag(
                        '${log['cartridge']['name']} (${log['cartridge']['caliber']['name']})',
                        icon: Icons.keyboard_arrow_right,
                      ),
                    ),
                    if (log['cartridge']['price'] != null)
                      _buildTag(
                        '${(double.parse(log['cartridge']['price']) * log['ammo_count']).toStringAsFixed(2)} Kč',
                      ),
                  ],
                ),
              ],
              if (log['range'] != null ||
                  (log['note']?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (log['range'] != null)
                      _buildTag(log['range'], icon: Icons.location_on),
                    if (log['note']?.isNotEmpty ?? false)
                      _buildTag(log['note'], icon: Icons.note),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showTargetDetail(Map<String, dynamic> target) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(target['weapon']['name']),
            backgroundColor: Colors.blueGrey,
          ),
          body: Container(
            color: Colors.black,
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Hero(
                        tag: 'target-${target['id']}',
                        child: Center(
                          child: Image.network(
                            'https://www.reloading-tracker.cz/storage/${target['image_path']}',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    color: Colors.black.withOpacity(0.7),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zbraň: ${target['weapon']['name']}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        if (target['cartridge'] != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Náboj: ${target['cartridge']['name']}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Datum: ${DateFormat('dd.MM.yyyy').format(DateTime.parse(target['created_at']))}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      constraints: const BoxConstraints(maxWidth: 300), // Add max width
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.grey[800]),
            const SizedBox(width: 4),
          ],
          Flexible(
            // Wrap text in Flexible
            child: Text(
              text,
              style: TextStyle(color: Colors.grey[800], fontSize: 14),
              overflow: TextOverflow.ellipsis,
              maxLines: 3, // Allow up to 3 lines for notes
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetCard(Map<String, dynamic> target) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showTargetDetail(target),
        child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  color: Colors.grey[100],
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Center(
                      child: Image.network(
                        'https://www.reloading-tracker.cz/storage/${target['image_path']}',
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.blueGrey[300],
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target['weapon']['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (target['cartridge'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          target['cartridge']['name'],
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 12, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('dd.MM.yyyy').format(
                              DateTime.parse(target['created_at']),
                            ),
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (showTargets) {
      if (targets.isEmpty) {
        return const Center(
          child: Text('Žádné terče nenalezeny',
              style: TextStyle(fontSize: 16, color: Colors.black54)),
        );
      }

      // First filter and sort all targets
      final filteredTargets = _getFilteredTargets();

      // Then group by weapon
      final groupedTargets = <String, List<Map<String, dynamic>>>{};
      for (var target in filteredTargets) {
        final weaponName = target['weapon']['name'] as String;
        groupedTargets.putIfAbsent(weaponName, () => []);
        groupedTargets[weaponName]!.add(target);
      }

      // Sort targets within each group
      for (var weaponTargets in groupedTargets.values) {
        weaponTargets.sort((a, b) {
          final dateA = DateTime.parse(a['created_at']);
          final dateB = DateTime.parse(b['created_at']);
          return selectedSort == 'newest'
              ? dateB.compareTo(dateA)
              : dateA.compareTo(dateB);
        });
      }

      return Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: groupedTargets.length,
              itemBuilder: (context, index) {
                final weaponName = groupedTargets.keys.elementAt(index);
                final weaponTargets = groupedTargets[weaponName]!;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ExpansionTile(
                    title: Text(
                      weaponName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        Icon(Icons.photo, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Počet terčů: ${weaponTargets.length}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    children: [
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: weaponTargets.length,
                        itemBuilder: (context, index) =>
                            _buildTargetCard(weaponTargets[index]),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    } else {
      if (logs.isEmpty) {
        return const Center(
          child: Text('Žádné záznamy nenalezeny',
              style: TextStyle(fontSize: 16, color: Colors.black54)),
        );
      }

      // Get filtered logs
      final filteredLogs = _getFilteredLogs();

      // Group by weapon
      final groupedLogs = <String, List<Map<String, dynamic>>>{};
      for (var log in filteredLogs) {
        final weaponName = log['weapon']['name'] as String;
        groupedLogs.putIfAbsent(weaponName, () => []);
        groupedLogs[weaponName]!.add(log);
      }

      return Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: groupedLogs.length,
              itemBuilder: (context, index) {
                final weaponName = groupedLogs.keys.elementAt(index);
                final weaponLogs = groupedLogs[weaponName]!;

                // Počítáme celkový počet ran z VŠECH logů pro tuto zbraň
                final totalRounds = logs
                    .where((log) => log['weapon']['name'] == weaponName)
                    .fold<int>(
                        0, (sum, log) => sum + (log['ammo_count'] as int));

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ExpansionTile(
                    title: Text(
                      weaponName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        Icon(Icons.track_changes,
                            size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Celkem vystřeleno: $totalRounds ran',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    children: weaponLogs
                        .map((log) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: _buildLogCard(log),
                            ))
                        .toList(),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Střelecký deník'),
        backgroundColor: Colors.blueGrey,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Main toggle - more prominent
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blueGrey.shade700, Colors.blueGrey.shade600],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => setState(() => showTargets = false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              !showTargets ? Colors.white : Colors.transparent,
                          foregroundColor: !showTargets
                              ? Colors.blueGrey.shade700
                              : Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: !showTargets
                                ? BorderSide.none
                                : BorderSide(
                                    color: Colors.white.withOpacity(0.3)),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.list, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Záznamy',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => setState(() => showTargets = true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              showTargets ? Colors.white : Colors.transparent,
                          foregroundColor: showTargets
                              ? Colors.blueGrey.shade700
                              : Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: showTargets
                                ? BorderSide.none
                                : BorderSide(
                                    color: Colors.white.withOpacity(0.3)),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.track_changes, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Terče',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Filters section - subtle
          _buildFilterHeader(),
          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadData(clearCache: true),
              child: _buildContent(),
            ),
          ),
        ],
      ),
      floatingActionButton: SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
        activeBackgroundColor: Colors.red,
        activeForegroundColor: Colors.white,
        spacing: 8,
        children: [
          if (!showTargets) ...[
            SpeedDialChild(
              child: const Icon(Icons.camera_alt),
              backgroundColor: Colors.blue,
              label: 'Naskenovat náboj',
              labelStyle: const TextStyle(fontSize: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BarcodeScannerScreen(
                      source: 'shooting_log',
                    ),
                  ),
                );
              },
            ),
            SpeedDialChild(
              child: const Icon(Icons.edit),
              backgroundColor: Colors.green,
              label: 'Ruční zadání',
              labelStyle: const TextStyle(fontSize: 16),
              onTap: _showEntryTypeSelection, // Změna zde
            ),
          ] else
            SpeedDialChild(
              child: const Icon(Icons.camera_alt),
              backgroundColor: Colors.blue,
              label: 'Přidat terč',
              labelStyle: const TextStyle(fontSize: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TargetPhotoScreen(
                      // Add callback here
                      onTargetAdded: () async {
                        // Force reload targets without cache
                        await _loadTargets(forceRefresh: true);
                      },
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
