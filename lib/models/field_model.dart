import 'package:hive/hive.dart';

part 'field_model.g.dart';

@HiveType(typeId: 0)
class FieldModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String producerId;

  @HiveField(2)
  final String name;

  @HiveField(3)
  final String cropType;

  @HiveField(4)
  final DateTime plantingDate;

  @HiveField(5)
  final double latitude;

  @HiveField(6)
  final double longitude;

  @HiveField(7)
  final DateTime createdAt;

  FieldModel({
    required this.id,
    required this.producerId,
    required this.name,
    required this.cropType,
    required this.plantingDate,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  factory FieldModel.fromJson(Map<String, dynamic> json) {
    double lat = 0.0;
    double lon = 0.0;
    if (json['center'] != null) {
      if (json['center'] is Map) {
        final coordinates = json['center']['coordinates'] as List?;
        if (coordinates != null && coordinates.length >= 2) {
          lon = (coordinates[0] as num).toDouble();
          lat = (coordinates[1] as num).toDouble();
        }
      }
    }
    return FieldModel(
      id: json['id'] as String,
      producerId: json['producer_id'] as String,
      name: json['name'] as String,
      cropType: json['crop_type'] as String,
      plantingDate: DateTime.parse(json['planting_date'] as String),
      latitude: lat,
      longitude: lon,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    final double latMin = latitude - 0.0001;
    final double latMax = latitude + 0.0001;
    final double lonMin = longitude - 0.0001;
    final double lonMax = longitude + 0.0001;
    return {
      'id': id,
      'producer_id': producerId,
      'name': name,
      'crop_type': cropType,
      'planting_date': plantingDate.toIso8601String().split('T')[0],
      'center': 'POINT($longitude $latitude)', // WKT geography format
      'boundary': 'POLYGON(($lonMin $latMin, $lonMax $latMin, $lonMax $latMax, $lonMin $latMax, $lonMin $latMin))', // WKT Polygon geography format
      'created_at': createdAt.toIso8601String(),
    };
  }
}
