import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_locale.dart';
import '../domain/note.dart';
import '../domain/workflow_automation.dart';
import '../state/workflow_automation_controller.dart';
import '../widgets/editorial.dart';
import '../widgets/ui_resilience.dart';

class WorkflowAutomationScreen extends ConsumerWidget {
  const WorkflowAutomationScreen({
    required this.collections,
    super.key,
  });

  final List<NoteCollection> collections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workflowAutomationProvider);
    final strings = AppStrings.of(context);
    final rulesById = {for (final rule in state.rules) rule.id: rule};

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.automations),
        actions: [
          IconButton(
            tooltip: _t(context, 'Aggiorna', 'Refresh', 'Actualizar',
                'Actualiser', 'Aktualisieren', 'Atualizar'),
            onPressed: state.loading
                ? null
                : () => ref.read(workflowAutomationProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editRule(context, ref),
        icon: const Icon(Icons.add),
        label: Text(strings.newRule),
      ),
      body: state.loading && state.rules.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
              children: [
                EditorialEyebrow(
                  _t(
                    context,
                    'WORKFLOW LOCALI',
                    'LOCAL WORKFLOWS',
                    'FLUJOS LOCALES',
                    'WORKFLOWS LOCAUX',
                    'LOKALE WORKFLOWS',
                    'FLUXOS LOCAIS',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.automationsSubtitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    context,
                    'Le regole vengono applicate prima del salvataggio canonico. '
                        'Nessuna AI, rete o azione distruttiva.',
                    'Rules are applied before the canonical save. '
                        'No AI, network, or destructive actions.',
                    'Las reglas se aplican antes del guardado canónico. '
                        'Sin IA, red ni acciones destructivas.',
                    'Les règles sont appliquées avant l’enregistrement canonique. '
                        'Aucune IA, réseau ou action destructive.',
                    'Regeln werden vor dem kanonischen Speichern angewendet. '
                        'Keine KI, kein Netzwerk, keine destruktiven Aktionen.',
                    'As regras são aplicadas antes do salvamento canônico. '
                        'Sem IA, rede ou ações destrutivas.',
                  ),
                ),
                const SizedBox(height: 18),
                if (state.error != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(
                        _t(
                          context,
                          'Automazioni non disponibili',
                          'Automations unavailable',
                          'Automatizaciones no disponibles',
                          'Automatisations indisponibles',
                          'Automationen nicht verfügbar',
                          'Automações indisponíveis',
                        ),
                      ),
                      subtitle: Text(userErrorText(state.error!)),
                    ),
                  ),
                if (state.rules.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(strings.noRules),
                    ),
                  )
                else
                  for (final rule in state.rules)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: ListTile(
                          leading: Switch(
                            value: rule.enabled,
                            onChanged: (value) => _setEnabled(
                              context,
                              ref,
                              rule,
                              value,
                            ),
                          ),
                          title: Text(rule.name),
                          subtitle: Text(
                            _describeRule(context, rule, collections),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                _editRule(context, ref, existing: rule);
                              } else if (value == 'delete') {
                                _deleteRule(context, ref, rule);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(
                                  _t(context, 'Modifica', 'Edit', 'Editar',
                                      'Modifier', 'Bearbeiten', 'Editar'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  _t(context, 'Elimina', 'Delete', 'Eliminar',
                                      'Supprimer', 'Löschen', 'Excluir'),
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _editRule(context, ref, existing: rule),
                        ),
                      ),
                    ),
                const SizedBox(height: 16),
                EditorialSection(strings.recentRuns),
                if (state.runs.isEmpty)
                  Text(
                    _t(
                      context,
                      'Nessuna esecuzione registrata.',
                      'No runs recorded yet.',
                      'Aún no hay ejecuciones registradas.',
                      'Aucune exécution enregistrée.',
                      'Noch keine Ausführungen aufgezeichnet.',
                      'Nenhuma execução registrada.',
                    ),
                  )
                else
                  for (final run in state.runs.take(20))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        child: Icon(Icons.bolt_outlined),
                      ),
                      title: Text(
                        rulesById[run.ruleId]?.name ??
                            _t(
                              context,
                              'Regola rimossa',
                              'Removed rule',
                              'Regla eliminada',
                              'Règle supprimée',
                              'Entfernte Regel',
                              'Regra removida',
                            ),
                      ),
                      subtitle: Text(
                        '${_triggerLabel(context, run.trigger)} · '
                        '${_actionLabel(context, run.actionKind)}',
                      ),
                      trailing: Text(_shortDate(run.ranAt)),
                    ),
              ],
            ),
    );
  }

  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    WorkflowRule rule,
    bool value,
  ) async {
    try {
      await ref
          .read(workflowAutomationProvider.notifier)
          .setEnabled(rule, value);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userErrorText(error))),
      );
    }
  }

  Future<void> _deleteRule(
    BuildContext context,
    WidgetRef ref,
    WorkflowRule rule,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _t(
            context,
            'Eliminare l’automazione?',
            'Delete automation?',
            '¿Eliminar automatización?',
            'Supprimer l’automatisation ?',
            'Automation löschen?',
            'Excluir automação?',
          ),
        ),
        content: Text(rule.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              _t(context, 'Annulla', 'Cancel', 'Cancelar', 'Annuler',
                  'Abbrechen', 'Cancelar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _t(context, 'Elimina', 'Delete', 'Eliminar', 'Supprimer',
                  'Löschen', 'Excluir'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(workflowAutomationProvider.notifier).delete(rule);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userErrorText(error))),
      );
    }
  }

  Future<void> _editRule(
    BuildContext context,
    WidgetRef ref, {
    WorkflowRule? existing,
  }) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final tag = TextEditingController(text: existing?.requiredTag ?? '');
    final title = TextEditingController(text: existing?.titleContains ?? '');
    final actionText = TextEditingController(
      text: existing?.actionKind == WorkflowActionKind.addTag
          ? existing!.actionValue
          : '',
    );

    var enabled = existing?.enabled ?? true;
    var trigger = existing?.trigger ?? WorkflowTrigger.itemCreated;
    var subject = existing?.subject ?? WorkflowSubject.any;
    var action = existing?.actionKind ?? WorkflowActionKind.addTag;
    var collectionId =
        existing?.actionKind == WorkflowActionKind.moveToCollection
            ? existing!.actionValue
            : collections.firstOrNull?.id;
    var priority = existing?.actionKind == WorkflowActionKind.setPriority
        ? int.tryParse(existing!.actionValue) ?? 2
        : 2;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) {
          Widget actionValueField() {
            switch (action) {
              case WorkflowActionKind.addTag:
                return TextField(
                  controller: actionText,
                  decoration: InputDecoration(
                    labelText: _t(
                      dialogContext,
                      'Tag da aggiungere',
                      'Tag to add',
                      'Etiqueta a añadir',
                      'Tag à ajouter',
                      'Hinzuzufügendes Tag',
                      'Tag a adicionar',
                    ),
                  ),
                );
              case WorkflowActionKind.moveToCollection:
                if (collections.isEmpty) {
                  return Text(
                    _t(
                      dialogContext,
                      'Crea prima una raccolta.',
                      'Create a collection first.',
                      'Crea primero una colección.',
                      'Créez d’abord une collection.',
                      'Erstelle zuerst eine Sammlung.',
                      'Crie uma coleção primeiro.',
                    ),
                  );
                }
                if (!collections.any((item) => item.id == collectionId)) {
                  collectionId = collections.first.id;
                }
                return DropdownButtonFormField<String>(
                  value: collectionId,
                  decoration: InputDecoration(
                    labelText: _t(
                      dialogContext,
                      'Raccolta',
                      'Collection',
                      'Colección',
                      'Collection',
                      'Sammlung',
                      'Coleção',
                    ),
                  ),
                  items: [
                    for (final collection in collections)
                      DropdownMenuItem(
                        value: collection.id,
                        child: Text(collection.name),
                      ),
                  ],
                  onChanged: (value) => setLocal(() => collectionId = value),
                );
              case WorkflowActionKind.pin:
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text(
                    _t(
                      dialogContext,
                      'Fissa l’elemento',
                      'Pin item',
                      'Fijar elemento',
                      'Épingler l’élément',
                      'Element anheften',
                      'Fixar item',
                    ),
                  ),
                );
              case WorkflowActionKind.setPriority:
                return DropdownButtonFormField<int>(
                  value: priority,
                  decoration: InputDecoration(
                    labelText: _t(
                      dialogContext,
                      'Priorità',
                      'Priority',
                      'Prioridad',
                      'Priorité',
                      'Priorität',
                      'Prioridade',
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 0,
                      child: Text(_priorityLabel(dialogContext, 0)),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text(_priorityLabel(dialogContext, 1)),
                    ),
                    DropdownMenuItem(
                      value: 2,
                      child: Text(_priorityLabel(dialogContext, 2)),
                    ),
                    DropdownMenuItem(
                      value: 3,
                      child: Text(_priorityLabel(dialogContext, 3)),
                    ),
                  ],
                  onChanged: (value) => setLocal(() => priority = value ?? 0),
                );
            }
          }

          return AlertDialog(
            title: Text(
              existing == null
                  ? AppStrings.of(dialogContext).newRule
                  : _t(
                      dialogContext,
                      'Modifica automazione',
                      'Edit automation',
                      'Editar automatización',
                      'Modifier l’automatisation',
                      'Automation bearbeiten',
                      'Editar automação',
                    ),
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: _t(
                          dialogContext,
                          'Nome',
                          'Name',
                          'Nombre',
                          'Nom',
                          'Name',
                          'Nome',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<WorkflowTrigger>(
                      value: trigger,
                      decoration: InputDecoration(
                        labelText: _t(
                          dialogContext,
                          'Quando',
                          'When',
                          'Cuándo',
                          'Quand',
                          'Wenn',
                          'Quando',
                        ),
                      ),
                      items: [
                        for (final value in WorkflowTrigger.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(_triggerLabel(dialogContext, value)),
                          ),
                      ],
                      onChanged: (value) =>
                          setLocal(() => trigger = value ?? trigger),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<WorkflowSubject>(
                      value: subject,
                      decoration: InputDecoration(
                        labelText: _t(
                          dialogContext,
                          'Su',
                          'On',
                          'Sobre',
                          'Sur',
                          'Auf',
                          'Em',
                        ),
                      ),
                      items: [
                        for (final value in WorkflowSubject.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(_subjectLabel(dialogContext, value)),
                          ),
                      ],
                      onChanged: (value) =>
                          setLocal(() => subject = value ?? subject),
                    ),
                    const Divider(height: 28),
                    TextField(
                      controller: tag,
                      decoration: InputDecoration(
                        labelText: _t(
                          dialogContext,
                          'Solo se ha il tag (opzionale)',
                          'Only if it has tag (optional)',
                          'Solo si tiene etiqueta (opcional)',
                          'Seulement si tag présent (optionnel)',
                          'Nur bei Tag (optional)',
                          'Somente se tiver tag (opcional)',
                        ),
                      ),
                    ),
                    TextField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: _t(
                          dialogContext,
                          'Titolo contiene (opzionale)',
                          'Title contains (optional)',
                          'Título contiene (opcional)',
                          'Titre contient (optionnel)',
                          'Titel enthält (optional)',
                          'Título contém (opcional)',
                        ),
                      ),
                    ),
                    const Divider(height: 28),
                    DropdownButtonFormField<WorkflowActionKind>(
                      value: action,
                      decoration: InputDecoration(
                        labelText: _t(
                          dialogContext,
                          'Allora',
                          'Then',
                          'Entonces',
                          'Alors',
                          'Dann',
                          'Então',
                        ),
                      ),
                      items: [
                        for (final value in WorkflowActionKind.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(_actionLabel(dialogContext, value)),
                          ),
                      ],
                      onChanged: (value) {
                        setLocal(() {
                          action = value ?? action;
                          if (action == WorkflowActionKind.addTag &&
                              actionText.text.trim().isEmpty) {
                            actionText.text = 'workflow';
                          }
                          if (action == WorkflowActionKind.moveToCollection &&
                              collectionId == null &&
                              collections.isNotEmpty) {
                            collectionId = collections.first.id;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    actionValueField(),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _t(
                          dialogContext,
                          'Regola attiva',
                          'Rule enabled',
                          'Regla activa',
                          'Règle active',
                          'Regel aktiv',
                          'Regra ativa',
                        ),
                      ),
                      value: enabled,
                      onChanged: (value) => setLocal(() => enabled = value),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  _t(dialogContext, 'Annulla', 'Cancel', 'Cancelar', 'Annuler',
                      'Abbrechen', 'Cancelar'),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    final actionValue = switch (action) {
                      WorkflowActionKind.addTag => actionText.text.trim(),
                      WorkflowActionKind.moveToCollection => collectionId ?? '',
                      WorkflowActionKind.pin => '',
                      WorkflowActionKind.setPriority => '$priority',
                    };
                    await ref.read(workflowAutomationProvider.notifier).save(
                          existing: existing,
                          name: name.text,
                          enabled: enabled,
                          trigger: trigger,
                          subject: subject,
                          requiredTag: tag.text,
                          titleContains: title.text,
                          actionKind: action,
                          actionValue: actionValue,
                        );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (exception) {
                    setLocal(() => error = userErrorText(exception));
                  }
                },
                child: Text(
                  _t(dialogContext, 'Salva', 'Save', 'Guardar', 'Enregistrer',
                      'Speichern', 'Salvar'),
                ),
              ),
            ],
          );
        },
      ),
    );

    name.dispose();
    tag.dispose();
    title.dispose();
    actionText.dispose();
  }
}

