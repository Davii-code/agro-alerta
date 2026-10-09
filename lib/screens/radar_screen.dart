import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/field_model.dart';
import '../services/database_service.dart';
import '../shared/theme.dart';

/// One confirmed pest focus, as returned by get_regional_hotspots.
class Hotspot {
  final String pest;
  final String cropType;
  final int observerCount;
  final int totalSpecimens;
  final double latitude;
  final double longitude;

  const Hotspot({
    required this.pest,
    required this.cropType,
    required this.observerCount,
    required this.totalSpecimens,
    required this.latitude,
    required this.longitude,
  });

  factory Hotspot.fromJson(Map<String, dynamic> json) => Hotspot(
        pest: json['pest_name'] as String? ?? 'Praga',
        cropType: json['crop_type'] as String? ?? 'soja',
        observerCount: (json['observer_count'] as num?)?.toInt() ?? 0,
        totalSpecimens: (json['total_specimens'] as num?)?.toInt() ?? 0,
        // The RPC now returns plain numerics instead of a geography column, so
        // there is no GeoJSON unwrapping to do and nothing to mis-order.
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      );

  String get category {
    final p = pest.toLowerCase();
    if (p.contains('lagarta')) return 'Lagartas';
    if (p.contains('percevejo') || p.contains('bicudo')) return 'Percevejos';
    return 'Outros';
  }

  Color get color => switch (category) {
        'Lagartas' => AgroTheme.statusYellow,
        'Percevejos' => AgroTheme.statusRed,
        _ => AgroTheme.legendPurple,
      };

