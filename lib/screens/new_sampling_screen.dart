import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../models/field_model.dart';
import '../models/sampling_model.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../shared/theme.dart';

class NewSamplingScreen extends StatefulWidget {
  const NewSamplingScreen({super.key});

  @override
  State<NewSamplingScreen> createState() => _NewSamplingScreenState();
}

class _NewSamplingScreenState extends State<NewSamplingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseService();
  final _auth = AuthService();

  List<FieldModel> _fields = [];
  String? _selectedFieldId;
  String _selectedPest = 'Lagarta-do-cartucho';
  final _countController = TextEditingController(text: '0');
  String _selectedMethod = 'Pano de batida';
  
  double _latitude = -16.326;
  double _longitude = -48.953;

  final List<String> _pests = [
    'Lagarta-do-cartucho',
    'Cigarrinha-do-milho',
    'Percevejo-marrom',
    'Outros',
  ];

  final List<String> _methods = [
    'Pano de batida',
    'Visual',
    'Armadilha',
  ];

  @override
  void initState() {
    super.initState();
    _fields = _db.getFields();
    if (_fields.isNotEmpty) {
      _selectedFieldId = _fields.first.id;
    }
    _captureLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final argId = ModalRoute.of(context)!.settings.arguments as String?;
    if (argId != null) {
      _selectedFieldId = argId;
    }
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  Future<void> _captureLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });

      _autoSelectFieldByLocation();
    } catch (e) {
      // Fail silently, use fallback
    }
  }

  void _autoSelectFieldByLocation() {
    if (_fields.isEmpty) return;
    
    // Find field closest to GPS coordinates
    double minDistance = double.infinity;
    String nearestFieldId = _fields.first.id;
    
    for (var field in _fields) {
      double dist = Geolocator.distanceBetween(
        _latitude,
        _longitude,
        field.latitude,
        field.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearestFieldId = field.id;
      }
    }
    
    setState(() {
      _selectedFieldId = nearestFieldId;
    });
  }

  Future<void> _saveSampling() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedFieldId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum talhão cadastrado. Crie um talhão primeiro.'),
          backgroundColor: AgroTheme.statusRed,
        ),
      );
      return;
    }

    final count = int.tryParse(_countController.text) ?? 0;
    final user = _auth.currentUser;
    final observerId = user?.id ?? 'mock-user-id';

    final sampling = SamplingModel(
      id: const Uuid().v4(),
      fieldId: _selectedFieldId!,
      observerId: observerId,
      species: _selectedPest,
      count: count,
      unit: 'insetos/planta',
      method: _selectedMethod,
      latitude: _latitude,
      longitude: _longitude,
      createdAt: DateTime.now(),
      isSynced: false,
    );

    // Save locally
    await _db.saveSampling(sampling);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Amostragem salva localmente com sucesso!'),
          backgroundColor: AgroTheme.primary,
        ),
      );
      Navigator.pop(context, true);
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
          'Nova Amostragem',
          style: TextStyle(
            color: Color(0xFF212121),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                
                // 1. PRAGA IDENTIFICADA Label
                const Text(
                  'PRAGA IDENTIFICADA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5C6B61),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                
                // Praga dropdown field
                DropdownButtonFormField<String>(
                  value: _selectedPest,
                  items: _pests.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text(
                        p,
                        style: const TextStyle(
                          color: Color(0xFF212121),
                          fontSize: 15,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedPest = val ?? _pests.first;
                    });
                  },
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF757575)),
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 2. QUANTIDADE ENCONTRADA Label
                const Text(
                  'QUANTIDADE ENCONTRADA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5C6B61),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                
                // Quantidade Text Field
                TextFormField(
                  controller: _countController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 1.5),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, informe a quantidade';
                    }
                    if (int.tryParse(value) == null) {
                      return 'Apenas números são permitidos';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // 3. MÉTODO DE COLETA Label
                const Text(
                  'MÉTODO DE COLETA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5C6B61),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                
                // Método Dropdown Field
                DropdownButtonFormField<String>(
                  value: _selectedMethod,
                  items: _methods.map((m) {
                    return DropdownMenuItem(
                      value: m,
                      child: Text(
                        m,
                        style: const TextStyle(
                          color: Color(0xFF212121),
                          fontSize: 15,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedMethod = val ?? _methods.first;
                    });
                  },
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF757575)),
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // SALVAR AMOSTRAGEM Button
                ElevatedButton(
                  onPressed: _saveSampling,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'SALVAR AMOSTRAGEM',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Funciona sem internet Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.check_circle,
                      color: Color(0xFF2E7D32),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Funciona sem internet',
                      style: TextStyle(
                        color: Color(0xFF757575),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