String _describeRule(
  BuildContext context,
  WorkflowRule rule,
  List<NoteCollection> collections,
) {
  final conditions = <String>[];
  if (rule.requiredTag != null) conditions.add('#${rule.requiredTag}');
  if (rule.titleContains != null) {
    conditions.add(
      _t(
        context,
        'titolo: “${rule.titleContains}”',
        'title: “${rule.titleContains}”',
        'título: “${rule.titleContains}”',
        'titre : “${rule.titleContains}”',
        'Titel: “${rule.titleContains}”',
        'título: “${rule.titleContains}”',
      ),
    );
  }
  final target = switch (rule.actionKind) {
    WorkflowActionKind.addTag => '#${rule.actionValue}',
    WorkflowActionKind.moveToCollection => collections
            .where((item) => item.id == rule.actionValue)
            .firstOrNull
            ?.name ??
        _t(
          context,
          'raccolta mancante',
          'missing collection',
          'colección ausente',
          'collection manquante',
          'fehlende Sammlung',
          'coleção ausente',
        ),
    WorkflowActionKind.pin => '',
    WorkflowActionKind.setPriority =>
      _priorityLabel(context, int.tryParse(rule.actionValue) ?? 0),
  };
  return [
    '${_triggerLabel(context, rule.trigger)} · ${_subjectLabel(context, rule.subject)}',
    if (conditions.isNotEmpty) conditions.join(' · '),
    '${_actionLabel(context, rule.actionKind)}${target.isEmpty ? '' : ': $target'}',
  ].join('\n');
}

