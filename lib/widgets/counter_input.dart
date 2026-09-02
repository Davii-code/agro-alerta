import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../shared/theme.dart';

/// Big plus/minus counter for the pest count.
///
/// Replaces a plain TextFormField. Typing into a small text box is the worst
/// possible interaction in the field: gloves, dirty hands, glare, and a soft
/// keyboard covering half the screen. Tapping a 64dp button works with a
/// knuckle. The number stays editable by tapping it, for anyone entering a
/// large count from a sheet.
class CounterInput extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  /// Shown under the number, e.g. "insetos por planta".
  final String unitLabel;

  const CounterInput({
    super.key,
    required this.value,
    required this.onChanged,
    required this.unitLabel,
    this.min = 0,
    this.max = 999,
  });

  void _bump(int delta) {
    final next = (value + delta).clamp(min, max);
    if (next != value) {
      HapticFeedback.selectionClick();
      onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _RoundButton(
              icon: Icons.remove,
              semanticLabel: 'Diminuir contagem',
              enabled: value > min,
              onTap: () => _bump(-1),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => _promptForNumber(context),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    Text(
                      '$value',
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: AgroTheme.textDark,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      unitLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AgroTheme.textGray,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _RoundButton(
              icon: Icons.add,
              semanticLabel: 'Aumentar contagem',
              enabled: value < max,
              onTap: () => _bump(1),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Shortcuts for the common case of counting a batch at once.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepChip(label: '+5', onTap: () => _bump(5)),
            const SizedBox(width: 10),
            _StepChip(label: '+10', onTap: () => _bump(10)),
            const SizedBox(width: 10),
            _StepChip(
              label: 'Zerar',
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(min);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Toque no número para digitar',
          style: TextStyle(fontSize: 13, color: AgroTheme.textGray),
        ),
      ],
    );
  }

  Future<void> _promptForNumber(BuildContext context) async {
    final controller = TextEditingController(text: '$value');

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Digitar a contagem'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          decoration: InputDecoration(hintText: unitLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(120, 48)),
            onPressed: () => Navigator.pop(
              context,
              int.tryParse(controller.text) ?? value,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (result != null) onChanged(result.clamp(min, max));
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.semanticLabel,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: enabled ? AgroTheme.primary : AgroTheme.divider,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            // 64dp, well past the 48dp minimum: this is the control the
            // producer uses most, often without looking.
            width: 64,
            height: 64,
            child: Icon(
              icon,
              size: 34,
              color: enabled ? Colors.white : AgroTheme.textGray,
            ),
          ),
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _StepChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 72,
            minHeight: AgroTheme.minTouchTarget,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AgroTheme.divider),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AgroTheme.primaryDark,
            ),
          ),
        ),
      ),
    );
  }
}