  /// Drives the heat circle radius: more confirmations, wider halo.
  double get intensityRadiusMeters => 1500 + (observerCount.clamp(2, 12) * 400);
}

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  final _db = DatabaseService();

  // Starts online. The vector fallback is for when the map cannot load, not the
  // default view - previously the screen opened on mock data even with signal.
  bool _offlineMode = false;
  bool _loading = false;
  String? _loadError;

  List<Hotspot> _hotspots = const [];
  List<FieldModel> _myFields = const [];

  @override
  void initState() {
    super.initState();
    _myFields = _db.getFields();
    _fetchHotspots();
  }

  Future<void> _fetchHotspots() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final response = await Supabase.instance.client.rpc(
        'get_regional_hotspots',
        params: {
          'radius_meters': 5000.0,
          'min_observers': 2,
          'window_days': 7,
        },
      );

      final list = (response as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _hotspots = list
            .map((e) => Hotspot.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offlineMode = true;
        _loadError = 'Sem conexão com o servidor. Mostrando o mapa simplificado.';
      });
    }
  }

  /// Straight-line distance from the producer's nearest field to the nearest
  /// focus. This is the number that decides whether they act today.
  ({Hotspot hotspot, double metres})? get _closestThreat {
    if (_hotspots.isEmpty || _myFields.isEmpty) return null;

    Hotspot? best;
    var bestDistance = double.infinity;

    for (final h in _hotspots) {
      for (final f in _myFields) {
        final d = Geolocator.distanceBetween(
          f.latitude,
          f.longitude,
          h.latitude,
          h.longitude,
        );
        if (d < bestDistance) {
          bestDistance = d;
          best = h;
        }
      }
    }

    if (best == null) return null;
    return (hotspot: best, metres: bestDistance);
  }

  LatLng get _initialTarget {
    if (_myFields.isNotEmpty) {
      return LatLng(_myFields.first.latitude, _myFields.first.longitude);
    }
    if (_hotspots.isNotEmpty) {
      return LatLng(_hotspots.first.latitude, _hotspots.first.longitude);
    }
    return const LatLng(-16.326, -48.953); // Anápolis region
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar da região'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _fetchHotspots,
          ),
          IconButton(
            icon: Icon(_offlineMode ? Icons.map_outlined : Icons.grid_view),
            tooltip: _offlineMode ? 'Ver mapa' : 'Ver mapa simplificado',
            onPressed: () => setState(() => _offlineMode = !_offlineMode),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _offlineMode ? _simplifiedMap() : _osmMap(),
          ),
          Positioned(top: 12, left: 12, right: 12, child: _topBanner()),
          Positioned(left: 0, right: 0, bottom: 0, child: _legendSheet()),
          if (_loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33FFFFFF),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  /// OpenStreetMap tiles through flutter_map.
  ///
  /// Google Maps needs a billed API key, and without one the SDK renders a grey
  /// grid with no error - the map simply looks broken. OSM tiles need no key, so
  /// the radar works on a fresh checkout. The tile server asks for a real
  /// User-Agent and sets a fair-use limit, which `userAgentPackageName` covers
  /// and this screen's traffic (one viewport per open) stays well inside.
  Widget _osmMap() {
    return FlutterMap(
      options: MapOptions(
        initialCenter: _initialTarget,
        initialZoom: 11,
        // OSM has no tiles past 19, and letting the user zoom further just
        // shows blank squares.
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.agro_alerta',
          maxNativeZoom: 19,
        ),
        // Weighted circles instead of fixed-size pins: the halo grows with the
        // number of independent confirmations, which is what "heat" means here.
        CircleLayer(
          circles: _hotspots
              .map((h) => CircleMarker(
                    point: LatLng(h.latitude, h.longitude),
                    radius: h.intensityRadiusMeters,
                    // Without this the radius would be read as screen pixels,
                    // so a focus would cover the same area at every zoom.
                    useRadiusInMeter: true,
                    color: h.color.withValues(alpha: 0.18),
                    borderColor: h.color.withValues(alpha: 0.55),
                    borderStrokeWidth: 2,
                  ))
              .toList(),
        ),
        MarkerLayer(
          markers: [
            for (final h in _hotspots)
              Marker(
                point: LatLng(h.latitude, h.longitude),
                width: 40,
                height: 40,
                child: _mapPin(
                  icon: Icons.warning_rounded,
                  color: h.color,
                  title: h.pest,
                  subtitle:
                      '${h.observerCount} produtores confirmaram · ${h.totalSpecimens} insetos',
                ),
              ),
            // The producer's own fields, so the focus has a reference point.
            for (final f in _myFields)
              Marker(
                point: LatLng(f.latitude, f.longitude),
                width: 40,
                height: 40,
                child: _mapPin(
                  icon: Icons.agriculture_rounded,
                  color: AgroTheme.statusGreen,
                  title: f.name,
                  subtitle: 'Seu talhão · ${f.cropType}',
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// A tappable pin. flutter_map has no InfoWindow equivalent, so the label
  /// that Google Maps drew on tap becomes a bottom sheet.
  Widget _mapPin({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
      child: Icon(icon, color: color, size: 32),
    );
  }

  Widget _simplifiedMap() {
    return Container(
      color: const Color(0xFFE5E9F0),
      child: ClipRect(
        child: InteractiveViewer(
          maxScale: 3.0,
          child: Stack(
            children: [
              const Positioned.fill(child: CustomPaint(painter: MockMapPainter())),
              ..._hotspots.asMap().entries.map((entry) {
                final h = entry.value;
                // Deterministic placement seeded by the focus identity, so the
                // same focus stays put between refreshes. It is a schematic, not
                // a projection - the banner says so.
                final rand = math.Random(
                  '${h.pest}${h.latitude.toStringAsFixed(3)}'.hashCode,
                );
                final dx = 60 + rand.nextDouble() * 220;
                final dy = 140 + rand.nextDouble() * 240;
                final size = 32.0 + h.observerCount.clamp(2, 10) * 4;

                return Positioned(
                  left: dx,
                  top: dy,
                  child: GestureDetector(
                    onTap: () => _showHotspotDetail(h),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            color: h.color.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: h.color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showHotspotDetail(Hotspot h) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(h.pest),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirmado por ${h.observerCount} produtores diferentes.'),
            const SizedBox(height: 6),
            Text('Total contado na região: ${h.totalSpecimens}.'),
            const SizedBox(height: 6),
            Text('Cultura afetada: ${h.cropType}.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  /// Leads with the actionable number when there is one, and only falls back to
  /// the privacy note when there is nothing near the producer.
  Widget _topBanner() {
    final threat = _closestThreat;

    if (_loadError != null) {
      return _banner(
        icon: Icons.cloud_off,
        text: _loadError!,
        tint: AgroTheme.statusYellowTint,
        strong: AgroTheme.statusYellow,
      );
    }

    if (threat != null) {
      final km = (threat.metres / 1000).toStringAsFixed(1);
      final close = threat.metres <= 20000;
      return _banner(
        icon: close ? Icons.warning_amber_rounded : Icons.travel_explore,
        text: 'Foco de ${threat.hotspot.pest} a $km km do seu talhão mais próximo.',
        tint: close ? AgroTheme.statusRedTint : AgroTheme.statusGreenTint,
        strong: close ? AgroTheme.statusRed : AgroTheme.statusGreen,
      );
    }

    return _banner(
      icon: Icons.shield_outlined,
      text: 'Focos agrupados por área. Ninguém vê a localização exata do seu talhão.',
      tint: AgroTheme.statusGreenTint,
      strong: AgroTheme.primaryDark,
    );
  }

  Widget _banner({
    required IconData icon,
    required String text,
    required Color tint,
    required Color strong,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: strong.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: strong, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: strong,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendSheet() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _hotspots.isEmpty
                ? 'Nenhum foco confirmado nos últimos 7 dias'
                : '${_hotspots.length} foco(s) confirmado(s) nos últimos 7 dias',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AgroTheme.textDark,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _LegendItem(color: AgroTheme.statusYellow, label: 'Lagartas'),
              _LegendItem(color: AgroTheme.statusRed, label: 'Percevejos'),
              _LegendItem(color: AgroTheme.legendPurple, label: 'Outros'),
              _LegendItem(color: AgroTheme.primary, label: 'Seus talhões'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'O círculo cresce conforme mais produtores confirmam a mesma praga. '
            'Toque para ver os detalhes.',
            style: TextStyle(fontSize: 13, color: AgroTheme.textGray, height: 1.3),
          ),
          // A politica de uso dos tiles do OSM exige credito visivel. Fica aqui
          // e nao sobreposto ao mapa: esta folha cobre o canto inferior, que e
          // onde o widget de atribuicao do flutter_map se desenha por padrao,
          // e o credito ficava escondido atras dela.
          const SizedBox(height: 10),
          const Text(
            'Mapa © OpenStreetMap',
            style: TextStyle(fontSize: 11, color: AgroTheme.textGray),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AgroTheme.textDark,
          ),
        ),
      ],
    );
  }
}

/// Schematic road/field background for the fallback view. Drawn rather than
/// tiled so it works with no network and no Maps key.
class MockMapPainter extends CustomPainter {
  const MockMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final field = Paint()..color = const Color(0xFFDCE6DA);
    final road = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final track = Paint()
      ..color = const Color(0xFFC9D3C7)
      ..strokeWidth = 3;

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE5E9F0));

    // Blocks of cropland.
    final rand = math.Random(7);
    for (var i = 0; i < 14; i++) {
      final left = rand.nextDouble() * size.width;
      final top = rand.nextDouble() * size.height;
      final w = 60 + rand.nextDouble() * 120;
      final h = 50 + rand.nextDouble() * 90;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, w, h),
          const Radius.circular(6),
        ),
        field,
      );
    }

    // Field tracks.
    for (var i = 0; i < 10; i++) {
      final y = size.height * (i / 10);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), track);
    }

    // Two main roads.
    canvas.drawLine(
      Offset(0, size.height * 0.62),
      Offset(size.width, size.height * 0.38),
      road,
    );
    canvas.drawLine(
      Offset(size.width * 0.33, 0),
      Offset(size.width * 0.52, size.height),
      road,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
