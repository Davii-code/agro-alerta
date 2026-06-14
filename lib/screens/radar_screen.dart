import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  bool _isOfflineMode = true; // Default to offline high-fidelity vector map
  bool _isLoading = false;

  // Localized Hotspots simulating real data
  List<Map<String, dynamic>> _hotspots = [
    {
      'pest': 'Lagarta-do-cartucho',
      'count': 12,
      'latitude': -16.324,
      'longitude': -48.951,
      'category': 'Lagartas',
      'color': const Color(0xFFEF6C00), // Orange
      'offset': const Offset(120, 160),
    },
    {
      'pest': 'Percevejo-marrom',
      'count': 8,
      'latitude': -16.328,
      'longitude': -48.955,
      'category': 'Percevejos',
      'color': const Color(0xFFC62828), // Red
      'offset': const Offset(240, 220),
    },
    {
      'pest': 'Cigarrinha-do-milho',
      'count': 15,
      'latitude': -16.320,
      'longitude': -48.948,
      'category': 'Outros',
      'color': const Color(0xFF7B1FA2), // Purple
      'offset': const Offset(180, 280),
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchHotspots();
  }

  Future<void> _fetchHotspots() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.rpc('get_regional_hotspots', params: {
        'radius_meters': 5000.0,
        'min_observers': 2,
      });

      if (response != null && response is List && response.isNotEmpty) {
        final List<Map<String, dynamic>> loaded = [];
        for (var item in response) {
          final pestName = item['pest_name'] as String;
          final count = (item['observer_count'] as num).toInt();
          
          // Determine coordinates from PostGIS geography point
          double lat = -16.326;
          double lon = -48.953;
          if (item['location'] != null && item['location'] is Map) {
            final coords = item['location']['coordinates'] as List?;
            if (coords != null && coords.length >= 2) {
              lon = (coords[0] as num).toDouble();
              lat = (coords[1] as num).toDouble();
            }
          }

          // Category mapping
          String category = 'Outros';
          Color color = const Color(0xFF7B1FA2);
          if (pestName.toLowerCase().contains('lagarta')) {
            category = 'Lagartas';
            color = const Color(0xFFEF6C00);
          } else if (pestName.toLowerCase().contains('percevejo')) {
            category = 'Percevejos';
            color = const Color(0xFFC62828);
          }

          // Distribute visually on screen
          final rand = math.Random(pestName.hashCode);
          loaded.add({
            'pest': pestName,
            'count': count,
            'latitude': lat,
            'longitude': lon,
            'category': category,
            'color': color,
            'offset': Offset(100.0 + rand.nextDouble() * 200, 150.0 + rand.nextDouble() * 200),
          });
        }

        setState(() {
          _hotspots = loaded;
        });
      }
    } catch (e) {
      // Offline fallback: keep pre-configured mock focuses
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1B5E20)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Radar Regional MIP',
          style: TextStyle(
            color: Color(0xFF212121),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF1B5E20)),
            onPressed: _isLoading ? null : _fetchHotspots,
          ),
          IconButton(
            icon: Icon(
              _isOfflineMode ? Icons.signal_wifi_off : Icons.map_outlined,
              color: const Color(0xFF1B5E20),
            ),
            onPressed: () {
              setState(() {
                _isOfflineMode = !_isOfflineMode;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Map Content (Online GoogleMap or Custom Mock Painter)
          Positioned.fill(
            child: _isOfflineMode
                ? Container(
                    color: const Color(0xFFE5E9F0),
                    child: ClipRect(
                      child: InteractiveViewer(
                        maxScale: 3.0,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: MockMapPainter(),
                              ),
                            ),
                            // Overlay Hotspots
                            ..._hotspots.map((h) {
                              final offset = h['offset'] as Offset;
                              final color = h['color'] as Color;
                              return Positioned(
                                left: offset.dx - 20,
                                top: offset.dy - 20,
                                child: GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(h['pest']),
                                        content: Text(
                                          'Categoria: ${h['category']}\n'
                                          'Focos Identificados: ${h['count']}\n'
                                          'Coordenadas: ${h['latitude'].toStringAsFixed(4)}, ${h['longitude'].toStringAsFixed(4)}',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('Fechar'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Outer Pulse
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.25),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      // Inner Glow
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.5),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      // Solid center dot
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 1.5),
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
                  )
                : GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(-16.326, -48.953), // Nerópolis / Anápolis region
                      zoom: 12,
                    ),
                    myLocationEnabled: true,
                    zoomControlsEnabled: false,
                    markers: _hotspots.map((h) {
                      return Marker(
                        markerId: MarkerId(h['pest'] + h['latitude'].toString()),
                        position: LatLng(h['latitude'] as double, h['longitude'] as double),
                        infoWindow: InfoWindow(
                          title: h['pest'],
                          snippet: 'Grupo: ${h['category']} - Focos: ${h['count']}',
                        ),
                      );
                    }).toSet(),
                  ),
          ),

          // 2. Green Informational Box (Top Banner)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9), // Mint green
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC8E6C9), width: 1),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.security,
                    color: Color(0xFF2E7D32),
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'VISÃO ANÔNIMA: Focos agrupados por grade territorial para proteção e privacidade do produtor.',
                      style: TextStyle(
                        color: Color(0xFF1B5E20),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Bottom Legend Card Sheet
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  const Text(
                    'LEGENDA DE RISCO REGIONAL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF37474F),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Row of bullets
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildLegendItem(const Color(0xFFEF6C00), 'Lagartas'),
                      _buildLegendItem(const Color(0xFFC62828), 'Percevejos'),
                      _buildLegendItem(const Color(0xFF7B1FA2), 'Outros'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Footnote
                  const Center(
                    child: Text(
                      '* Toque nos círculos ou marcadores para ver a intensidade e número de focos',
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF757575),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.white24,
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF1B5E20)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF212121),
          ),
        ),
      ],
    );
  }
}

