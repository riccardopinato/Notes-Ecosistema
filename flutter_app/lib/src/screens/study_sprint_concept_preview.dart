import 'package:flutter/material.dart';

/// UI-only research candidate: no note/task writer, SKU or entitlement.
class StudySprintConceptPreview extends StatefulWidget {
  const StudySprintConceptPreview({super.key});

  @override
  State<StudySprintConceptPreview> createState() =>
      _StudySprintConceptPreviewState();
}

class _StudySprintConceptPreviewState extends State<StudySprintConceptPreview> {
  final title = TextEditingController(text: 'Fondamenti di economia');
  final source = TextEditingController(text: 'Appunti del corso');
  final topics =
      TextEditingController(text: 'Domanda e offerta\nMercati\nInflazione');
  int step = 0;
  bool questions = true;
  bool checkpoints = true;
  bool acknowledged = false;
  bool simulated = false;

  String translated(List<String> variants) {
    const locales = ['it', 'en', 'es', 'fr', 'de', 'pt'];
    final i = locales.indexOf(Localizations.localeOf(context).languageCode);
    return variants[i < 0 ? 1 : i];
  }

  @override
  void dispose() {
    title.dispose();
    source.dispose();
    topics.dispose();
    super.dispose();
  }

  String get sample {
    final cleaned = topics.text
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(8);
    return [
      '# ${title.text.trim().isEmpty ? 'Studio senza titolo' : title.text.trim()}',
      '',
      'Fonte dichiarata: ${source.text.trim().isEmpty ? 'Da indicare' : source.text.trim()}',
      '',
      '## Argomenti',
      ...cleaned.map((s) => '- $s'),
      if (questions) ...[
        '',
        '## Domande scritte da me',
        '- Quale concetto voglio chiarire?'
      ],
      if (checkpoints) ...[
        '',
        '## Ripasso',
        '- [ ] Rivedere gli appunti',
        '- [ ] Rispondere alle domande'
      ],
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Study Sprint Studio')),
      body: SafeArea(
        child: ListView(
          key: const ValueKey('study-sprint-native-preview'),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
                translated([
                  'Concept · non acquistabile',
                  'Concept · not for sale',
                  'Concepto · no disponible',
                  'Concept · non disponible',
                  'Konzept · nicht erhältlich',
                  'Conceito · indisponível'
                ]),
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            Text(translated([
              'Da una fonte scelta da te. Nessuna AI o task automatico.',
              'From your chosen source. No AI or automatic tasks.',
              'Desde tu fuente. Sin IA ni tareas automáticas.',
              'Depuis votre source. Sans IA ni tâches automatiques.',
              'Mit deiner Quelle. Ohne KI oder automatische Aufgaben.',
              'Com a sua fonte. Sem IA nem tarefas automáticas.'
            ])),
            const SizedBox(height: 16),
            Text('${step + 1} / 4',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (step == 0)
              const Text('Fonte · Argomenti · Domande personali · Ripasso'),
            if (step == 1) ...[
              TextField(
                  key: const ValueKey('study-sprint-title'),
                  controller: title,
                  maxLength: 100,
                  decoration:
                      const InputDecoration(labelText: 'Titolo / Study title')),
              TextField(
                  controller: source,
                  maxLength: 150,
                  decoration:
                      const InputDecoration(labelText: 'Fonte / Source')),
              TextField(
                  controller: topics,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 500,
                  decoration: const InputDecoration(
                      labelText: 'Argomenti / Topics (max 8)')),
              CheckboxListTile(
                  value: questions,
                  title: const Text('Domande personali / Personal questions'),
                  onChanged: (v) => setState(() => questions = v ?? false)),
              CheckboxListTile(
                  value: checkpoints,
                  title: const Text('Ripasso / Review (no notifications)'),
                  onChanged: (v) => setState(() => checkpoints = v ?? false)),
            ],
            if (step == 2) ...[
              const Text('Anteprima / Preview · nota non salvata'),
              const SizedBox(height: 12),
              SelectableText(sample),
            ],
            if (step == 3) ...[
              const Text('Riepilogo / Review · zero Task e zero notifiche'),
              const SizedBox(height: 12),
              SelectableText(sample),
              CheckboxListTile(
                  value: acknowledged,
                  title: const Text(
                      'Ho letto la simulazione / I reviewed the preview'),
                  onChanged: (v) => setState(() => acknowledged = v ?? false)),
              FilledButton(
                  key: const ValueKey('study-sprint-simulate'),
                  onPressed: !acknowledged
                      ? null
                      : () => setState(() => simulated = true),
                  child: const Text('Simula creazione / Simulate')),
              if (simulated)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    translated([
                      'Simulazione completa: nessun dato salvato.',
                      'Simulation complete: no data saved.',
                      'Simulación completa: no se guardaron datos.',
                      'Simulation terminée : aucune donnée sauvegardée.',
                      'Simulation abgeschlossen: keine Daten gespeichert.',
                      'Simulação concluída: nenhum dado guardado.'
                    ]),
                    key: const ValueKey('study-sprint-done'),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Wrap(
              key: const ValueKey('study-sprint-actions'),
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (step > 0)
                  TextButton(
                    key: const ValueKey('study-sprint-back'),
                    onPressed: () => setState(() {
                      step--;
                      simulated = false;
                    }),
                    child: Text(translated([
                      'Indietro',
                      'Back',
                      'Atrás',
                      'Retour',
                      'Zurück',
                      'Voltar'
                    ])),
                  ),
                if (step < 3)
                  FilledButton(
                    key: const ValueKey('study-sprint-next'),
                    onPressed: () => setState(() => step++),
                    child: Text(translated([
                      'Avanti',
                      'Next',
                      'Siguiente',
                      'Suivant',
                      'Weiter',
                      'Próximo'
                    ])),
                  )
                else
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(translated([
                      'Chiudi',
                      'Close',
                      'Cerrar',
                      'Fermer',
                      'Schließen',
                      'Fechar'
                    ])),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
