import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/field_model.dart';
import '../models/mip_parameter_model.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/mip_service.dart';
import '../services/risk_calculator.dart';
import '../services/sync_service.dart';
import '../shared/theme.dart';
import '../widgets/field_card.dart';
import '../widgets/sync_indicator.dart';

/// The producer's dashboard: one card per field, each carrying its decision.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseService();
  final _auth = AuthService();
  final _mip = MipService();
  final _calculator = const RiskCalculator();

  List<FieldModel> _fields = const [];
  Map<String, RiskAssessment> _assessments = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    var fields = _db.getFields();

    // Pull the server copy when possible. Anything that fails here leaves the
    // Hive cache untouched, which is the offline path.
    if (_isOnline) {
      try {
        final response = await Supabase.instance.client.from('fields').select();
        if (response.isNotEmpty) {
          final remote =
              response.map<FieldModel>((f) => FieldModel.fromJson(f)).toList();

          // Locally created fields that have not been pushed yet must survive a
          // refresh; clearing the box outright used to delete them.
          final pendingLocal = _db.getUnsyncedFields();
          final remoteIds = remote.map((f) => f.id).toSet();

          await _db.clearFields();
          await _db.saveFields(remote);
          await _db.saveFields(
            pendingLocal.where((f) => !remoteIds.contains(f.id)).toList(),
          );
          fields = _db.getFields();
        }
      } catch (_) {
        // Offline: keep the local cache.
      }
    }

    await _db.pruneOrphanSamplings();

    // Reference data for the NDE. Cheap when already cached.
    await _mip.refresh();

    final assessments = <String, RiskAssessment>{};
    for (final field in fields) {
      final latest = _db.getLatestSamplingForField(field.id);
      if (latest == null) continue;

      final parameters = _mip.parametersFor(
        culture: field.cropType,
        pestSpecies: latest.species,
      );

      final assessment = _calculator.assess(
        count: latest.count,
        pestSpecies: latest.species,
        parameters: parameters,
        marketPrice: _mip.priceFor(field.cropType),
      );

      assessments[field.id] = assessment;
    }

    if (!mounted) return;
    setState(() {
      _fields = fields;
      _assessments = assessments;
      _loading = false;
    });

    // The score is now persisted rather than recomputed and thrown away, so the
    // dashboard, the Python pipeline and the Edge Function all read one number.
    _persistScores(assessments);
  }

  bool get _isOnline {
    try {
      Supabase.instance.client;
      return _auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// Fire-and-forget upsert into risk_scores. A failure is not worth blocking
  /// or reporting: the local value is already on screen and the pipeline
  /// recomputes server-side anyway.
  void _persistScores(Map<String, RiskAssessment> assessments) async {
    if (!_isOnline || assessments.isEmpty) return;
    try {
      await Supabase.instance.client.from('risk_scores').upsert(
        assessments.entries
            .map((e) => {
                  'field_id': e.key,
                  'score': e.value.score,
                  'main_pest': e.value.pestSpecies,
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                })
            .toList(),
        onConflict: 'field_id',
      );
    } catch (_) {
      // Ignored on purpose.
    }
  }

  Future<void> _handleSync() async {
    final state = await SyncService().triggerSync();
    await _loadData();
    if (!mounted) return;

    // Reports what actually happened. The old handler always said
    // "Dados sincronizados com sucesso!", including when the batch had failed.
    final (message, colour) = switch (state.status) {
      SyncStatus.upToDate => ('Tudo enviado.', AgroTheme.statusGreen),
      SyncStatus.syncing => ('Enviando...', AgroTheme.info),
      SyncStatus.offlinePending => (
          'Sem internet. Seus ${state.pending} registros estão guardados.',
          AgroTheme.statusYellow
        ),
      SyncStatus.blockedNoAccount => (
          state.message ?? 'Entre com sua conta para enviar.',
          AgroTheme.statusRed
        ),
      SyncStatus.error => (
          state.message ?? 'Não foi possível enviar agora.',
          AgroTheme.statusRed
        ),
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: colour),
    );
  }

  Future<void> _handleDeleteField(FieldModel field) async {
    final samplingCount = _db.getSamplingsForField(field.id).length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir talhão'),
        content: Text(
          samplingCount == 0
              ? 'Remover o talhão "${field.name}"?'
              : 'Remover o talhão "${field.name}"? '
                  'As $samplingCount contagens feitas nele também serão apagadas do celular.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AgroTheme.statusRed),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _db.deleteField(field.id);
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Talhão excluído.'),
        backgroundColor: AgroTheme.textDark,
      ),
    );
  }

  Future<void> _showAddFieldDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    String selectedCrop = 'soja';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Novo talhão'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nome do talhão',
                    hintText: 'Ex: Talhão do fundo',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Dê um nome ao talhão'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedCrop,
                  decoration: const InputDecoration(labelText: 'O que está plantado'),
                  items: const [
                    DropdownMenuItem(value: 'soja', child: Text('Soja')),
                    DropdownMenuItem(value: 'milho', child: Text('Milho')),
                    DropdownMenuItem(value: 'algodao', child: Text('Algodão')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedCrop = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(120, 48)),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    final typedName = nameController.text.trim();
    nameController.dispose();
    if (saved != true) return;

    final user = _auth.currentUser;
    final field = FieldModel(
      id: const Uuid().v4(),
      producerId: user?.id ?? 'mock-user-id',
      name: typedName,
      cropType: selectedCrop,
      plantingDate: DateTime.now(),
      // Placeholder centroid until the first GPS-stamped sampling lands on it.
      latitude: -16.326,
      longitude: -48.953,
      createdAt: DateTime.now(),
      // Queued like any other local write; SyncService pushes it.
      isSynced: false,
    );

    await _db.saveField(field);
    await SyncService().triggerSync();
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agro Alerta GO'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () async {
              await _auth.signOut();
              if (!context.mounted) return;
              Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SyncIndicator(onTapRetry: _handleSync),
          _priceTicker(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _fields.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          itemCount: _fields.length,
                          itemBuilder: (context, i) {
                            final field = _fields[i];
                            return FieldCard(
                              field: field,
                              assessment: _assessments[field.id],
                              onCount: () async {
                                await Navigator.pushNamed(
                                  context,
                                  '/new-sampling',
                                  arguments: field.id,
                                );
                                _loadData();
                              },
                              onHistory: () => Navigator.pushNamed(
                                context,
                                '/history',
                                arguments: field.id,
                              ),
                              onDelete: () => _handleDeleteField(field),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: _fields.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddFieldDialog,
              backgroundColor: AgroTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text(
                'NOVO TALHÃO',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Meus talhões',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.radar_outlined),
            label: 'Radar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            label: 'Contagens',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sync_outlined),
            label: 'Enviar',
          ),
        ],
        onTap: (index) async {
          switch (index) {
            case 1:
              await Navigator.pushNamed(context, '/radar');
              _loadData();
            case 2:
              await Navigator.pushNamed(context, '/history');
              _loadData();
            case 3:
              await _handleSync();
          }
        },
      ),
    );
  }

  /// Grain prices, now read from market_prices instead of a literal list, with
  /// the date of the quote visible so a stale number is recognisable as stale.
  Widget _priceTicker() {
    final prices = _mip.prices.isNotEmpty
        ? _mip.prices
        : const <MarketPrice>[];

    if (prices.isEmpty) return const SizedBox(height: 8);

    return SizedBox(
      height: 62,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        itemCount: prices.length,
        itemBuilder: (context, i) {
          final p = prices[i];
          return Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AgroTheme.divider),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_cropLabel(p.culture)}  R\$ ${p.pricePerSack.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AgroTheme.textDark,
                  ),
                ),
                Text(
                  '${p.source} · ${_shortDate(p.updatedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AgroTheme.textGray,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _cropLabel(String c) => switch (c) {
        'milho' => 'Milho',
        'algodao' => 'Algodão',
        'soja' => 'Soja',
        _ => c,
      };

  static String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                color: AgroTheme.statusGreenTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.agriculture_outlined,
                size: 60,
                color: AgroTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Vamos começar pelo seu talhão',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AgroTheme.textDark,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Cadastre a área que você quer acompanhar. '
              'Depois é só contar as pragas quando estiver na lavoura.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: AgroTheme.textGray,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _showAddFieldDialog,
              icon: const Icon(Icons.add),
              label: const Text('CADASTRAR MEU TALHÃO'),
            ),
          ],
        ),
      ),
    );
  }
}
