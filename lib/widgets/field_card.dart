import 'package:flutter/material.dart';
import '../models/field_model.dart';
import '../services/risk_calculator.dart';
import '../shared/theme.dart';

/// One field on the dashboard.
///
/// The old card led with a percentage ("78%"), which tells a producer nothing.
/// This one leads with the decision - APLICAR AGORA / FICAR DE OLHO / TUDO CERTO -
/// then the reason in one sentence, and only then the numbers. The score is kept
/// as a small caption for the extensionist, not as the headline.
class FieldCard extends StatelessWidget {
  final FieldModel field;

  /// Null when the field has no sampling yet.
  final RiskAssessment? assessment;

  final VoidCallback onCount;
  final VoidCallback onDelete;
  final VoidCallback? onHistory;

  const FieldCard({
    super.key,
    required this.field,
    required this.assessment,
    required this.onCount,
    required this.onDelete,
    this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final band = assessment?.band;
    final colors = _colorsFor(band);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AgroTheme.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner. Full-width colour is the fastest thing to read at arm's
          // length in the sun - much faster than a small coloured chip.
          Container(
            width: double.infinity,
            color: colors.tint,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.strong,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(colors.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assessment?.headline ?? 'SEM CONTAGEM',
                        style: TextStyle(
                          color: colors.strong,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        assessment?.advice ??
                            'Faça a primeira contagem para saber o risco.',
                        style: TextStyle(
                          color: colors.strong.withValues(alpha: 0.92),
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            field.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AgroTheme.textDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _Chip(label: _cropLabel(field.cropType)),
                              if (!field.isSynced) ...[
                                const SizedBox(width: 8),
                                const _Chip(
                                  label: 'NÃO ENVIADO',
                                  color: AgroTheme.statusYellow,
                                  tint: AgroTheme.statusYellowTint,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 26),
                      color: AgroTheme.statusRed,
                      tooltip: 'Excluir talhão',
                      onPressed: onDelete,
                    ),
                  ],
                ),

                if (assessment != null) ...[
                  const SizedBox(height: 12),
                  // The one sentence that makes the traffic light legible:
                  // "Você contou 12. O prejuízo começa em 8."
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AgroTheme.lightBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          assessment!.explanation,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AgroTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Praga: ${assessment!.pestSpecies}  ·  '
                          'Índice ${assessment!.score}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AgroTheme.textGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: onCount,
                        icon: const Icon(Icons.add_circle_outline, size: 22),
                        label: const Text('Contar praga'),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (onHistory != null)
                      TextButton(
                        onPressed: onHistory,
                        child: const Text('Ver histórico'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _cropLabel(String cropType) {
    switch (cropType) {
      case 'milho':
        return 'MILHO';
      case 'algodao':
        return 'ALGODÃO';
      case 'soja':
        return 'SOJA';
      default:
        return cropType.toUpperCase();
    }
  }

  _BandColors _colorsFor(RiskBand? band) {
    switch (band) {
      case RiskBand.red:
        return const _BandColors(
          strong: AgroTheme.statusRed,
          tint: AgroTheme.statusRedTint,
          icon: Icons.warning_amber_rounded,
        );
      case RiskBand.yellow:
        return const _BandColors(
          strong: AgroTheme.statusYellow,
          tint: AgroTheme.statusYellowTint,
          icon: Icons.visibility_outlined,
        );
      case RiskBand.green:
        return const _BandColors(
          strong: AgroTheme.statusGreen,
          tint: AgroTheme.statusGreenTint,
          icon: Icons.check_circle_outline,
        );
      case null:
        return const _BandColors(
          strong: AgroTheme.textGray,
          tint: Color(0xFFEFF1F0),
          icon: Icons.help_outline,
        );
    }
  }
}

class _BandColors {
  final Color strong;
  final Color tint;
  final IconData icon;

  const _BandColors({
    required this.strong,
    required this.tint,
    required this.icon,
  });
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color tint;

  const _Chip({
    required this.label,
    this.color = AgroTheme.textGray,
    this.tint = const Color(0xFFEFF1F0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
