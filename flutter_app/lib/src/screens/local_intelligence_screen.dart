import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_locale.dart';
import '../domain/local_intelligence.dart';
import '../domain/note.dart';
import '../state/local_intelligence_controller.dart';
import '../widgets/editorial.dart';
import '../widgets/ui_resilience.dart';

class LocalIntelligenceScreen extends ConsumerStatefulWidget {
  const LocalIntelligenceScreen({
    required this.notes,
    super.key,
  });

  final List<Note> notes;

  @override
  ConsumerState<LocalIntelligenceScreen> createState() =>
      _LocalIntelligenceScreenState();
}

class _LocalIntelligenceScreenState
    extends ConsumerState<LocalIntelligenceScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref
          .read(localIntelligenceProvider.notifier)
          .refresh(widget.notes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localIntelligenceProvider);
    final needle = LocalModelAudit.needle;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t(
            context,
            'Intelligence locale',
            'Local Intelligence',
            'Inteligencia local',
            'Intelligence locale',
            'Lokale Intelligence',
            'Inteligência local',
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
        children: [
          EditorialEyebrow(
            _t(
              context,
              'SEMANTIC RETRIEVAL · OPZIONALE',
              'SEMANTIC RETRIEVAL · OPTIONAL',
              'BÚSQUEDA SEMÁNTICA · OPCIONAL',
              'RECHERCHE SÉMANTIQUE · OPTIONNELLE',
              'SEMANTISCHE SUCHE · OPTIONAL',
              'BUSCA SEMÂNTICA · OPCIONAL',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              context,
              'Più contesto, senza rendere l’AI necessaria.',
              'More context without making AI mandatory.',
              'Más contexto sin hacer obligatoria la IA.',
              'Plus de contexte sans rendre l’IA obligatoire.',
              'Mehr Kontext, ohne KI zur Pflicht zu machen.',
              'Mais contexto sem tornar a IA obrigatória.',
            ),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              context,
              'La ricerca deterministica resta sempre disponibile. Il modello '
                  'locale può solo migliorare il ranking e le correlazioni.',
              'Deterministic search always stays available. The local model '
                  'can only improve ranking and related content.',
              'La búsqueda determinista siempre permanece disponible. El '
                  'modelo local solo puede mejorar el ranking y las relaciones.',
              'La recherche déterministe reste toujours disponible. Le modèle '
                  'local ne fait qu’améliorer le classement et les rapprochements.',
              'Die deterministische Suche bleibt immer verfügbar. Das lokale '
                  'Modell verbessert nur Ranking und Ähnlichkeiten.',
              'A busca determinística permanece sempre disponível. O modelo '
                  'local apenas melhora ranking e relações.',
            ),
          ),
          const SizedBox(height: 18),
          _statusCard(context, state, needle),
          const SizedBox(height: 18),
          EditorialSection(
            _t(
              context,
              'Controlli',
              'Controls',
              'Controles',
              'Contrôles',
              'Steuerung',
              'Controles',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.enabled,
            onChanged: (value) =>
                ref.read(localIntelligenceProvider.notifier).setEnabled(value),
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: Text(
              _t(
                context,
                'Usa ranking semantico quando disponibile',
                'Use semantic ranking when available',
                'Usar ranking semántico cuando esté disponible',
                'Utiliser le classement sémantique si disponible',
                'Semantisches Ranking verwenden, wenn verfügbar',
                'Usar ranking semântico quando disponível',
              ),
            ),
            subtitle: Text(
              state.providerAvailable
                  ? _t(
                      context,
                      'Il provider locale è disponibile.',
                      'The local provider is available.',
                      'El proveedor local está disponible.',
                      'Le fournisseur local est disponible.',
                      'Der lokale Provider ist verfügbar.',
                      'O provedor local está disponível.',
                    )
                  : _t(
                      context,
                      'Nessun modello installato: fallback deterministico.',
                      'No model installed: deterministic fallback.',
                      'Sin modelo instalado: fallback determinista.',
                      'Aucun modèle installé : fallback déterministe.',
                      'Kein Modell installiert: deterministischer Fallback.',
                      'Nenhum modelo instalado: fallback determinístico.',
                    ),
            ),
          ),
          if (state.providerAvailable) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storage_outlined),
              title: Text(
                _t(
                  context,
                  'Indice semantico',
                  'Semantic index',
                  'Índice semántico',
                  'Index sémantique',
                  'Semantischer Index',
                  'Índice semântico',
                ),
              ),
              subtitle: Text(
                '${state.indexedDocuments}/${state.totalDocuments}',
              ),
              trailing: state.progress == null
                  ? null
                  : SizedBox(
                      width: 72,
                      child: LinearProgressIndicator(value: state.progress),
                    ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: state.loading
                      ? null
                      : () => ref
                          .read(localIntelligenceProvider.notifier)
                          .rebuild(widget.notes),
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    _t(
                      context,
                      'Aggiorna indice',
                      'Update index',
                      'Actualizar índice',
                      'Mettre à jour l’index',
                      'Index aktualisieren',
                      'Atualizar índice',
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: state.loading
                      ? null
                      : () => ref
                          .read(localIntelligenceProvider.notifier)
                          .runBenchmark(widget.notes),
                  icon: const Icon(Icons.speed_outlined),
                  label: Text(
                    _t(
                      context,
                      'Esegui benchmark',
                      'Run benchmark',
                      'Ejecutar benchmark',
                      'Lancer le benchmark',
                      'Benchmark starten',
                      'Executar benchmark',
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: state.loading
                      ? null
                      : () => ref
                          .read(localIntelligenceProvider.notifier)
                          .clearIndex(widget.notes),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(
                    _t(
                      context,
                      'Ricrea da zero',
                      'Rebuild from scratch',
                      'Reconstruir desde cero',
                      'Reconstruire de zéro',
                      'Neu aufbauen',
                      'Reconstruir do zero',
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (state.benchmark case final benchmark?) ...[
            const SizedBox(height: 18),
            _benchmarkCard(context, benchmark),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(
                  _t(
                    context,
                    'Stato provider',
                    'Provider status',
                    'Estado del proveedor',
                    'État du fournisseur',
                    'Provider-Status',
                    'Status do provedor',
                  ),
                ),
                subtitle: Text(userErrorText(state.error!)),
              ),
            ),
          ],
          const SizedBox(height: 24),
          EditorialSection(
            _t(
              context,
              'Audit modelli',
              'Model audit',
              'Auditoría de modelos',
              'Audit des modèles',
              'Modell-Audit',
              'Auditoria de modelos',
            ),
            detail: _t(
              context,
              'Il default viene promosso solo dopo il benchmark sulle sei lingue.',
              'A default is promoted only after the six-language benchmark.',
              'El predeterminado se promueve solo tras el benchmark en seis idiomas.',
              'Le modèle par défaut n’est promu qu’après le benchmark en six langues.',
              'Ein Standardmodell wird erst nach dem Sechs-Sprachen-Benchmark aktiviert.',
              'O padrão só é promovido após o benchmark em seis idiomas.',
            ),
          ),
          for (final candidate in LocalModelAudit.candidates)
            _candidateCard(context, candidate),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      context,
                      'Privacy e storage',
                      'Privacy and storage',
                      'Privacidad y almacenamiento',
                      'Confidentialité et stockage',
                      'Datenschutz und Speicher',
                      'Privacidade e armazenamento',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      context,
                      '• nessun cloud fallback\n'
                          '• telemetria del runtime obbligatoriamente disattivata\n'
                          '• pesi fuori dall’APK base\n'
                          '• embeddings rigenerabili e non inclusi nei backup\n'
                          '• nessuna relazione esplicita viene creata dalla similarità',
                      '• no cloud fallback\n'
                          '• runtime telemetry must be disabled\n'
                          '• weights stay outside the base APK\n'
                          '• embeddings are regenerable and excluded from backups\n'
                          '• similarity never creates an explicit relation',
                      '• sin fallback en la nube\n'
                          '• telemetría del runtime desactivada\n'
                          '• pesos fuera del APK base\n'
                          '• embeddings regenerables y fuera de backups\n'
                          '• la similitud nunca crea una relación explícita',
                      '• aucun fallback cloud\n'
                          '• télémétrie du runtime désactivée\n'
                          '• poids hors de l’APK de base\n'
                          '• embeddings régénérables, hors sauvegardes\n'
                          '• la similarité ne crée jamais de relation explicite',
                      '• kein Cloud-Fallback\n'
                          '• Runtime-Telemetrie muss deaktiviert sein\n'
                          '• Gewichte außerhalb der Basis-APK\n'
                          '• Embeddings sind regenerierbar und nicht im Backup\n'
                          '• Ähnlichkeit erzeugt keine explizite Beziehung',
                      '• sem fallback na nuvem\n'
                          '• telemetria do runtime desativada\n'
                          '• pesos fora do APK base\n'
                          '• embeddings regeneráveis e fora dos backups\n'
                          '• similaridade nunca cria relação explícita',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(
    BuildContext context,
    LocalIntelligenceState state,
    LocalModelCandidate needle,
  ) {
    final active = state.active;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              child: Icon(
                active ? Icons.auto_awesome : Icons.memory_outlined,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active
                        ? _t(
                            context,
                            'Semantica locale attiva',
                            'Local semantics active',
                            'Semántica local activa',
                            'Sémantique locale active',
                            'Lokale Semantik aktiv',
                            'Semântica local ativa',
                          )
                        : _t(
                            context,
                            'Fallback deterministico attivo',
                            'Deterministic fallback active',
                            'Fallback determinista activo',
                            'Fallback déterministe actif',
                            'Deterministischer Fallback aktiv',
                            'Fallback determinístico ativo',
                          ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.providerAvailable
                        ? '${state.modelId} · ${state.modelVersion}'
                        : '${needle.name} · ${_sizeLabel(needle)} · '
                            '${needle.license}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidateCard(
    BuildContext context,
    LocalModelCandidate candidate,
  ) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      candidate.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Chip(label: Text(_roleLabel(context, candidate.role))),
                ],
              ),
              Text(
                '${_sizeLabel(candidate)} · ${candidate.license} · '
                '${candidate.embeddingDimensions ?? '—'}d',
              ),
              const SizedBox(height: 6),
              Text(candidate.summary),
              if (candidate.mobileAbiNote != null) ...[
                const SizedBox(height: 6),
                Text(
                  candidate.mobileAbiNote!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      );

  Widget _benchmarkCard(
    BuildContext context,
    SemanticBenchmarkResult result,
  ) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.passesNotesGate
                    ? _t(
                        context,
                        'Benchmark superato',
                        'Benchmark passed',
                        'Benchmark superado',
                        'Benchmark réussi',
                        'Benchmark bestanden',
                        'Benchmark aprovado',
                      )
                    : _t(
                        context,
                        'Benchmark non superato',
                        'Benchmark not passed',
                        'Benchmark no superado',
                        'Benchmark non réussi',
                        'Benchmark nicht bestanden',
                        'Benchmark não aprovado',
                      ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Top-1 ${(result.top1Accuracy * 100).toStringAsFixed(1)}% · '
                'MRR ${result.meanReciprocalRank.toStringAsFixed(2)} · '
                '${result.elapsedMilliseconds} ms',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in result.perLanguageTop1.entries)
                    Chip(
                      label: Text(
                        '${entry.key.toUpperCase()} '
                        '${(entry.value * 100).toStringAsFixed(0)}%',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );

  String _sizeLabel(LocalModelCandidate candidate) {
    final min = candidate.minWeightBytes / (1024 * 1024);
    final max = candidate.maxWeightBytes / (1024 * 1024);
    if ((max - min).abs() < 0.5) return '${max.toStringAsFixed(0)} MB';
    return '${min.toStringAsFixed(0)}–${max.toStringAsFixed(0)} MB';
  }

  String _roleLabel(BuildContext context, LocalModelRole role) => switch (role) {
        LocalModelRole.shipCandidate => _t(
            context,
            'Candidato',
            'Candidate',
            'Candidato',
            'Candidat',
            'Kandidat',
            'Candidato',
          ),
        LocalModelRole.control => _t(
            context,
            'Controllo',
            'Control',
            'Control',
            'Contrôle',
            'Kontrolle',
            'Controle',
          ),
        LocalModelRole.qualityReference => _t(
            context,
            'Riferimento',
            'Reference',
            'Referencia',
            'Référence',
            'Referenz',
            'Referência',
          ),
      };
}

String _t(
  BuildContext context,
  String it,
  String en,
  String es,
  String fr,
  String de,
  String pt,
) =>
    switch (AppLocale.effectiveCode(Localizations.localeOf(context))) {
      'it' => it,
      'es' => es,
      'fr' => fr,
      'de' => de,
      'pt' => pt,
      _ => en,
    };
