// lib/models/cartridge.dart
class Cartridge {
  final int id;
  final String description;
  final String price;
  final int stockQuantity;
  final String bulletName;
  final String primerName;
  final String powderName;
  final String caliberName;
  final String powderWeight;

  Cartridge({
    required this.id,
    required this.description,
    required this.price,
    required this.stockQuantity,
    required this.bulletName,
    required this.primerName,
    required this.powderName,
    required this.caliberName,
    required this.powderWeight,
  });

  factory Cartridge.fromJson(Map<String, dynamic> json) {
    return Cartridge(
      id: json['id'],
      description: json['description'],
      price: json['price'],
      stockQuantity: json['stock_quantity'],
      bulletName: json['bullet_name'],
      primerName: json['primer_name'],
      powderName: json['powder_name'],
      caliberName: json['caliber_name'],
      powderWeight: json['powder_weight'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'description': description,
      'price': price,
      'stock_quantity': stockQuantity,
      'bullet_name': bulletName,
      'primer_name': primerName,
      'powder_name': powderName,
      'caliber_name': caliberName,
      'powder_weight': powderWeight,
    };
  }
}
