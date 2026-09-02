import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mip_parameter_model.dart';
import 'database_service.dart';

/// Serves the C/K/I parameters and the sack price the NDE formula needs (RF04).
///
/// Resolution order, best source first:
///   1. rows fetched from Supabase this session
///   2. the JSON copy cached in Hive from the last successful fetch
///   3. bundled constants, so a phone that has never been online still computes
///
/// Before this existed, HomeScreen hardcoded C/K/I in an if/else chain and read
/// prices from a literal list, while mip_parameters and market_prices sat unused
/// in the database - and the two sets of numbers did not even agree.
class MipService {
  static final MipService _instance = MipService._internal();
  factory MipService() => _instance;
  MipService._internal();

  final _db = DatabaseService();

  List<MipParameter> _parameters = const [];
  Map<String, MarketPrice> _prices = const {};
  DateTime? _lastRefresh;

  DateTime? get lastRefresh => _lastRefresh;

  /// Prices currently in use, for the ticker on the dashboard.
  List<MarketPrice> get prices => _prices.values.toList()
    ..sort((a, b) => a.culture.compareTo(b.culture));

  bool get _isSupabaseInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads the cache, then tries the network. Never throws: a failure here must
  /// not stop the app from opening.
  Future<void> refresh() async {
    _loadFromCache();

    if (!_isSupabaseInitialized) return;

    try {
      final client = Supabase.instance.client;
      // main() awaits this before runApp, so a stalled request would hold the
      // splash screen open. The cache already loaded above is a fine answer.
      const timeout = Duration(seconds: 8);
      final paramRows =
          await client.from('mip_parameters').select().timeout(timeout);
      final priceRows =
          await client.from('market_prices').select().timeout(timeout);

      if (paramRows.isNotEmpty) {
        _parameters = paramRows
            .map<MipParameter>((r) => MipParameter.fromJson(r))
            .toList();
        await _db.putCache('mip_parameters', jsonEncode(paramRows));
      }

      if (priceRows.isNotEmpty) {
        final parsed = priceRows.map<MarketPrice>((r) => MarketPrice.fromJson(r));
        _prices = {for (final p in parsed) p.culture: p};
        await _db.putCache('market_prices', jsonEncode(priceRows));
      }

      _lastRefresh = DateTime.now();
      await _db.putCache('mip_refreshed_at', _lastRefresh!.toIso8601String());
    } catch (_) {
      // Offline: whatever _loadFromCache() produced stays in force.
    }
  }

  void _loadFromCache() {
    final rawParams = _db.getCache('mip_parameters');
    if (rawParams != null) {
      try {
        final decoded = jsonDecode(rawParams) as List;
        _parameters = decoded
            .map((r) => MipParameter.fromJson(Map<String, dynamic>.from(r)))
            .toList();
      } catch (_) {
        _parameters = const [];
      }
    }

    final rawPrices = _db.getCache('market_prices');
    if (rawPrices != null) {
      try {
        final decoded = jsonDecode(rawPrices) as List;
        final parsed = decoded
            .map((r) => MarketPrice.fromJson(Map<String, dynamic>.from(r)));
        _prices = {for (final p in parsed) p.culture: p};
      } catch (_) {
        _prices = const {};
      }
    }

    final rawStamp = _db.getCache('mip_refreshed_at');
    if (rawStamp != null) _lastRefresh = DateTime.tryParse(rawStamp);
  }

  /// Most specific parameters available: exact pest first, then the '*' wildcard
  /// row for the crop, then the bundled default.
  MipParameter parametersFor({
    required String culture,
    required String pestSpecies,
  }) {
    MipParameter? exact;
    MipParameter? wildcard;

    for (final p in _parameters) {
      if (p.culture != culture) continue;
      if (p.pestSpecies == pestSpecies) {
        exact = p;
        break;
      }
      if (p.isWildcard) wildcard = p;
    }

    return exact ??
        wildcard ??
        _bundledDefaults[culture] ??
        _bundledDefaults['soja']!;
  }

  /// V in the NDE formula.
  double priceFor(String culture) =>
      _prices[culture]?.pricePerSack ?? _bundledPrices[culture] ?? 120.0;

  MarketPrice? priceRowFor(String culture) => _prices[culture];

  /// Kept identical to the seed in supabase/migrations/03_mip_and_pest_map.sql
  /// and to MIP_FALLBACK_PARAMETERS in pipeline/ingestion_pipeline.py.
  static const Map<String, MipParameter> _bundledDefaults = {
    'soja': MipParameter(
      culture: 'soja',
      pestSpecies: '*',
      controlCostPerHa: 130.00,
      efficacyFactor: 0.85,
      injuryFactor: 0.15,
    ),
    'milho': MipParameter(
      culture: 'milho',
      pestSpecies: '*',
      controlCostPerHa: 140.00,
      efficacyFactor: 0.82,
      injuryFactor: 0.60,
    ),
    'algodao': MipParameter(
      culture: 'algodao',
      pestSpecies: '*',
      controlCostPerHa: 200.00,
      efficacyFactor: 0.85,
      injuryFactor: 1.50,
    ),
  };

  static const Map<String, double> _bundledPrices = {
    'soja': 129.71,
    'milho': 65.32,
    'algodao': 210.45,
  };
}
