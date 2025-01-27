enum ComponentType { bullet, powder, primer, brass }

abstract class InventoryComponent {
  final int id;
  final String name;
  final String manufacturer;
  final int stockQuantity;
  final int minQuantity;
  final ComponentType type;

  bool get isLowStock => stockQuantity <= minQuantity && minQuantity > 0;

  const InventoryComponent({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.stockQuantity,
    required this.minQuantity,
    required this.type,
  });
}

class Bullet extends InventoryComponent {
  final double weightGrains;
  final String caliberName;

  const Bullet({
    required super.id,
    required super.name,
    required super.manufacturer,
    required super.stockQuantity,
    required super.minQuantity,
    required this.weightGrains,
    required this.caliberName,
  }) : super(type: ComponentType.bullet);

  factory Bullet.fromJson(Map<String, dynamic> json) {
    return Bullet(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      stockQuantity: json['stock_quantity'] as int? ?? 0,
      minQuantity: json['min_quantity'] as int? ?? 0,
      weightGrains: (json['weight_grains'] as num?)?.toDouble() ?? 0,
      caliberName: json['caliber']?['name'] as String? ?? '',
    );
  }
}

class Powder extends InventoryComponent {
  final String burnRate;

  const Powder({
    required super.id,
    required super.name,
    required super.manufacturer,
    required super.stockQuantity,
    required super.minQuantity,
    required this.burnRate,
  }) : super(type: ComponentType.powder);

  factory Powder.fromJson(Map<String, dynamic> json) {
    return Powder(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      stockQuantity: json['stock_quantity'] as int? ?? 0,
      minQuantity: json['min_quantity'] as int? ?? 0,
      burnRate: json['burn_rate'] as String? ?? '',
    );
  }
}

class Primer extends InventoryComponent {
  final String size;

  const Primer({
    required super.id,
    required super.name,
    required super.manufacturer,
    required super.stockQuantity,
    required super.minQuantity,
    required this.size,
  }) : super(type: ComponentType.primer);

  factory Primer.fromJson(Map<String, dynamic> json) {
    return Primer(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      stockQuantity: json['stock_quantity'] as int? ?? 0,
      minQuantity: json['min_quantity'] as int? ?? 0,
      size: json['size'] as String? ?? '',
    );
  }
}

class Brass extends InventoryComponent {
  final String caliberName;
  final int reloadCount;

  const Brass({
    required super.id,
    required super.name,
    required super.manufacturer,
    required super.stockQuantity,
    required super.minQuantity,
    required this.caliberName,
    required this.reloadCount,
  }) : super(type: ComponentType.brass);

  factory Brass.fromJson(Map<String, dynamic> json) {
    return Brass(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      stockQuantity: json['stock_quantity'] as int? ?? 0,
      minQuantity: json['min_quantity'] as int? ?? 0,
      caliberName: json['caliber']?['name'] as String? ?? '',
      reloadCount: json['reload_count'] as int? ?? 0,
    );
  }
}