String _triggerLabel(BuildContext context, WorkflowTrigger trigger) =>
    switch (trigger) {
      WorkflowTrigger.itemCreated => _t(
          context,
          'Elemento creato',
          'Item created',
          'Elemento creado',
          'Élément créé',
          'Element erstellt',
          'Item criado',
        ),
      WorkflowTrigger.itemUpdated => _t(
          context,
          'Elemento aggiornato',
          'Item updated',
          'Elemento actualizado',
          'Élément mis à jour',
          'Element aktualisiert',
          'Item atualizado',
        ),
      WorkflowTrigger.taskCompleted => _t(
          context,
          'Attività completata',
          'Task completed',
          'Tarea completada',
          'Tâche terminée',
          'Aufgabe abgeschlossen',
          'Tarefa concluída',
        ),
    };

String _subjectLabel(BuildContext context, WorkflowSubject subject) =>
    switch (subject) {
      WorkflowSubject.any => _t(
          context,
          'Note e attività',
          'Notes and tasks',
          'Notas y tareas',
          'Notes et tâches',
          'Notizen und Aufgaben',
          'Notas e tarefas'),
      WorkflowSubject.note => _t(context, 'Solo note', 'Notes only',
          'Solo notas', 'Notes seulement', 'Nur Notizen', 'Somente notas'),
      WorkflowSubject.task => _t(context, 'Solo attività', 'Tasks only',
          'Solo tareas', 'Tâches seulement', 'Nur Aufgaben', 'Somente tarefas'),
    };

