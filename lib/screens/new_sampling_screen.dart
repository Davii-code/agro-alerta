import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../models/field_model.dart';
import '../models/sampling_model.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/mip_service.dart';
import '../services/risk_calculator.dart';
import '../services/sync_service.dart';
import '../shared/theme.dart';
import '../widgets/counter_input.dart';
import '../widgets/pest_selector.dart';

/// How the GPS fix turned out. The old screen swallowed every failure, so a
/// producer whose location was denied silently recorded the Anápolis fallback
/// coordinate - which then broke the regional clustering downstream (RF06).
enum LocationState { capturing, captured, denied, serviceOff, failed }

class NewSamplingScreen extends StatefulWidget {
  const NewSamplingScreen({super.key});

  @override
  State<NewSamplingScreen> createState() => _NewSamplingScreenState();
}

class _NewSamplingScreenState extends State<NewSamplingScreen> {
  final _db = DatabaseService();
  final _auth = AuthService();
  final _mip = MipService();

  List<FieldModel> _fields = const [];
  String? _selectedFieldId;
  String _selectedPest = PestOption.all.first.species;
  String _selectedMethod = MethodSelector.methods.first.value;
  int _count = 0;

  LocationState _locationState = LocationState.capturing;
  double? _latitude;
  double? _longitude;
  bool _saving = false;
  bool _argumentsRead = false;

  @override
  void initState() {
    super.initState();
    _fields = _db.getFields();
    if (_fields.isNotEmpty) _selectedFieldId = _fields.first.id;
    _captureLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only once: the field passed in from the dashboard card should not
    // override a choice the producer made afterwards.
    if (_argumentsRead) return;
    _argumentsRead = true;
    final argId = ModalRoute.of(context)?.settings.arguments as String?;
    if (argId != null && _fields.any((f) => f.id == argId)) {
      setState(() => _selectedFieldId = argId);
    }
  }

