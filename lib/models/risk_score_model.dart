class RiskScoreModel {
  final String fieldId;
  final int score;
  final String mainPest;
  final DateTime updatedAt;

  RiskScoreModel({
    required this.fieldId,
    required this.score,
    required this.mainPest,
    required this.updatedAt,
  });

  factory RiskScoreModel.fromJson(Map<String, dynamic> json) {
    return RiskScoreModel(
      fieldId: json['field_id'] as String,
      score: json['score'] as int? ?? 0,
      mainPest: json['main_pest'] as String? ?? 'Nenhuma',
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'field_id': fieldId,
      'score': score,
      'main_pest': mainPest,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