String _actionLabel(BuildContext context, WorkflowActionKind action) =>
    switch (action) {
      WorkflowActionKind.addTag => _t(context, 'Aggiungi tag', 'Add tag',
          'Añadir etiqueta', 'Ajouter tag', 'Tag hinzufügen', 'Adicionar tag'),
      WorkflowActionKind.moveToCollection => _t(
          context,
          'Sposta in raccolta',
          'Move to collection',
          'Mover a colección',
          'Déplacer vers collection',
          'In Sammlung verschieben',
          'Mover para coleção',
        ),
      WorkflowActionKind.pin =>
        _t(context, 'Fissa', 'Pin', 'Fijar', 'Épingler', 'Anheften', 'Fixar'),
      WorkflowActionKind.setPriority => _t(
          context,
          'Imposta priorità',
          'Set priority',
          'Establecer prioridad',
          'Définir la priorité',
          'Priorität setzen',
          'Definir prioridade',
        ),
    };

String _priorityLabel(BuildContext context, int value) => switch (value) {
      3 => _t(context, 'Alta', 'High', 'Alta', 'Haute', 'Hoch', 'Alta'),
      2 =>
        _t(context, 'Media', 'Medium', 'Media', 'Moyenne', 'Mittel', 'Média'),
      1 => _t(context, 'Bassa', 'Low', 'Baja', 'Basse', 'Niedrig', 'Baixa'),
      _ =>
        _t(context, 'Nessuna', 'None', 'Ninguna', 'Aucune', 'Keine', 'Nenhuma'),
    };

String _shortDate(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