// Custom Painter to draw a clean, light-colored map background of regional roads and fields
class MockMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Background green agricultural lands and main routes
    final paintFields = Paint()
      ..color = const Color(0xFFDFEAD5)
      ..style = PaintingStyle.fill;
    
    // Draw some green zones representing farms
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * 0.4, size.height * 0.3), paintFields);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.6, size.height * 0.1, size.width * 0.35, size.height * 0.45), paintFields);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.1, size.height * 0.6, size.width * 0.5, size.height * 0.35), paintFields);

    // River
    final paintRiver = Paint()
      ..color = const Color(0xFFB3E5FC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    final pathRiver = Path();
    pathRiver.moveTo(0, size.height * 0.4);
    pathRiver.quadraticBezierTo(
      size.width * 0.3, size.height * 0.35,
      size.width * 0.6, size.height * 0.5,
    );
    pathRiver.quadraticBezierTo(
      size.width * 0.8, size.height * 0.6,
      size.width, size.height * 0.55,
    );
    canvas.drawPath(pathRiver, paintRiver);

    // Highways / Roads (GO-080, GO-222, GO-466)
    final paintRoadBorder = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    final paintRoadCenter = Paint()
      ..color = const Color(0xFFFFD54F) // Yellow Highway fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // GO-080
    final pathGO080 = Path();
    pathGO080.moveTo(size.width * 0.1, 0);
    pathGO080.lineTo(size.width * 0.5, size.height * 0.5);
    pathGO080.lineTo(size.width * 0.7, size.height);
    canvas.drawPath(pathGO080, paintRoadBorder);
    canvas.drawPath(pathGO080, paintRoadCenter);

    // GO-222
    final pathGO222 = Path();
    pathGO222.moveTo(0, size.height * 0.5);
    pathGO222.lineTo(size.width * 0.5, size.height * 0.5);
    pathGO222.lineTo(size.width, size.height * 0.6);
    canvas.drawPath(pathGO222, paintRoadBorder);
    canvas.drawPath(pathGO222, paintRoadCenter);

    // GO-466
    final pathGO466 = Path();
    pathGO466.moveTo(size.width * 0.5, size.height * 0.5);
    pathGO466.lineTo(size.width * 0.45, size.height);
    canvas.drawPath(pathGO466, paintRoadBorder);
    canvas.drawPath(pathGO466, paintRoadCenter);

    // Draw City Label: Nerópolis
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Nerópolis text
    textPainter.text = const TextSpan(
      text: 'Nerópolis',
      style: TextStyle(
        color: Color(0xFF37474F),
        fontSize: 14,
        fontWeight: FontWeight.bold,
        backgroundColor: Colors.white70,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width * 0.45 - 20, size.height * 0.5 - 24));

    // Highway labels
    const textStyleLabel = TextStyle(
      color: Colors.white,
      fontSize: 8,
      fontWeight: FontWeight.bold,
    );

    final labelPaint = Paint()..color = const Color(0xFFC62828);

    // GO-080 label box
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.2, 80, 40, 14), const Radius.circular(3)), labelPaint);
    textPainter.text = const TextSpan(text: 'GO-080', style: textStyleLabel);
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width * 0.2 + 4, 81));

    // GO-222 label box
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(60, size.height * 0.5 - 24, 40, 14), const Radius.circular(3)), labelPaint);
    textPainter.text = const TextSpan(text: 'GO-222', style: textStyleLabel);
    textPainter.layout();
    textPainter.paint(canvas, Offset(64, size.height * 0.5 - 23));

    // GO-466 label box
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.45 - 10, size.height * 0.75, 40, 14), const Radius.circular(3)), labelPaint);
    textPainter.text = const TextSpan(text: 'GO-466', style: textStyleLabel);
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width * 0.45 - 6, size.height * 0.75 + 1));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
