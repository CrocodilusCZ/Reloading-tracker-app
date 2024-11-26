// lib/models/cartridge.dart
class Cartridge {
  final int id;
  final String name;
  final String type; // 'factory' nebo 'reload'
  final String caliberName;
  final int stockQuantity;
  final double price;

  // Údaje pro tovární náboje
  final String? manufacturer;
  final String? bulletSpecification;

  // Údaje pro přebíjené náboje
  final String? bulletName;
  final String? powderName;
  final String? powderWeight;
  final String? primerName;
  final String? oal;
  final String? velocity;

  final String? barcode;
  final bool isFavorite;

  Cartridge({
    required this.id,
    required this.name,
    required this.type,
    required this.caliberName,
    required this.stockQuantity,
    required this.price,
    this.manufacturer,
    this.bulletSpecification,
    this.bulletName,
    this.powderName,
    this.powderWeight,
    this.primerName,
    this.oal,
    this.velocity,
    this.barcode,
    this.isFavorite = false,
  });

  factory Cartridge.fromJson(Map<String, dynamic> json) {
    return Cartridge(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      caliberName: json['caliber_name'],
      stockQuantity: json['stock_quantity'] ?? 0,
      price: double.tryParse(json['price'].toString()) ?? 0.0,
      manufacturer: json['manufacturer'],
      bulletSpecification: json['bullet_specification'],
      bulletName: json['bullet']?['name'],
      powderName: json['powder']?['name'],
      powderWeight: json['powder_weight'],
      primerName: json['primer_name'],
      oal: json['oal'],
      velocity: json['velocity_ms'],
      barcode: json['barcode'],
      isFavorite: json['is_favorite'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'caliber_name': caliberName,
      'stock_quantity': stockQuantity,
      'price': price,
      'manufacturer': manufacturer,
      'bullet_specification': bulletSpecification,
      'bullet_name': bulletName,
      'powder_name': powderName,
      'powder_weight': powderWeight,
      'primer_name': primerName,
      'oal': oal,
      'velocity_ms': velocity,
      'barcode': barcode,
      'is_favorite': isFavorite ? 1 : 0,
    };
  }
}
