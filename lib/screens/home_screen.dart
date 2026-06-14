import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/field_model.dart';
import '../models/sampling_model.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';
import '../shared/theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseService();
  final _auth = AuthService();
  List<FieldModel> _fields = [];
  Map<String, int> _riskScores = {};
  Map<String, String> _mainPests = {};
  int _pendingSyncCount = 0;
  bool _isSyncing = false;

  // Grain Quotes matching print
  List<Map<String, dynamic>> _grainQuotes = [
    {'culture': 'SOJA', 'price': 129.71, 'source': 'CEPEA'},
    {'culture': 'MILHO', 'price': 65.32, 'source': 'CEPEA'},
    {'culture': 'ALGODÃO', 'price': 210.45, 'source': 'CEPEA'},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    List<FieldModel> fields = _db.getFields();

    // Pull fields from Supabase if online to sync local cache
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .from('fields')
            .select();
        if (response.isNotEmpty) {
          final remoteFields = response.map((f) => FieldModel.fromJson(f)).toList();
          await _db.clearFields();
          await _db.saveFields(remoteFields);
          fields = remoteFields;
        }
      }
    } catch (_) {
      // Offline fallback: keep local Hive cache
    }
    
    // Automatically seed fields if database is empty for demo/testing purposes
    if (fields.isEmpty) {
      final user = _auth.currentUser;
      final producerId = user?.id ?? 'mock-user-id';
      
      fields = [
        FieldModel(
          id: const Uuid().v4(),
          producerId: producerId,
          name: 'talhão teste',
          cropType: 'soja',
          plantingDate: DateTime.now().subtract(const Duration(days: 45)),
          latitude: -16.326,
          longitude: -48.953,
          createdAt: DateTime.now(),
        ),
      ];
      await _db.saveFields(fields);

      if (producerId != 'mock-user-id') {
        try {
          await Supabase.instance.client
              .from('fields')
              .insert(fields.map((f) => f.toJson()).toList());
        } catch (_) {
          // Ignore offline
        }
      }
    }

    // Recalculate risk scores dynamically using the NDE formula: NDE = (C x K) / (V x I)
    List<SamplingModel> samplings = _db.getSamplings();
    
    // Cleanup orphan samplings whose field does not exist locally to avoid sync lockups
    final List<String> fieldIds = fields.map((f) => f.id).toList();
    final List<SamplingModel> validSamplings = [];
    for (var sampling in samplings) {
      if (!fieldIds.contains(sampling.fieldId)) {
        await sampling.delete();
      } else {
        validSamplings.add(sampling);
      }
    }
    samplings = validSamplings;
    final Map<String, int> riskScores = {};
    final Map<String, String> mainPests = {};

    for (var field in fields) {
      final fieldSamplings = samplings.where((s) => s.fieldId == field.id).toList();
      if (fieldSamplings.isNotEmpty) {
        fieldSamplings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final latest = fieldSamplings.first;

        // Get market price for NDE
        double marketPrice = 120.0;
        final quote = _grainQuotes.firstWhere(
          (q) => q['culture'].toString().toLowerCase() == field.cropType.toLowerCase(),
          orElse: () => {'price': 120.0},
        );
        marketPrice = quote['price'] as double;

        // Calculate dynamic NDE
        double c = 130.0; // Control cost
        double k = 0.80;  // Efficacy
        double i = 0.02;  // Injury factor

        if (field.cropType == 'milho') {
          c = 150.0;
          i = 0.03;
        } else if (field.cropType == 'algodao') {
          c = 250.0;
          i = 0.05;
        }

        double nde = (c * k) / (marketPrice * i);
        
        // Calculate score percentage
        int score = 0;
        if (latest.count >= nde) {
          score = 100;
        } else if (latest.count > 0) {
          score = ((latest.count / nde) * 100).round().clamp(1, 99);
        }

        riskScores[field.id] = score;
        mainPests[field.id] = latest.species;
      } else {
        // No samplings
        riskScores[field.id] = 0;
        mainPests[field.id] = 'Sem dados';
      }
    }

    setState(() {
      _fields = fields;
      _riskScores = riskScores;
      _mainPests = mainPests;
      _pendingSyncCount = _db.getUnsyncedSamplings().length;
    });
  }

  Future<void> _handleSync() async {
    setState(() {
      _isSyncing = true;
    });
    
    await SyncService().triggerSync();
    await Future.delayed(const Duration(milliseconds: 800));
    await _loadData();
    
    setState(() {
      _isSyncing = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dados sincronizados com sucesso!'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    }
  }

  Future<void> _handleDeleteField(String fieldId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Talhão'),
        content: const Text('Tem certeza que deseja remover este talhão? Todos os dados associados serão perdidos localmente.'),
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

    if (confirm == true) {
      await _db.deleteField(fieldId);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Talhão excluído com sucesso.'),
            backgroundColor: Color(0xFFC62828),
          ),
        );
      }
    }
  }

  void _showAddFieldDialog() {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    String selectedCrop = 'soja';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Novo Talhão', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do Talhão',
                        hintText: 'Ex: Talhão Norte',
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Insira um nome' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedCrop,
                      decoration: const InputDecoration(labelText: 'Cultura'),
                      items: const [
                        DropdownMenuItem(value: 'soja', child: Text('Soja')),
                        DropdownMenuItem(value: 'milho', child: Text('Milho')),
                        DropdownMenuItem(value: 'algodao', child: Text('Algodão')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedCrop = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final user = _auth.currentUser;
                      final producerId = user?.id ?? 'mock-user-id';
                      
                      final newField = FieldModel(
                        id: const Uuid().v4(),
                        producerId: producerId,
                        name: nameController.text.trim(),
                        cropType: selectedCrop,
                        plantingDate: DateTime.now(),
                        latitude: -16.326,
                        longitude: -48.953,
                        createdAt: DateTime.now(),
                      );
                      
                      await _db.saveField(newField);
                      if (producerId != 'mock-user-id') {
                        try {
                          await Supabase.instance.client
                              .from('fields')
                              .insert(newField.toJson());
                        } catch (_) {
                          // Ignore if offline, fallback to sync/local
                        }
                      }
                      Navigator.pop(context);
                      _loadData();
                    }
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(int score) {
    if (score >= 70) return const Color(0xFFC62828); // Red
    if (score >= 40) return const Color(0xFFEF6C00); // Yellow/Orange
    return const Color(0xFF2E7D32); // Green
  }

  String _getStatusText(int score) {
    if (score >= 70) return 'VERMELHO';
    if (score >= 40) return 'AMARELO';
    return 'VERDE';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Agro Alerta GO',
          style: TextStyle(
            color: Color(0xFF212121),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          // 1. Yellow Status Bar
          Container(
            width: double.infinity,
            color: const Color(0xFFFFEB3B),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const Text(
              'MODO DE SINCRONIZAÇÃO OFFLINE ATIVO',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ),
          
          // 2. Grain Quotes horizontal scrolling row
          Container(
            height: 48,
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _grainQuotes.length,
              itemBuilder: (context, index) {
                final quote = _grainQuotes[index];
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.trending_up,
                        color: Color(0xFF2E7D32),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${quote['culture']}: R\$ ${quote['price'].toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF212121),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${quote['source']})',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF757575),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 3. Fields List Area
          Expanded(
            child: _fields.isEmpty
                ? const Center(
                    child: Text('Nenhum talhão cadastrado.'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _fields.length,
                    itemBuilder: (context, index) {
                      final field = _fields[index];
                      final score = _riskScores[field.id] ?? 0;
                      final statusColor = _getStatusColor(score);
                      final statusText = _getStatusText(score);
                      final pest = _mainPests[field.id] ?? 'Sem dados';

                      return Card(
                        color: Colors.white,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Row: Title, Badges and Delete button
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Left side: Title and Crop Badge
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          field.name,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF212121),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        // Crop Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFECEFF1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            field.cropType.toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF546E7A),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Right side: Status, percentage and Trash
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          // Status Chip
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusColor.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              statusText,
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          // Percentage Score
                                          Text(
                                            '$score%',
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      // Trash Icon
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Color(0xFFC62828), size: 22),
                                        onPressed: () => _handleDeleteField(field.id),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Middle Row: Weather container
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3F2FD),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: const [
                                    Text(
                                      '☀️ Ensolarado 27.2°C',
                                      style: TextStyle(
                                        color: Color(0xFF1E88E5),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      '💧 78%',
                                      style: TextStyle(
                                        color: Color(0xFF1E88E5),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Bottom Row: History and Arrow navigation
                              InkWell(
                                onTap: () async {
                                  // Navigate to amostragem adding screen pre-filled with this field
                                  await Navigator.pushNamed(context, '/new-sampling', arguments: field.id);
                                  _loadData();
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.show_chart,
                                          color: Color(0xFF757575),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          pest == 'Sem dados' ? 'Sem dados recentes' : 'Último foco: $pest',
                                          style: const TextStyle(
                                            color: Color(0xFF757575),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Color(0xFF757575),
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          
          // 4. FAB Row at bottom above bottomNavigationBar
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: SizedBox(
              width: 180,
              child: FloatingActionButton.extended(
                onPressed: _showAddFieldDialog,
                backgroundColor: const Color(0xFF2E7D32),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                label: const Text(
                  'NOVO TALHÃO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    fontSize: 12,
                  ),
                ),
                icon: const Icon(Icons.add, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF2E7D32),
        unselectedItemColor: const Color(0xFF757575),
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Painel',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.radar_outlined),
            label: 'Radar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            label: 'Histórico',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sync_outlined),
            label: 'Atualizar',
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            Navigator.pushNamed(context, '/radar');
          } else if (index == 2) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Histórico Offline'),
                content: Text('Atualmente você possui $_pendingSyncCount monitoramentos pendentes de sincronização local.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          } else if (index == 3) {
            if (!_isSyncing) {
              _handleSync();
            }
          }
        },
      ),
    );
  }
}
