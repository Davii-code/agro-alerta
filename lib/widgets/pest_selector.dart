import 'package:flutter/material.dart';
import '../shared/theme.dart';

/// A pest the app knows how to score.
///
/// The species strings here are the contract with the rest of the system: they
/// are stored in samplings.species, looked up in mip_parameters.pest_species,
/// and matched in pest_crop_map. A typo here silently degrades the NDE to the
/// per-crop wildcard, so they must stay identical to the seeds in
/// supabase/migrations/03_mip_and_pest_map.sql and to MIP_FALLBACK_PARAMETERS
/// in pipeline/ingestion_pipeline.py.
class PestOption {
  final String species;

  /// What the producer calls it.
  final String commonName;

  /// One-line recognition hint, since many producers know the damage rather
  /// than the insect.
  final String hint;

  final IconData icon;
  final Color color;

  const PestOption({
    required this.species,
    required this.commonName,
    required this.hint,
    required this.icon,
    required this.color,
  });

  static const List<PestOption> all = [
    PestOption(
      species: 'Lagarta-do-cartucho',
      commonName: 'Lagarta do cartucho',
      hint: 'Fura o cartucho do milho, deixa serragem',
      icon: Icons.pest_control,
      color: Color(0xFFB25000),
    ),
    PestOption(
      species: 'Lagarta-da-soja',
      commonName: 'Lagarta da soja',
      hint: 'Come as folhas, deixa a planta rendilhada',
      icon: Icons.grass,
      color: Color(0xFF2E7D32),
    ),
    PestOption(
      species: 'Cigarrinha-do-milho',
      commonName: 'Cigarrinha do milho',
      hint: 'Inseto pequeno que salta, folha amarela',
      icon: Icons.bug_report,
      color: Color(0xFF0D5FA6),
    ),
    PestOption(
      species: 'Percevejo-marrom',
      commonName: 'Percevejo marrom',
      hint: 'Suga a vagem, grão chocho e murcho',
      icon: Icons.coronavirus,
      color: Color(0xFF6A1B9A),
    ),
    PestOption(
      species: 'Bicudo-do-algodoeiro',
      commonName: 'Bicudo do algodoeiro',
      hint: 'Fura o botão floral do algodão',
      icon: Icons.spa,
      color: Color(0xFFB3261E),
    ),
    PestOption(
      species: 'Outros',
      commonName: 'Outra praga',
      hint: 'Não sei o nome / não está na lista',
      icon: Icons.help_outline,
      color: AgroTheme.textGray,
    ),
  ];
}

/// Pest picker as tappable cards.
///
/// The old screen used a dropdown of scientific-sounding strings. A producer
/// recognises the damage and the shape, not the hyphenated name, so each option
/// carries an icon, the common name, and what the damage looks like.
class PestSelector extends StatelessWidget {
  final String selectedSpecies;
  final ValueChanged<String> onChanged;

  const PestSelector({
    super.key,
    required this.selectedSpecies,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: PestOption.all.map((pest) {
        final selected = pest.species == selectedSpecies;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: selected ? pest.color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onChanged(pest.species),
              child: Container(
                constraints: const BoxConstraints(minHeight: 72),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? pest.color : AgroTheme.divider,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: pest.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(pest.icon, color: pest.color, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pest.commonName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AgroTheme.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pest.hint,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AgroTheme.textGray,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, color: pest.color, size: 28),
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

/// Sampling method, as three wide buttons instead of a dropdown.
class MethodSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  static const List<({String value, String label, IconData icon})> methods = [
    (value: 'Pano de batida', label: 'Pano de batida', icon: Icons.view_agenda_outlined),
    (value: 'Visual', label: 'Olhando a planta', icon: Icons.visibility_outlined),
    (value: 'Armadilha', label: 'Armadilha', icon: Icons.crop_free),
  ];

  const MethodSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: methods.map((m) {
        final isSelected = m.value == selected;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: isSelected ? AgroTheme.primary : Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onChanged(m.value),
                child: Container(
                  height: 88,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AgroTheme.primary : AgroTheme.divider,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        m.icon,
                        size: 26,
                        color: isSelected ? Colors.white : AgroTheme.textGray,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        m.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                          color:
                              isSelected ? Colors.white : AgroTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
