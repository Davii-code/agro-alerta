import 'package:flutter/material.dart';
import '../services/sync_service.dart';
import '../shared/theme.dart';

/// Honest connection status.
///
/// Replaces the fixed yellow "MODO DE SINCRONIZACAO OFFLINE ATIVO" strip, which
/// was displayed even when the phone was online and syncing fine. It listens to
/// SyncService rather than guessing, and states the count in words a producer
/// can act on ("3 contagens guardadas no celular"), not a status name.
class SyncIndicator extends StatelessWidget {
  /// Called when the producer taps to force a sync.
  final VoidCallback? onTapRetry;

  const SyncIndicator({super.key, this.onTapRetry});

  @override
  Widget build(BuildContext context) {
    final service = SyncService();

    return StreamBuilder<SyncState>(
      stream: service.stream,
      initialData: service.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ??
            const SyncState(status: SyncStatus.upToDate, pending: 0);
        final visual = _visualFor(state);

        // Nothing pending and nothing wrong: a quiet confirmation line, not a
        // warning banner. Occupying the same slot keeps the layout stable.
        return Material(
          color: visual.background,
          child: InkWell(
            onTap: state.status == SyncStatus.syncing ? null : onTapRetry,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: AgroTheme.minTouchTarget),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (state.status == SyncStatus.syncing)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(visual.foreground),
                      ),
                    )
                  else
                    Icon(visual.icon, color: visual.foreground, size: 22),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      visual.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: visual.foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  _SyncVisual _visualFor(SyncState state) {
    final n = state.pending;
    final plural = n == 1 ? 'registro guardado' : 'registros guardados';

    switch (state.status) {
      case SyncStatus.syncing:
        return const _SyncVisual(
          icon: Icons.sync,
          label: 'Enviando seus registros...',
          background: AgroTheme.infoTint,
          foreground: AgroTheme.info,
        );

      case SyncStatus.offlinePending:
        return _SyncVisual(
          icon: Icons.cloud_off_outlined,
          label: n > 0
              ? 'Sem internet - $n $plural no celular'
              : 'Sem internet - nada pendente',
          background: AgroTheme.statusYellowTint,
          foreground: AgroTheme.statusYellow,
        );

      case SyncStatus.error:
        return _SyncVisual(
          icon: Icons.error_outline,
          label: state.message ?? 'Falha ao enviar. Toque para tentar de novo.',
          background: AgroTheme.statusRedTint,
          foreground: AgroTheme.statusRed,
        );

      case SyncStatus.blockedNoAccount:
        return _SyncVisual(
          icon: Icons.person_off_outlined,
          label: state.message ?? 'Entre com sua conta para enviar os registros.',
          background: AgroTheme.statusRedTint,
          foreground: AgroTheme.statusRed,
        );

      case SyncStatus.upToDate:
        return const _SyncVisual(
          icon: Icons.cloud_done_outlined,
          label: 'Tudo enviado',
          background: AgroTheme.statusGreenTint,
          foreground: AgroTheme.statusGreen,
        );
    }
  }
}

class _SyncVisual {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  const _SyncVisual({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });
}