  Future<void> _captureLocation() async {
    setState(() => _locationState = LocationState.capturing);

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _locationState = LocationState.serviceOff);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _locationState = LocationState.denied);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationState = LocationState.captured;
      });

      _autoSelectNearestField();
    } catch (_) {
      setState(() => _locationState = LocationState.failed);
    }
  }

  void _autoSelectNearestField() {
    if (_fields.isEmpty || _latitude == null || _longitude == null) return;
    if (_argumentsRead && ModalRoute.of(context)?.settings.arguments != null) {
      // The producer arrived from a specific field card; respect that.
      return;
    }

    var minDistance = double.infinity;
    var nearest = _fields.first.id;

    for (final field in _fields) {
      final d = Geolocator.distanceBetween(
        _latitude!,
        _longitude!,
        field.latitude,
        field.longitude,
      );
      if (d < minDistance) {
        minDistance = d;
        nearest = field.id;
      }
    }

    setState(() => _selectedFieldId = nearest);
  }

  FieldModel? get _selectedField =>
      _selectedFieldId == null ? null : _db.getField(_selectedFieldId!);

  /// Live preview of what this count means, so the producer sees the
  /// consequence before saving rather than after going back to the dashboard.
  RiskAssessment? get _preview {
    final field = _selectedField;
    if (field == null || _count <= 0) return null;
    return const RiskCalculator().assess(
      count: _count,
      pestSpecies: _selectedPest,
      parameters: _mip.parametersFor(
        culture: field.cropType,
        pestSpecies: _selectedPest,
      ),
      marketPrice: _mip.priceFor(field.cropType),
    );
  }

  Future<void> _save() async {
    final field = _selectedField;
    if (field == null) {
      _snack('Cadastre um talhão antes de contar pragas.', AgroTheme.statusRed);
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      _snack('Entre com sua conta para registrar.', AgroTheme.statusRed);
      return;
    }

    setState(() => _saving = true);

    final sampling = SamplingModel(
      id: const Uuid().v4(),
      fieldId: field.id,
      observerId: user.id,
      species: _selectedPest,
      count: _count,
      unit: 'insetos/planta',
      method: _selectedMethod,
      // No fix means the field centroid, not a hardcoded city. The producer is
      // told which one was used by the GPS banner above.
      latitude: _latitude ?? field.latitude,
      longitude: _longitude ?? field.longitude,
      createdAt: DateTime.now(),
      isSynced: false,
    );

    // Local write only. The network is SyncService's job (RF01).
    await _db.saveSampling(sampling);
    SyncService().triggerSync();

    if (!mounted) return;
    setState(() => _saving = false);
    await _showSuccess(sampling.count);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  /// Full-screen confirmation instead of a SnackBar that vanishes in 4 s.
  /// Saving a count is the whole point of the screen; it deserves an
  /// acknowledgement the producer can read at their own pace.
  Future<void> _showSuccess(int count) {
    final assessment = _preview;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AgroTheme.statusGreenTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 56,
                  color: AgroTheme.statusGreen,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Contagem salva',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AgroTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Guardamos $count no seu celular. '
                'Vai para o servidor sozinho quando houver internet.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: AgroTheme.textGray,
                  height: 1.4,
                ),
              ),
              if (assessment != null) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _tintFor(assessment.band),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        assessment.headline,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _strongFor(assessment.band),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        assessment.advice,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: _strongFor(assessment.band),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ENTENDI'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String message, Color colour) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: colour),
    );
  }

  static Color _tintFor(RiskBand b) => switch (b) {
        RiskBand.red => AgroTheme.statusRedTint,
        RiskBand.yellow => AgroTheme.statusYellowTint,
        RiskBand.green => AgroTheme.statusGreenTint,
      };

  static Color _strongFor(RiskBand b) => switch (b) {
        RiskBand.red => AgroTheme.statusRed,
        RiskBand.yellow => AgroTheme.statusYellow,
        RiskBand.green => AgroTheme.statusGreen,
      };

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Contar pragas')),
      body: SafeArea(
        child: Column(
          children: [
            _locationBanner(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _sectionTitle('1. Em qual talhão?'),
                  _fieldPicker(),
                  const SizedBox(height: 28),

                  _sectionTitle('2. Qual praga você viu?'),
                  PestSelector(
                    selectedSpecies: _selectedPest,
                    onChanged: (v) => setState(() => _selectedPest = v),
                  ),
                  const SizedBox(height: 28),

                  _sectionTitle('3. Quantas você contou?'),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AgroTheme.divider),
                    ),
                    child: CounterInput(
                      value: _count,
                      unitLabel: 'insetos por planta',
                      onChanged: (v) => setState(() => _count = v),
                    ),
                  ),
                  const SizedBox(height: 28),

                  _sectionTitle('4. Como você contou?'),
                  MethodSelector(
                    selected: _selectedMethod,
                    onChanged: (v) => setState(() => _selectedMethod = v),
                  ),

                  if (preview != null) ...[
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _tintFor(preview.band),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            preview.band == RiskBand.red
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline,
                            color: _strongFor(preview.band),
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  preview.headline,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: _strongFor(preview.band),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  preview.explanation,
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.3,
                                    color: _strongFor(preview.band),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.save_alt),
                label: Text(_saving ? 'SALVANDO...' : 'SALVAR CONTAGEM'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AgroTheme.textDark,
          ),
        ),
      );

  /// Says out loud where the coordinates came from. A silent fallback is what
  /// let every sampling land on the same pin and mask the RF06 defect.
  Widget _locationBanner() {
    final (icon, label, tint, strong, action) = switch (_locationState) {
      LocationState.capturing => (
          Icons.gps_not_fixed,
          'Procurando sua localização...',
          AgroTheme.infoTint,
          AgroTheme.info,
          false,
        ),
      LocationState.captured => (
          Icons.gps_fixed,
          'Localização capturada',
          AgroTheme.statusGreenTint,
          AgroTheme.statusGreen,
          false,
        ),
      LocationState.serviceOff => (
          Icons.location_disabled,
          'GPS desligado - usando o centro do talhão. Toque para tentar de novo.',
          AgroTheme.statusYellowTint,
          AgroTheme.statusYellow,
          true,
        ),
      LocationState.denied => (
          Icons.location_off,
          'Sem permissão de localização - usando o centro do talhão. Toque para permitir.',
          AgroTheme.statusYellowTint,
          AgroTheme.statusYellow,
          true,
        ),
      LocationState.failed => (
          Icons.location_searching,
          'Não achamos o sinal - usando o centro do talhão. Toque para tentar de novo.',
          AgroTheme.statusYellowTint,
          AgroTheme.statusYellow,
          true,
        ),
    };

    return Material(
      color: tint,
      child: InkWell(
        onTap: action ? _captureLocation : null,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: AgroTheme.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 22, color: strong),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: strong,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldPicker() {
    if (_fields.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AgroTheme.statusYellowTint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Você ainda não tem talhão cadastrado. '
          'Volte e toque em "Cadastrar meu talhão".',
          style: TextStyle(fontSize: 15, color: AgroTheme.statusYellow),
        ),
      );
    }

    return Column(
      children: _fields.map((field) {
        final selected = field.id == _selectedFieldId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: selected ? AgroTheme.statusGreenTint : Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _selectedFieldId = field.id),
              child: Container(
                constraints:
                    const BoxConstraints(minHeight: AgroTheme.minTouchTarget + 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? AgroTheme.primary : AgroTheme.divider,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? AgroTheme.primary : AgroTheme.textGray,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        field.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AgroTheme.textDark,
                        ),
                      ),
                    ),
                    Text(
                      field.cropType.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AgroTheme.textGray,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
