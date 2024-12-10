class TargetPhotoRequest {
  final int id;
  final String photoPath;
  final String note;
  final DateTime createdAt;
  final bool isSynced;
  final int cartridgeId;

  TargetPhotoRequest({
    required this.id,
    required this.photoPath,
    required this.note,
    required this.createdAt,
    required this.cartridgeId,
    this.isSynced = false,
  });

  factory TargetPhotoRequest.fromJson(Map<String, dynamic> json) {
    return TargetPhotoRequest(
      id: json['id'] as int,
      photoPath: json['photo_path'] as String,
      note: json['note'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      cartridgeId: json['cartridge_id'] as int,
      isSynced: (json['is_synced'] as int) == 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'photo_path': photoPath,
        'note': note,
        'created_at': createdAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'cartridge_id': cartridgeId,
      };
}
