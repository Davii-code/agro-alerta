/// One row of public.mip_parameters: the economics of controlling a given pest
/// on a given crop.
///
/// Deliberately not a Hive @HiveType. Reference data is cached as JSON inside a
/// plain string box, so adding a field here never requires regenerating an
/// adapter or migrating a typed box on the producer's phone.
class MipParameter {
  final String culture;

  /// '*' is the per-crop wildcard used when no pest-specific row exists.
  final String pestSpecies;

  /// C - control cost per hectare, in R$.
  final double controlCostPerHa;

  /// K - expected efficacy of the control, 0 to 1.
  final double efficacyFactor;

  /// I - injury coefficient: sacks lost per pest unit per hectare.
  final double injuryFactor;

  const MipParameter({
    required this.culture,
    required this.pestSpecies,
    required this.controlCostPerHa,
    required this.efficacyFactor,
    required this.injuryFactor,
  });

  bool get isWildcard => pestSpecies == '*';

  factory MipParameter.fromJson(Map<String, dynamic> json) {
    return MipParameter(
      culture: json['culture'] as String,
      pestSpecies: (json['pest_species'] as String?) ?? '*',
      controlCostPerHa: (json['control_cost_per_ha'] as num).toDouble(),
      efficacyFactor: (json['efficacy_factor'] as num).toDouble(),
      injuryFactor: (json['injury_factor'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'culture': culture,
        'pest_species': pestSpecies,
        'control_cost_per_ha': controlCostPerHa,
        'efficacy_factor': efficacyFactor,
        'injury_factor': injuryFactor,
      };
}

/// One row of public.market_prices.
class MarketPrice {
  final String culture;
  final double pricePerSack;
  final String source;
  final DateTime updatedAt;

  const MarketPrice({
    required this.culture,
    required this.pricePerSack,
    required this.source,
    required this.updatedAt,
  });

  factory MarketPrice.fromJson(Map<String, dynamic> json) {
    return MarketPrice(
      culture: json['culture'] as String,
      pricePerSack: (json['price_per_sack'] as num).toDouble(),
      source: (json['source'] as String?) ?? 'CEPEA',
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'culture': culture,
        'price_per_sack': pricePerSack,
        'source': source,
        'updated_at': updatedAt.toIso8601String(),
      };
}
