import 'package:flutter/material.dart';
import '../models/field_model.dart';
import '../models/sampling_model.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../shared/theme.dart';
import '../widgets/sync_indicator.dart';

/// Every count the producer has made, newest first.
///
/// The "Histórico" tab used to open an AlertDialog containing a single number
/// ("você possui N monitoramentos pendentes"). That answered a question nobody
/// asked. This screen answers the real ones: what did I count, where, when, and
/// did it reach the server.
class HistoryScreen extends StatefulWidget {
  /// When set, only this field's samplings are listed.
  final String? fieldId;

  const HistoryScreen({super.key, this.fieldId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _db = DatabaseService();

  List<SamplingModel> _samplings = const [];
  Map<String, FieldModel> _fieldsById = const {};

  static const _months = [
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
  ];

  /// Hand-rolled instead of package:intl. The whole locale need of this app is
  /// one date line, and pulling in intl means matching whatever version the
  /// Flutter SDK pins plus an initializeDateFormatting() call at startup.
  static String _formatDate(DateTime d) {
    final today = DateTime.now();
    final isToday =
        d.year == today.year && d.month == today.month && d.day == today.day;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');

    if (isToday) return 'Hoje às $hh:$mm';
    return '${d.day} de ${_months[d.month - 1]} às $hh:$mm';
  }

  /// Loading happens in didChangeDependencies, not initState: _load reads the
  /// route arguments, and ModalRoute.of(context) is not available that early.
  void _load() {
    final fieldId = widget.fieldId ??
        (ModalRoute.of(context)?.settings.arguments as String?);

    setState(() {
      _fieldsById = {for (final f in _db.getFields()) f.id: f};
      _samplings = fieldId == null
          ? _db.getSamplingsSorted()
          : _db.getSamplingsForField(fieldId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minhas contagens')),
      body: Column(
        children: [
          SyncIndicator(onTapRetry: () async {
            await SyncService().triggerSync();
            // _load() reads ModalRoute.of(context); the screen may have been
            // popped while the sync was in flight.
            if (!mounted) return;
            _load();
          }),
          Expanded(
            child: _samplings.isEmpty ? _empty() : _list(),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 76, color: AgroTheme.divider),
            const SizedBox(height: 20),
            const Text(
              'Nenhuma contagem ainda',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AgroTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Assim que você contar pragas em um talhão, '
              'o registro aparece aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AgroTheme.textGray),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/new-sampling'),
              icon: const Icon(Icons.add),
              label: const Text('CONTAR PRAGA AGORA'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _samplings.length,
      itemBuilder: (context, index) {
        final s = _samplings[index];
        final field = _fieldsById[s.fieldId];
        final synced = s.isSynced;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AgroTheme.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AgroTheme.lightBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${s.count}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AgroTheme.textDark,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.species,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AgroTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      field?.name ?? 'Talhão removido',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AgroTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDate(s.createdAt)} · ${s.method}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AgroTheme.textGray,
                      ),
                    ),
                  ],
                ),
              ),
              // Per-item delivery state. A single global counter could not tell
              // the producer WHICH record was still stuck on the phone.
              Column(
                children: [
                  Icon(
                    synced ? Icons.cloud_done_outlined : Icons.phone_android,
                    size: 22,
                    color: synced ? AgroTheme.statusGreen : AgroTheme.statusYellow,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    synced ? 'Enviado' : 'No celular',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          synced ? AgroTheme.statusGreen : AgroTheme.statusYellow,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
