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

  /// False while the field only exists on this phone. Fields created offline
  /// queue exactly like samplings, so a talhao registered with no signal is not
  /// lost (RF02).
  @HiveField(8)
  bool isSynced;

  FieldModel({
    required this.id,
    required this.producerId,
    required this.name,
    required this.cropType,
    required this.plantingDate,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.isSynced = false,
  });

  factory FieldModel.fromJson(Map<String, dynamic> json) {
    double lat = 0.0;
    double lon = 0.0;
    // PostgREST serialises a geography column as GeoJSON, whose coordinate pair
    // is [longitude, latitude] - the reverse of the order used everywhere else.
    if (json['center'] is Map) {
      final coordinates = json['center']['coordinates'] as List?;
      if (coordinates != null && coordinates.length >= 2) {
        lon = (coordinates[0] as num).toDouble();
        lat = (coordinates[1] as num).toDouble();
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
      // It came from the server, so by definition it is already synced.
      isSynced: true,
    );
  }

  Map<String, dynamic> toJson() {
    // fields.boundary is NOT NULL in the schema but the app only captures a
    // single centre point, so a small square (~11 m per side) is synthesised
    // around it to satisfy the column.
    const double delta = 0.0001;
    final double latMin = latitude - delta;
    final double latMax = latitude + delta;
    final double lonMin = longitude - delta;
    final double lonMax = longitude + delta;
    return {
      'id': id,
      'producer_id': producerId,
      'name': name,
      'crop_type': cropType,
      'planting_date': plantingDate.toIso8601String().split('T')[0],
      'center': 'POINT($longitude $latitude)', // WKT geography format
      'boundary':
          'POLYGON(($lonMin $latMin, $lonMax $latMin, $lonMax $latMax, $lonMin $latMax, $lonMin $latMin))',
      'created_at': createdAt.toIso8601String(),
    };
  }
}
