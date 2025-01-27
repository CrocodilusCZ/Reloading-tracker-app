class CartridgeDetails {
  final int id;
  final int? loadStepId;
  final int userId;
  final String name;
  final String? description;
  final int isPublic;
  final int? bulletId;
  final int? primerId;
  final double? powderWeight;
  final int stockQuantity;
  final int? brassId;
  final double? velocityMs;
  final double? energyJoules;
  final double? oal;
  final double? standardDeviation;
  final int isFavorite;
  final String price;
  final int caliberId;
  final int? powderId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String type;
  final String? manufacturer;
  final String? bulletSpecification;
  final int totalUpvotes;
  final int totalDownvotes;
  final String? barcode;
  final int? packageSize;
  final CaliberDetails? caliber;

  CartridgeDetails.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        loadStepId = json['load_step_id'],
        userId = json['user_id'],
        name = json['name'],
        description = json['description'],
        isPublic = json['is_public'],
        bulletId = json['bullet_id'],
        primerId = json['primer_id'],
        powderWeight = json['powder_weight']?.toDouble(),
        stockQuantity = json['stock_quantity'],
        brassId = json['brass_id'],
        velocityMs = json['velocity_ms']?.toDouble(),
        energyJoules = json['energy_joules']?.toDouble(),
        oal = json['oal']?.toDouble(),
        standardDeviation = json['standard_deviation']?.toDouble(),
        isFavorite = json['is_favorite'],
        price = json['price'],
        caliberId = json['caliber_id'],
        powderId = json['powder_id'],
        createdAt = DateTime.parse(json['created_at']),
        updatedAt = DateTime.parse(json['updated_at']),
        type = json['type'],
        manufacturer = json['manufacturer'],
        bulletSpecification = json['bullet_specification'],
        totalUpvotes = json['total_upvotes'],
        totalDownvotes = json['total_downvotes'],
        barcode = json['barcode'],
        packageSize = json['package_size'],
        caliber = json['caliber'] != null
            ? CaliberDetails.fromJson(json['caliber'])
            : null;
}

class CaliberDetails {
  final int id;
  final String name;
  final String description;
  final String bulletDiameter;
  final String caseLength;
  final String maxPressure;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int userId;
  final int isGlobal;

  CaliberDetails.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        name = json['name'],
        description = json['description'],
        bulletDiameter = json['bullet_diameter'],
        caseLength = json['case_length'],
        maxPressure = json['max_pressure'],
        createdAt = DateTime.parse(json['created_at']),
        updatedAt = DateTime.parse(json['updated_at']),
        userId = json['user_id'],
        isGlobal = json['is_global'];
}
