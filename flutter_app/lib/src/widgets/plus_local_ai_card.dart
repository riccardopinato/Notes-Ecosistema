import 'package:flutter/material.dart';

import '../data/local_ai_pack_service.dart';
import '../data/plus_entitlement_service.dart';
import '../domain/local_ai_pack.dart';
import '../domain/plus.dart';
import 'ui_resilience.dart';

class PlusLocalAiCard extends StatefulWidget {
  const PlusLocalAiCard({super.key});

  @override
  State<PlusLocalAiCard> createState() => _PlusLocalAiCardState();
}

class _PlusLocalAiCardState extends State<PlusLocalAiCard> {
  final _entitlements = const PlusEntitlementService();
  final _pack = const LocalAiPackService();

  PlusEntitlementSnapshot? _entitlement;
  LocalAiPackStatus? _status;
  bool _busy = false;
  String? _error;

  bool get _unlocked =>
      _entitlement?.allows(PlusFeature.localAi20L) == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entitlement = await _entitlements.snapshot();
    LocalAiPackStatus? status;
    if (entitlement.allows(PlusFeature.localAi20L)) {
      status = await _pack.status();
    }
    if (!mounted) return;
    setState(() {
      _entitlement = entitlement;
      _status = status;
    });
  }

  Future<void> _run(
    Future<LocalAiPackStatus> Function() action,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await action();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _error = userErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusText() {
    if (_entitlement == null) return 'Controllo Notes Plus…';
    if (!_unlocked) {
      return 'Needle 3 20L sarà disponibile come pacchetto AI locale '
          'scaricabile con Notes Plus.';
    }

    final status = _status;
    if (status == null) return 'Controllo pacchetto AI…';

    return switch (status.phase) {
      LocalAiPackPhase.installed =>
        'Pacchetto AI installato. Il modello resta sul dispositivo e può '
            'essere rimosso in qualsiasi momento.',
      LocalAiPackPhase.pending => 'Download AI in coda…',
      LocalAiPackPhase.downloading => 'Download AI in corso…',
      LocalAiPackPhase.transferring =>
        'Download completato. Preparazione del modello…',
      LocalAiPackPhase.waitingForWifi => 'Download in attesa del Wi-Fi.',
      LocalAiPackPhase.requiresConfirmation =>
        'Google Play richiede una conferma prima del download.',
      LocalAiPackPhase.failed => 'Il download del pacchetto AI è fallito.',
      LocalAiPackPhase.canceled => 'Download del pacchetto AI annullato.',
      LocalAiPackPhase.notInstalled =>
        'Needle 3 20L non è installato. Il modello attuale richiede circa '
            '${Needle20LPackPolicy.approximateModelMegabytes} MB.',
      LocalAiPackPhase.unavailable =>
        'Il pacchetto Play AI non è disponibile in questa installazione.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final progress = status?.progress;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notes Plus · AI locale',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  avatar: Icon(
                    _unlocked ? Icons.lock_open_outlined : Icons.lock_outline,
                    size: 16,
                  ),
                  label: const Text('Plus'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_statusText()),
            const SizedBox(height: 6),
            Text(
              'Needle 3 20L · on-device · nessun cloud fallback · '
              'modello separato dall’app base.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_entitlement?.source == EntitlementSource.debug) ...[
              const SizedBox(height: 6),
              Text(
                'Entitlement Plus di test attivo nella build debug.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (status?.error != null || _error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error ?? status!.error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            if (progress != null &&
                status != null &&
                status.downloading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 4),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ] else if (_busy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!_unlocked)
                  FilledButton.tonalIcon(
                    onPressed: null,
                    icon: const Icon(Icons.workspace_premium_outlined),
                    label: const Text('Richiede Notes Plus'),
                  )
                else if (status?.installed == true)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(_pack.remove),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Elimina modello'),
                  )
                else if (status?.downloading == true)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(_pack.cancel),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Annulla download'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _busy || status?.supported != true
                        ? null
                        : () => _run(_pack.download),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Scarica AI locale'),
                  ),
                if (_unlocked)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Ricontrolla'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
