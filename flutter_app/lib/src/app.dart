import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'data/import_application_service.dart';
import 'data/knowledge_graph_service.dart';
import 'data/unified_retrieval_service.dart';
import 'domain/app_locale.dart';
import 'domain/attachments.dart';
import 'domain/backup.dart';
import 'domain/diary.dart';
import 'domain/editing.dart';
import 'domain/disaster_recovery.dart';
import 'domain/recovery_safety.dart';
import 'domain/recovery_journal.dart';
import 'domain/import_provenance.dart';
import 'domain/intelligence.dart';
import 'domain/note_to_checklist.dart';
import 'domain/smart_inbox_checklist_action.dart';
import 'domain/smart_inbox_source_preview.dart';
import 'domain/media_bundle.dart';
import 'domain/markdown_interop.dart';
import 'domain/markdown_folder_mirror.dart';
import 'domain/note.dart';
import 'domain/obsidian_migration.dart';
import 'domain/open_export.dart';
import 'domain/planner.dart';
import 'domain/project_workspace.dart';
import 'domain/research.dart';
import 'domain/shared_space_bundle.dart';
import 'domain/shared_spaces.dart';
import 'domain/stable_links.dart';
import 'domain/sync.dart';
import 'domain/quick_capture.dart';
import 'domain/quick_switcher.dart';
import 'domain/templates.dart';
import 'domain/unified_retrieval.dart';
import 'domain/visual_documents.dart';
import 'platform/deep_link_bridge.dart';
import 'platform/quick_capture_bridge.dart';
import 'platform/quick_sync_bridge.dart';
import 'platform/shared_background_bridge.dart';
import 'platform/reminder_action_bridge.dart';
import 'platform/reminder_bridge.dart';
import 'screens/diary_screen.dart';
import 'screens/editor_screen.dart';
import 'screens/github_sync_screen.dart';
import 'screens/home_screen.dart';
import 'screens/knowledge_graph_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/planner_screen.dart';
import 'screens/project_workspace_screen.dart';
import 'screens/shared_spaces_screen.dart';
import 'screens/study_screen.dart';
import 'screens/sketch_screen.dart';
import 'screens/templates_screen.dart';
import 'screens/whiteboard_screen.dart';
import 'screens/workflow_automation_screen.dart';
import 'state/document_controller.dart';
import 'state/project_workspace_controller.dart';
import 'state/shared_live_sync_controller.dart';
import 'state/shared_spaces_controller.dart';
import 'state/study_controller.dart';
import 'state/workflow_automation_controller.dart';
import 'state/workspace_controller.dart';
import 'sync/github_sync_service.dart';
import 'theme/notes_theme.dart';
import 'widgets/editorial.dart';
import 'widgets/quick_switcher_sheet.dart';
import 'widgets/intelligence_sheet.dart';
import 'widgets/ui_resilience.dart';

class NotesEcosistemaApp extends ConsumerStatefulWidget {
  const NotesEcosistemaApp({super.key});

  @override
  ConsumerState<NotesEcosistemaApp> createState() => _NotesEcosistemaAppState();
}

class _NotesEcosistemaAppState extends ConsumerState<NotesEcosistemaApp> {
  bool _dark = false;
  String? _localeCode;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _dark = prefs.getBool('dark_mode') ?? false;
        _localeCode = AppLocale.normalizePreference(
            prefs.getString(AppLocale.preferenceKey));
      });
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Notes Ecosistema',
        debugShowCheckedModeBanner: false,
        theme: NotesTheme.light(),
        darkTheme: NotesTheme.dark(),
        themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
        locale: AppLocale.localeForPreference(_localeCode),
        supportedLocales: AppLocale.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: WorkspaceShell(
          dark: _dark,
          localeCode: _localeCode,
          onDarkChanged: (value) async {
            setState(() => _dark = value);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('dark_mode', value);
          },
          onLocaleChanged: (value) async {
            final normalized = AppLocale.normalizePreference(value);
            setState(() => _localeCode = normalized);
            final prefs = await SharedPreferences.getInstance();
            if (normalized == null) {
              await prefs.remove(AppLocale.preferenceKey);
            } else {
              await prefs.setString(AppLocale.preferenceKey, normalized);
            }
          },
        ),
      );
}

class WorkspaceShell extends ConsumerStatefulWidget {
  const WorkspaceShell({
    required this.dark,
    required this.localeCode,
    required this.onDarkChanged,
    required this.onLocaleChanged,
    super.key,
  });

  final bool dark;
  final String? localeCode;
  final ValueChanged<bool> onDarkChanged;
  final ValueChanged<String?> onLocaleChanged;

  @override
  ConsumerState<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends ConsumerState<WorkspaceShell>
    with WidgetsBindingObserver {
  int _index = 0;
  String _query = '';
  String? _libraryCollectionId;
  String? _plannerTaskId;
  String _reminderSignature = '';
  bool _smartInboxTaskSaving = false;
  final Map<String, ({Note task, String owner})> _smartInboxTaskUndo = {};
  bool _semanticSearchEnabled = true;
  bool _recoveryGateOpen = false;
  bool _recoveryGateBusy = false;
  bool _restoreBusy = false;
  bool _bridgesInitialized = false;
  String? _recoveryGateError;
  RecoveryJournal? _recoveryJournal;
  SharedLiveSyncController? _heldRecoveryPause;

  static const _semanticSearchPreference = 'semantic_search_enabled';

  static const labels = [
    'Home',
    'Note',
    'Diario',
    'Attività',
    'Spazi',
    'Cerca'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _semanticSearchEnabled =
            prefs.getBool(_semanticSearchPreference) ?? true;
      });
    });
    // No platform callbacks, user editors or Live Sync before crash recovery.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openRecoveryGate());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_recoveryGateOpen ||
        _restoreBusy) {
      return;
    }
    unawaited(
      ref.read(sharedLiveSyncProvider.notifier).syncOnForeground(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _acquireRecoveryPause() async {
    if (_heldRecoveryPause != null) return;
    final sync = ref.read(sharedLiveSyncProvider.notifier);
    if (!sync.tryBeginRestorePause()) {
      throw const FormatException(
        'Sincronizzazione in corso: riprova dopo la conclusione.',
      );
    }
    try {
      // A native background worker is independent of Flutter's pause gate.
      if (!kIsWeb && Platform.isAndroid) {
        await SharedBackgroundBridge.setEnabled(false);
      }
      _heldRecoveryPause = sync;
    } catch (_) {
      sync.endRestorePause();
      rethrow;
    }
  }

  Future<void> _releaseRecoveryPause() async {
    final sync = _heldRecoveryPause;
    if (sync == null) return;
    _heldRecoveryPause = null;
    sync.endRestorePause();
    if (!kIsWeb && Platform.isAndroid) {
      // Restore background scheduling only AFTER journal completion.
      try {
        await SharedBackgroundBridge.setEnabled(
          ref.read(sharedLiveSyncProvider).enabled,
        );
      } catch (_) {
        // An unavailable scheduler must not invalidate completed local data.
      }
    }
  }

  void _activatePlatformBridges() {
    if (_bridgesInitialized) return;
    _bridgesInitialized = true;
    QuickCaptureBridge.initialize(_handleIncomingCapture);
    DeepLinkBridge.initialize(_handleDeepLink);
    QuickSyncBridge.initialize(_handleQuickSync);
    SharedBackgroundBridge.initialize(_handleSharedBackgroundSpace);
    ReminderActionBridge.initialize(_handleReminderAction);
  }

  /// Fail closed on startup when a previous multi-store restore is pending.
  Future<void> _openRecoveryGate() async {
    if (_recoveryGateBusy || !mounted) return;
    _recoveryGateBusy = true;
    try {
      if (kIsWeb) {
        // Web has no private native file journal; keep browsing available but
        // refuse destructive multi-store restore in this target.
        setState(() {
          _recoveryGateOpen = true;
          _recoveryGateError = null;
        });
        _activatePlatformBridges();
        return;
      }
      final journal = _recoveryJournal ?? await RecoveryJournal.open();
      _recoveryJournal = journal;
      if (await journal.hasUnsettled) {
        await _acquireRecoveryPause();
        await RecoveryTransaction.recoverPending(
          journal: journal,
          applyOriginal: (bytes) async {
            final original = DisasterRecoveryBundle.decode(bytes);
            await _applyDisasterRecovery(original);
          },
        );
      }
      if (!mounted) return;
      await _releaseRecoveryPause();
      setState(() {
        _recoveryGateOpen = true;
        _recoveryGateError = null;
      });
      _activatePlatformBridges();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recoveryGateOpen = false;
        _recoveryGateError =
            'Recupero dello stato interrotto non completato: $error. '
            'Conserva il backup esterno. Nessuna altra scrittura è consentita.';
      });
    } finally {
      _recoveryGateBusy = false;
    }
  }

  void _selectSection(int value) {
    setState(() {
      if (value == 1) _libraryCollectionId = null;
      if (value != 3) _plannerTaskId = null;
      _index = value;
    });
  }

  Future<void> _handleDeepLink(String raw) async {
    // Native callbacks may arrive while a cross-store restore is suspended.
    if (!_recoveryGateOpen || _restoreBusy) return;
    final target = StableLinks.parse(raw);
    if (target == null || !mounted) return;
    switch (target.kind) {
      case StableLinkKind.object:
        var note = ref
            .read(workspaceProvider)
            .notes
            .where((item) => item.id == target.id)
            .firstOrNull;
        if (note == null) {
          await ref.read(workspaceProvider.notifier).refresh();
          note = ref
              .read(workspaceProvider)
              .notes
              .where((item) => item.id == target.id)
              .firstOrNull;
        }
        if (!mounted) return;
        if (note == null || note.isDeleted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Contenuto collegato non disponibile.')),
          );
          return;
        }
        if (note.isTask) {
          setState(() {
            _plannerTaskId = note!.id;
            _index = 3;
          });
        } else if (note.isVisual) {
          await _openVisual(note);
        } else {
          await _openEditor(note);
        }
        break;
      case StableLinkKind.project:
        await _openProjects(initialProjectId: target.id);
        break;
      case StableLinkKind.study:
        await _openStudy();
        break;
    }
  }

  Future<void> _copyStableLink(String id) async {
    final link = StableLinks.object(id).toString();
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Collegamento Notes copiato.')),
    );
  }

  Future<void> _handleSharedBackgroundSpace(String spaceId) async {
    // Native callbacks may arrive while a cross-store restore is suspended.
    if (!_recoveryGateOpen || _restoreBusy) return;
    if (!mounted) return;
    setState(() => _index = 4);

    await ref.read(sharedLiveSyncProvider.notifier).syncNow(silent: true);
    if (!mounted) return;

    final shared = ref.read(sharedSpacesProvider);
    final identity = shared.identity;
    final space = shared.byId(spaceId);
    if (identity == null || space == null || !space.canRead(identity.id)) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SharedSpaceDetailScreen(
          spaceId: spaceId,
          onOpenNote: _openSharedItem,
          onCreateNote: _createSharedNote,
          onCreateTask: _createSharedTask,
          onExportBundle: _exportSharedSpaceBundle,
          onImportBundle: _importSharedSpaceBundle,
        ),
      ),
    );
  }

  Future<void> _handleReminderAction(ReminderAction action) async {
    // Native callbacks may arrive while a cross-store restore is suspended.
    if (!_recoveryGateOpen || _restoreBusy) return;
    if (!mounted) return;

    if (action.action == 'open') {
      setState(() {
        _plannerTaskId = action.id;
        _index = 3;
      });
      return;
    }

    if (action.action != 'snooze' ||
        action.expectedAt == null ||
        action.nextAt == null) {
      return;
    }

    final changed = await ref.read(workspaceProvider.notifier).snoozeReminder(
          action.id,
          action.expectedAt!,
          action.nextAt!,
        );
    if (!mounted) return;

    if (changed) {
      await ReminderBridge.sync(ref.read(workspaceProvider).notes);
      if (!mounted) return;
      setState(() {
        _plannerTaskId = action.id;
        _index = 3;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Promemoria rinviato di 10 minuti.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Il promemoria è già cambiato: nessuna modifica applicata.',
          ),
        ),
      );
    }
  }

  Future<void> _handleQuickSync() async {
    // Native callbacks may arrive while a cross-store restore is suspended.
    if (!_recoveryGateOpen || _restoreBusy) return;
    if (!mounted) return;
    final service = GitHubSyncService(ref.read(databaseProvider));
    try {
      final connected = await service.loadStatus();
      if (!connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'GitHub non collegato. Apri Impostazioni → GitHub Sync.'),
            ),
          );
        }
        return;
      }

      await service.run();
      await ref.read(workspaceProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(service.status.message)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorText(error),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleIncomingCapture(IncomingCapture capture) async {
    // Native callbacks may arrive while a cross-store restore is suspended.
    if (!_recoveryGateOpen || _restoreBusy) return;
    if (!mounted) return;

    if (capture.error != null && capture.error!.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(capture.error!)),
      );
      return;
    }

    try {
      var body = capture.seed.body;
      if (capture.seed.checklist && body.trim().isEmpty) {
        body = '- [ ] ';
      }

      if (capture.files.isNotEmpty) {
        final store = await AttachmentStore.open();
        for (final shared in capture.files.take(20)) {
          final file = File(shared.path);
          if (!await file.exists()) continue;
          final bytes = await file.readAsBytes();
          final type = Attachments.typeFromName(shared.name) ??
              switch (shared.mime.toLowerCase()) {
                'application/pdf' => AttachmentType.pdf,
                'image/png' => AttachmentType.png,
                'image/webp' => AttachmentType.webp,
                _ => AttachmentType.jpeg,
              };
          final key = await store.ingest(bytes, type);
          body = Attachments.append(body, key, shared.name);
          await file.delete().catchError((_) => file);
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await _openEditor(
        Note(
          id: const Uuid().v4(),
          title: capture.seed.title,
          body: body,
          favorite: false,
          createdAt: now,
          updatedAt: now,
          pinned: false,
          archived: false,
          tags: const [],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(error),
          ),
        ),
      );
    }
  }

  /// First increment of the source-backed Smart Inbox writer flow.
  /// Proposals are edits to the existing editor draft, not background writes.
  Future<void> _openSmartInboxTagDraft(Note source, List<String> tags) async {
    if (tags.isEmpty) return;
    final state = ref.read(workspaceProvider);
    final matches = state.notes.where((note) => note.id == source.id).toList();
    if (matches.length != 1) return;
    final current = matches.single;
    if (current.isDeleted ||
        current.archived ||
        current.isTask ||
        current.isVisual ||
        current.updatedAt != source.updatedAt ||
        current.title != source.title ||
        current.body != source.body ||
        current.collectionId != source.collectionId ||
        current.tags.join('\\u0000') != source.tags.join('\\u0000')) {
      return;
    }
    // Shared-space role/switch safety remains a separate #46 gate.
    // This first writer increment only offers tag drafts for private notes.
    final shared = ref.read(sharedSpacesProvider);
    if (shared.spaces.any((space) => space.contentIds.contains(source.id))) {
      await _openEditor(current);
      return;
    }
    final merged = NoteTags.normalize({...current.tags, ...tags});
    if (merged.length == current.tags.length) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorScreen(
        note: current,
        collections: state.collections,
        allNotes: state.notes,
        suggestedTags: tags,
      ),
    ));
    await ref.read(workspaceProvider.notifier).refresh();
  }

  /// Source-verified private-only canonical Task writer. No implicit
  /// background action: the Home preview requires an explicit confirmation.
  Future<String> _createSmartInboxChecklistTask(
      Note source, List<String> selected) async {
    if (_smartInboxTaskSaving) {
      throw const FormatException('Attività già in fase di creazione.');
    }
    _smartInboxTaskSaving = true;
    try {
      final sharedBefore = ref.read(sharedSpacesProvider);
      final owner = sharedBefore.identity?.id;
      if (sharedBefore.loading ||
          sharedBefore.error != null ||
          owner == null ||
          sharedBefore.spaces
              .any((space) => space.contentIds.contains(source.id))) {
        throw const FormatException(
            'Fonte non privata o permessi non verificati.');
      }
      final selectedItems =
          SmartInboxChecklistAction.selectedItems(source, selected);
      final database = ref.read(databaseProvider);
      final live = await database.loadNote(source.id);
      final workspace = ref.read(workspaceProvider);
      final matching = workspace.notes
          .where((note) => note.id == source.id)
          .toList(growable: false);
      final sharedNow = ref.read(sharedSpacesProvider);
      if (workspace.loading ||
          matching.length != 1 ||
          live == null ||
          sharedNow.loading ||
          sharedNow.error != null ||
          sharedNow.identity?.id != owner ||
          sharedNow.spaces
              .any((space) => space.contentIds.contains(source.id)) ||
          !SmartInboxSourcePreview.sameCanonicalRevision(source, live) ||
          !SmartInboxSourcePreview.sameCanonicalRevision(
              source, matching.single)) {
        throw const FormatException('Fonte modificata o non più accessibile.');
      }
      if (SmartInboxChecklistAction.alreadyCreated(
          workspace.notes, source.id, selectedItems)) {
        throw const FormatException('Checklist già trasformata in attività.');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final task = NoteToChecklist.buildTask(
        source: live,
        selected: selectedItems,
        taskId: const Uuid().v4(),
        nowMilliseconds: now,
      );
      // No second task store: canonical writer and existing linkedNoteId.
      await ref.read(workspaceProvider.notifier).save(task);
      final saved = await database.loadNote(task.id);
      if (saved != null && saved.isTask && !saved.isDeleted) {
        _smartInboxTaskUndo[task.id] = (task: saved, owner: owner);
        if (_smartInboxTaskUndo.length > 12) {
          _smartInboxTaskUndo.remove(_smartInboxTaskUndo.keys.first);
        }
      }
      return task.id;
    } finally {
      _smartInboxTaskSaving = false;
    }
  }

  /// Explicit, bounded Undo: soft-trash the unmodified derived task only.
  Future<void> _undoSmartInboxChecklistTask(String id) async {
    final receipt = _smartInboxTaskUndo.remove(id);
    if (receipt == null) {
      throw const FormatException('Annullamento non più disponibile.');
    }
    final dbTask = await ref.read(databaseProvider).loadNote(id);
    final shared = ref.read(sharedSpacesProvider);
    if (dbTask == null ||
        shared.error != null ||
        shared.loading ||
        shared.identity?.id != receipt.owner ||
        shared.spaces.any((space) => space.contentIds.contains(id)) ||
        !SmartInboxChecklistAction.canUndo(receipt.task, dbTask)) {
      throw const FormatException(
          'Attività modificata: annullamento non sicuro.');
    }
    await ref.read(workspaceProvider.notifier).trash(id);
  }

  Future<void> _openEditor([
    Note? note,
    bool readOnly = false,
    bool autoRecord = false,
  ]) async {
    if (note?.isVisual == true) {
      await _openVisual(note!, readOnly: readOnly);
      return;
    }

    final collections = ref.read(workspaceProvider).collections;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          note: note,
          collections: collections,
          allNotes: ref.read(workspaceProvider).notes,
          readOnly: readOnly,
          autoRecord: autoRecord,
        ),
      ),
    );
    await ref.read(workspaceProvider.notifier).refresh();
  }

  Future<void> _openVisual(Note note, {bool readOnly = false}) async {
    if (note.visualKind == VisualDocumentKind.whiteboard) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WhiteboardScreen(
            note: note,
            onSave: (updated) =>
                ref.read(workspaceProvider.notifier).save(updated),
            readOnly: readOnly,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SketchScreen(
            note: note,
            onSave: (updated) =>
                ref.read(workspaceProvider.notifier).save(updated),
            readOnly: readOnly,
          ),
        ),
      );
    }
    await ref.read(workspaceProvider.notifier).refresh();
  }

  Future<void> _openTemplates() async {
    final workspace = ref.read(workspaceProvider);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplatesScreen(
          notes: workspace.notes,
          onUse: (content) {
            Navigator.pop(context);
            _openTemplateDraft(content);
          },
          onEdit: (note) {
            Navigator.pop(context);
            _openEditor(note);
          },
        ),
      ),
    );
    await ref.read(workspaceProvider.notifier).refresh();
  }

  Future<void> _openTemplateDraft(TemplateContent content) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _openEditor(
      Note(
        id: const Uuid().v4(),
        title: content.title,
        body: content.body,
        favorite: false,
        createdAt: now,
        updatedAt: now,
        pinned: false,
        archived: false,
        tags: content.tags,
      ),
    );
  }

  Future<void> _createVisual({
    required VisualInfoKind kind,
    WhiteboardMode whiteboardMode = WhiteboardMode.freeform,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = const Uuid().v4();
    final note = kind == VisualInfoKind.sketch
        ? Note(
            id: id,
            title: 'Nuovo disegno',
            body: SketchCodec.encode(SketchDocument()),
            favorite: false,
            createdAt: now,
            updatedAt: now,
            pinned: false,
            archived: false,
            tags: const [],
            sketchJson: const VisualInfo(
              kind: VisualInfoKind.sketch,
            ).encode(),
          )
        : Note(
            id: id,
            title: whiteboardMode == WhiteboardMode.mindMap
                ? 'Nuova mind map'
                : 'Nuova lavagna',
            body: WhiteboardCodec.encode(
              WhiteboardOps.empty(whiteboardMode),
            ),
            favorite: false,
            createdAt: now,
            updatedAt: now,
            pinned: false,
            archived: false,
            tags: const [],
            sketchJson: const VisualInfo(
              kind: VisualInfoKind.whiteboard,
            ).encode(),
          );

    await ref.read(workspaceProvider.notifier).save(note);
    await _openVisual(note);
  }

  Future<void> _createDiaryEntry(
    DateTime date,
    String? collectionId,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final draft = Note(
      id: const Uuid().v4(),
      title: '',
      body: '',
      collectionId: collectionId,
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: Diary.datedTags(const [], date),
    );
    await _openEditor(draft);
  }

  Future<void> _openSharedItem(Note note, bool readOnly) async {
    if (note.isTask) {
      if (readOnly) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SharedTaskReadOnlyScreen(note: note),
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlannerScreen(
            notes: ref.read(workspaceProvider).notes,
            initialTaskId: note.id,
            onSave: (updated) =>
                ref.read(workspaceProvider.notifier).save(updated),
            onTrash: (id) => ref.read(workspaceProvider.notifier).trash(id),
            onOpenNote: _openEditor,
          ),
        ),
      );
      await ref.read(workspaceProvider.notifier).refresh();
      await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
      return;
    }
    await _openEditor(note, readOnly);
    if (!readOnly) {
      await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
    }
  }

  Future<void> _createSharedNote(String spaceId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = const Uuid().v4();
    final draft = Note(
      id: id,
      title: '',
      body: '',
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: const [],
    );
    await _openEditor(draft);
    final saved = await ref.read(databaseProvider).loadNote(id);
    if (saved == null) return;
    await ref.read(sharedSpacesProvider.notifier).linkContent(spaceId, id);
    await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
  }

  Future<void> _createSharedTask(String spaceId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final note = Note(
      id: const Uuid().v4(),
      title: 'Nuova attività',
      body: '',
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: const [],
      taskJson: TaskDetails.empty().encode(),
    );
    await ref.read(workspaceProvider.notifier).save(note);
    await ref.read(sharedSpacesProvider.notifier).linkContent(spaceId, note.id);
    final current = await ref.read(databaseProvider).loadNote(note.id);
    if (current != null && mounted) {
      await _openSharedItem(current, false);
    } else {
      await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
    }
  }

  Future<void> _openStudy() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudyScreen(
          notes: ref.read(workspaceProvider).notes,
          onOpenSource: (note) {
            Navigator.of(context).pop();
            _openEditor(note);
          },
        ),
      ),
    );
  }

  bool _sharedReadOnly(String noteId) {
    final shared = ref.read(sharedSpacesProvider);
    final identity = shared.identity;
    if (identity == null) return false;
    var viewer = false;
    var editor = false;
    for (final space in shared.spaces) {
      if (!space.contentIds.contains(noteId)) continue;
      final role = space.roleFor(identity.id);
      if (role == null) continue;
      if (role.canEdit) {
        editor = true;
      } else {
        viewer = true;
      }
    }
    return viewer && !editor;
  }

  Future<void> _openKnowledgeGraph() async {
    final notes = ref.read(workspaceProvider).notes;
    final service = KnowledgeGraphService(
      knowledgeStore: ref.read(knowledgeStoreProvider),
      projectStore: ref.read(projectStoreProvider),
      studyStore: ref.read(studyStoreProvider),
      documentStore: ref.read(documentStoreProvider),
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => KnowledgeGraphScreen(
          notes: notes,
          loadGraph: () => service.load(
            ref.read(workspaceProvider).notes,
          ),
          onOpenNote: (note) {
            Navigator.of(context).pop();
            unawaited(_openSharedItem(note, _sharedReadOnly(note.id)));
          },
          onOpenProject: (id) {
            Navigator.of(context).pop();
            unawaited(_openProjects(initialProjectId: id));
          },
          onOpenStudy: () {
            Navigator.of(context).pop();
            unawaited(_openStudy());
          },
          semanticRanker: (query) => _rankNoteIds(
            query,
            ref.read(workspaceProvider).notes,
            limit: 40,
          ),
        ),
      ),
    );
  }

  Future<void> _openWorkflowAutomations() async {
    await ref.read(workflowAutomationProvider.notifier).refresh();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkflowAutomationScreen(
          collections: ref.read(workspaceProvider).collections,
        ),
      ),
    );
    await ref.read(workflowAutomationProvider.notifier).refresh();
  }

  Future<void> _openProjects({String? initialProjectId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectWorkspaceScreen(
          initialProjectId: initialProjectId,
          onOpenItem: _openSharedItem,
          onCreateNote: _createProjectNote,
          onCreateTask: _createProjectTask,
          onSaveTask: _saveProjectTask,
        ),
      ),
    );
    await ref.read(workspaceProvider.notifier).refresh();
    await ref.read(projectWorkspaceProvider.notifier).refresh();
  }

  Future<void> _createProjectNote(ProjectWorkspace project) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = const Uuid().v4();
    final draft = Note(
      id: id,
      title: '',
      body: '',
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: const [],
    );
    await _openEditor(draft);
    final saved = await ref.read(databaseProvider).loadNote(id);
    if (saved == null) return;
    await _attachProjectItem(project, id);
  }

  Future<void> _createProjectTask(ProjectWorkspace project) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final note = Note(
      id: const Uuid().v4(),
      title: 'Nuova attività',
      body: '',
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: const [],
      taskJson: TaskDetails.empty().encode(),
    );
    await ref.read(workspaceProvider.notifier).save(note);
    await _attachProjectItem(project, note.id);
    final current = await ref.read(databaseProvider).loadNote(note.id);
    if (current != null && mounted) {
      await _openSharedItem(current, false);
    }
  }

  Future<void> _attachProjectItem(
    ProjectWorkspace project,
    String noteId,
  ) async {
    final spaceId = project.sharedSpaceId;
    if (spaceId == null) {
      await ref
          .read(projectWorkspaceProvider.notifier)
          .attach(project.id, noteId);
      return;
    }

    final shared = ref.read(sharedSpacesProvider);
    final identity = shared.identity;
    final space = shared.byId(spaceId);
    if (identity == null || space == null || !space.canEdit(identity.id)) {
      throw const FormatException(
        'Non hai i permessi per aggiungere contenuti a questo progetto team.',
      );
    }
    await ref.read(sharedSpacesProvider.notifier).linkContent(spaceId, noteId);
    await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
  }

  Future<void> _saveProjectTask(
    ProjectWorkspace project,
    Note task,
  ) async {
    await ref.read(workspaceProvider.notifier).save(task);
    if (project.sharedSpaceId != null) {
      await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
    }
  }

  Future<void> _exportSharedSpaceBundle(SharedSpace space) async {
    try {
      final shared = ref.read(sharedSpacesProvider);
      final identity = shared.identity;
      if (identity == null || !space.canRead(identity.id)) {
        throw const FormatException(
          'Accesso allo spazio non disponibile.',
        );
      }

      final all = await ref.read(databaseProvider).syncDocuments();
      final documents = <String, SyncDocument>{};
      for (final id in space.contentIds) {
        final document = all[id];
        if (document == null) {
          throw const FormatException(
            'Uno degli elementi condivisi non è disponibile sul dispositivo.',
          );
        }
        documents[id] = document;
      }

      final store = await AttachmentStore.open();
      final bytes = await SharedSpaceBundle.encode(
        space: space,
        actor: identity,
        documents: documents,
        store: store,
      );

      var cleanName = space.name
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .toLowerCase();
      while (cleanName.startsWith('-')) {
        cleanName = cleanName.substring(1);
      }
      while (cleanName.endsWith('-')) {
        cleanName = cleanName.substring(0, cleanName.length - 1);
      }

      final now = DateTime.now();
      final stamp = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final baseName = cleanName.isEmpty ? 'notes' : cleanName;

      await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta Shared Space',
        fileName: 'shared-space-$baseName-$stamp.zip',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aggiornamento Shared Space esportato.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(error),
          ),
        ),
      );
    }
  }

  Future<void> _importSharedSpaceBundle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException(
          'Impossibile leggere il pacchetto Shared Space.',
        );
      }

      final preview = SharedSpaceBundle.decode(Uint8List.fromList(bytes));
      final shared = ref.read(sharedSpacesProvider);
      final identity = shared.identity;
      if (identity == null) {
        throw const FormatException(
          'Profilo collaborazione non disponibile.',
        );
      }
      final localSpace = shared.byId(preview.space.id);
      if (localSpace == null && !preview.space.canRead(identity.id)) {
        throw const FormatException(
          'Importa prima il codice invito di questo Shared Space.',
        );
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Importare “${preview.space.name}”?'),
          content: Text(
            'Pacchetto di ${preview.actor.displayName}: '
            '${preview.documents.length} elementi e '
            '${preview.assets.length} allegati. '
            'Le versioni locali più recenti non verranno sovrascritte.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importa aggiornamento'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final store = await AttachmentStore.open();
      await SharedSpaceBundle.installAssets(preview, store);

      final database = ref.read(databaseProvider);
      final localDocuments = await database.syncDocuments();
      var downloaded = 0;
      var keptLocal = 0;
      var conflicts = 0;

      for (final remote in preview.documents.values) {
        final local = localDocuments[remote.id];
        if (local == null) {
          await database.applySyncDocument(remote);
          downloaded++;
          continue;
        }
        if (local == remote) continue;
        if (remote.updatedAt > local.updatedAt) {
          await database.applySyncDocument(remote);
          downloaded++;
        } else if (remote.updatedAt < local.updatedAt) {
          keptLocal++;
        } else {
          await database.saveSyncCopy(
            remote,
            suffix: ' (conflitto Shared Space)',
          );
          conflicts++;
        }
      }

      await ref
          .read(sharedSpacesProvider.notifier)
          .mergeRemoteSpace(preview.space);
      await ref.read(workspaceProvider.notifier).refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Shared Space aggiornato · ricevuti $downloaded · '
            'locali mantenuti $keptLocal · conflitti $conflicts.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(error),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_recoveryGateOpen) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shield_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _recoveryGateError ??
                        'Verifica del recupero locale in corso…',
                    textAlign: TextAlign.center,
                  ),
                  if (_recoveryGateError != null) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _recoveryGateBusy ? null : _openRecoveryGate,
                      child: const Text('Riprova recupero'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    final live = ref.watch(sharedLiveSyncProvider);
    final workspace = ref.watch(workspaceProvider);
    final shared = ref.watch(sharedSpacesProvider);
    final projects = ref.watch(projectWorkspaceProvider);
    final section = labels[_index];

    final editableSharedIds = <String>{};
    final viewerSharedIds = <String>{};
    final identity = shared.identity;
    if (identity != null) {
      for (final space in shared.spaces) {
        final role = space.roleFor(identity.id);
        if (role == null) continue;
        if (role.canEdit) {
          editableSharedIds.addAll(space.contentIds);
        } else {
          viewerSharedIds.addAll(space.contentIds);
        }
      }
    }
    final viewerOnlyIds = viewerSharedIds.difference(editableSharedIds);
    final personalNotes = workspace.notes
        .where((note) => !viewerOnlyIds.contains(note.id))
        .toList(growable: false);

    if (!workspace.loading) {
      final reminderSignature = personalNotes
          .where((note) => note.isTask)
          .map(
            (note) =>
                '${note.id}|${note.title}|${note.taskJson}|${note.deletedAt}|${note.archived}',
          )
          .join('\n');
      if (reminderSignature != _reminderSignature) {
        _reminderSignature = reminderSignature;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ReminderBridge.sync(personalNotes).catchError((_) {});
          }
        });
      }
    }

    Widget body;
    if (workspace.loading && workspace.notes.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (workspace.error != null && workspace.notes.isEmpty) {
      body = _ErrorState(
        onRetry: () => ref.read(workspaceProvider.notifier).refresh(),
      );
    } else if (_index == 0) {
      body = HomeScreen(
        notes: personalNotes,
        collections: workspace.collections,
        onCreate: _openEditor,
        onNotes: () => setState(() {
          _libraryCollectionId = null;
          _index = 1;
        }),
        onAgenda: () => setState(() => _index = 3),
        onTasks: () => setState(() => _index = 3),
        onSketch: () => _createVisual(kind: VisualInfoKind.sketch),
        onCollection: (id) => setState(() {
          _libraryCollectionId = id;
          _index = 1;
        }),
        onOpenNote: _openEditor,
        onDraftSmartInboxTags: _openSmartInboxTagDraft,
        onCreateSmartInboxChecklistTask: _createSmartInboxChecklistTask,
        onUndoSmartInboxChecklistTask: _undoSmartInboxChecklistTask,
        onProjects: () => _openProjects(),
        onStudy: _openStudy,
        onGraph: _openKnowledgeGraph,
        onAutomations: _openWorkflowAutomations,
        projectCount:
            projects.projects.where((project) => project.isActive).length,
        sharedUnread: identity == null ? 0 : live.totalUnread(identity.id),
      );
    } else if (_index == 1 || _index == 5) {
      body = NotesScreen(
        notes: personalNotes,
        collections: workspace.collections,
        query: _query,
        searchMode: _index == 5,
        onQueryChanged: (value) => setState(() => _query = value),
        onOpen: _openEditor,
        onFavorite: (id) => ref.read(workspaceProvider.notifier).favorite(id),
        onPin: (id, value) =>
            ref.read(workspaceProvider.notifier).pin(id, value),
        onArchive: (id, value) =>
            ref.read(workspaceProvider.notifier).archive(id, value),
        onTrash: (id) => ref.read(workspaceProvider.notifier).trash(id),
        onRestore: _restoreFromTrash,
        onDeleteForever: _deleteForever,
        onCopyLink: _copyStableLink,
        onBulkEdit: (notes, change) =>
            ref.read(workspaceProvider.notifier).bulkEdit(notes, change),
        onRenameCollection: (collection, name) =>
            ref.read(workspaceProvider.notifier).renameCollection(
                  collection,
                  name,
                ),
        onDeleteCollection: (collection) =>
            ref.read(workspaceProvider.notifier).deleteEmptyCollection(
                  collection,
                ),
        semanticRanker:
            _index == 5 ? (query) => _rankNoteIds(query, personalNotes) : null,
        initialCollectionId: _index == 1 ? _libraryCollectionId : null,
      );
    } else if (_index == 2) {
      body = DiaryScreen(
        notes: personalNotes,
        collections: workspace.collections,
        onOpen: _openEditor,
        onCreate: _createDiaryEntry,
        onOpenTask: (_) => setState(() => _index = 3),
        onCreateCollection: (name) =>
            ref.read(workspaceProvider.notifier).createCollection(name),
      );
    } else if (_index == 3) {
      body = PlannerScreen(
        notes: personalNotes,
        initialTaskId: _plannerTaskId,
        onSave: (note) => ref.read(workspaceProvider.notifier).save(note),
        onTrash: (id) => ref.read(workspaceProvider.notifier).trash(id),
        onOpenNote: _openEditor,
      );
    } else {
      body = SharedSpacesScreen(
        onOpenNote: _openSharedItem,
        onCreateNote: _createSharedNote,
        onCreateTask: _createSharedTask,
        onExportBundle: _exportSharedSpaceBundle,
        onImportBundle: _importSharedSpaceBundle,
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            unawaited(_quickSwitcher(personalNotes)),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            unawaited(_openEditor()),
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): () => _selectSection(5),
        const SingleActivator(
          LogicalKeyboardKey.keyG,
          control: true,
          shift: true,
        ): () => unawaited(_openKnowledgeGraph()),
        const SingleActivator(
          LogicalKeyboardKey.keyA,
          control: true,
          shift: true,
        ): () => unawaited(_openWorkflowAutomations()),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            const destinations = [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(
                icon: Icon(Icons.description),
                label: 'Note',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month),
                label: 'Diario',
              ),
              NavigationDestination(
                icon: Icon(Icons.check_circle),
                label: 'Attività',
              ),
              NavigationDestination(
                icon: Icon(Icons.group_work_outlined),
                label: 'Spazi',
              ),
              NavigationDestination(icon: Icon(Icons.search), label: 'Cerca'),
            ];
            const railDestinations = [
              NavigationRailDestination(
                icon: Icon(Icons.home),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.description),
                label: Text('Note'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.calendar_month),
                label: Text('Diario'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.check_circle),
                label: Text('Attività'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.group_work_outlined),
                label: Text('Spazi'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.search),
                label: Text('Cerca'),
              ),
            ];

            return Scaffold(
              appBar: AppBar(
                title: EditorialAppTitle(
                    section == 'Home' ? 'Il tuo spazio' : section),
                actions: [
                  IconButton(
                    tooltip: 'Knowledge Search',
                    onPressed: () => _knowledgeSearch(personalNotes),
                    icon: const Icon(Icons.auto_awesome_outlined),
                  ),
                  IconButton(
                    tooltip: 'Quick Switcher · Ctrl+K',
                    onPressed: () => _quickSwitcher(personalNotes),
                    icon: const Icon(Icons.bolt_outlined),
                  ),
                  IconButton(
                    tooltip: 'Impostazioni',
                    onPressed: () => _settings(context),
                    icon: const Icon(Icons.settings),
                  ),
                ],
              ),
              body: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          selectedIndex: _index,
                          onDestinationSelected: _selectSection,
                          labelType: NavigationRailLabelType.selected,
                          destinations: railDestinations,
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: body),
                      ],
                    )
                  : body,
              floatingActionButton:
                  (_index == 5 || _index == 4 || _index == 2 || _index == 3)
                      ? null
                      : FloatingActionButton.extended(
                          onPressed: () => _createMenu(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Crea'),
                        ),
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      selectedIndex: _index,
                      onDestinationSelected: _selectSection,
                      destinations: destinations,
                    ),
            );
          },
        ),
      ),
    );
  }

  UnifiedRetrievalService _retrievalService() => UnifiedRetrievalService(
        derivativeStore: ref.read(derivativeStoreProvider),
        documentStore: ref.read(documentStoreProvider),
        knowledgeStore: ref.read(knowledgeStoreProvider),
        propertyStore: ref.read(propertyStoreProvider),
        studyStore: ref.read(studyStoreProvider),
        semanticStore: ref.read(semanticIndexStoreProvider),
      );

  Future<List<String>> _rankNoteIds(
    String query,
    List<Note> notes, {
    int limit = 80,
  }) =>
      _retrievalService().rankNoteIds(
        query: query,
        notes: notes,
        limit: limit,
        semanticEnabled: _semanticSearchEnabled,
      );

  Future<void> _knowledgeSearch(List<Note> notes) async {
    final service = _retrievalService();
    await showIntelligenceSheet(
      context: context,
      notes: notes,
      derivativeStore: ref.read(derivativeStoreProvider),
      semanticEnabled: _semanticSearchEnabled,
      onOpenNote: (note) => _openEditor(note),
      unifiedSearch: (query) async {
        final hits = await service.search(
          query: query,
          notes: notes,
          semanticEnabled: _semanticSearchEnabled,
        );
        final byId = {for (final note in notes) note.id: note};
        final knowledgeHits = <KnowledgeHit>[];
        for (final hit in hits) {
          final note = byId[hit.document.noteId];
          if (note == null) continue;
          knowledgeHits.add(
            KnowledgeHit(
              note: note,
              score: hit.score,
              excerpt: '${_retrievalLabel(hit.document.kind)} · ${hit.excerpt}',
            ),
          );
        }
        return KnowledgeQueryResult(
          query: query,
          hits: knowledgeHits,
        );
      },
      unifiedRelated: (source) async {
        final hits = await service.related(
          source: source,
          notes: notes,
          semanticEnabled: _semanticSearchEnabled,
        );
        final byId = {for (final note in notes) note.id: note};
        final related = <KnowledgeHit>[];
        for (final hit in hits) {
          final note = byId[hit.document.noteId];
          if (note == null) continue;
          related.add(
            KnowledgeHit(
              note: note,
              score: hit.score,
              excerpt: hit.excerpt,
            ),
          );
        }
        return related;
      },
    );
  }

  String _retrievalLabel(RetrievalKind kind) => switch (kind) {
        RetrievalKind.note => 'Nota',
        RetrievalKind.task => 'Attività',
        RetrievalKind.ocr => 'OCR',
        RetrievalKind.derivative => 'Derivato',
        RetrievalKind.study => 'Studio',
        RetrievalKind.pdfAnnotation => 'Annotazione PDF',
        RetrievalKind.research => 'Fonte',
        RetrievalKind.metadata => 'Proprietà',
        RetrievalKind.relation => 'Relazione',
      };

  Future<void> _quickSwitcher(List<Note> notes) async {
    final workspace = ref.read(workspaceProvider);
    final selected = await showQuickSwitcher(
      context: context,
      notes: notes,
      collections: workspace.collections,
      projects: ref.read(projectWorkspaceProvider).projects,
      semanticRanker: (query) => _rankNoteIds(
        query,
        notes,
        limit: 60,
      ),
    );
    if (selected == null || !mounted) return;

    switch (selected.kind) {
      case QuickSwitcherKind.note:
        final note = notes.where((item) => item.id == selected.id).firstOrNull;
        if (note != null) await _openEditor(note);
        break;
      case QuickSwitcherKind.task:
        setState(() {
          _plannerTaskId = selected.id;
          _index = 3;
        });
        break;
      case QuickSwitcherKind.collection:
        setState(() {
          _libraryCollectionId = selected.id;
          _index = 1;
        });
        break;
      case QuickSwitcherKind.project:
        await _openProjects(initialProjectId: selected.id);
        break;
      case QuickSwitcherKind.command:
        switch (selected.id) {
          case 'today':
            setState(() => _index = 0);
            break;
          case 'new-note':
            await _openEditor();
            break;
          case 'tasks':
            setState(() => _index = 3);
            break;
          case 'projects':
            await _openProjects();
            break;
          case 'knowledge-graph':
            await _openKnowledgeGraph();
            break;
          case 'automations':
            await _openWorkflowAutomations();
            break;
          case 'search':
            setState(() => _index = 5);
            break;
        }
        break;
    }
  }

  Future<void> _createMenu(BuildContext context) async {
    final action = await showNotesBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add),
              title: const Text('Nuova nota'),
              onTap: () => Navigator.pop(context, 'note'),
            ),
            ListTile(
              leading: const Icon(Icons.mic_none),
              title: const Text('Nota vocale'),
              subtitle: const Text('Conserva l’audio originale nella nota'),
              onTap: () => Navigator.pop(context, 'voice'),
            ),
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Diario di oggi'),
              onTap: () => Navigator.pop(context, 'diary'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Nuova attività'),
              onTap: () => Navigator.pop(context, 'task'),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize),
              title: const Text('Modelli'),
              onTap: () => Navigator.pop(context, 'templates'),
            ),
            ListTile(
              leading: const Icon(Icons.draw),
              title: const Text('Nuovo disegno'),
              onTap: () => Navigator.pop(context, 'sketch'),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Nuova lavagna'),
              onTap: () => Navigator.pop(context, 'board'),
            ),
            ListTile(
              leading: const Icon(Icons.account_tree),
              title: const Text('Nuova mind map'),
              onTap: () => Navigator.pop(context, 'mind'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'note') {
      await _openEditor();
    } else if (action == 'voice') {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _openEditor(
        Note(
          id: const Uuid().v4(),
          title: 'Nota vocale',
          body: '',
          favorite: false,
          createdAt: now,
          updatedAt: now,
          pinned: false,
          archived: false,
          tags: const ['voice-source'],
        ),
        false,
        true,
      );
    } else if (action == 'diary') {
      await _createDiaryEntry(DateTime.now(), null);
    } else if (action == 'task') {
      setState(() => _index = 3);
    } else if (action == 'templates') {
      await _openTemplates();
    } else if (action == 'sketch') {
      await _createVisual(kind: VisualInfoKind.sketch);
    } else if (action == 'board') {
      await _createVisual(kind: VisualInfoKind.whiteboard);
    } else if (action == 'mind') {
      await _createVisual(
        kind: VisualInfoKind.whiteboard,
        whiteboardMode: WhiteboardMode.mindMap,
      );
    } else {
      _showPending(action);
    }
  }

  void _showPending(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature: porting Flutter in corso.')),
    );
  }

  Future<void> _syncMarkdownFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var path = prefs.getString('markdown_mirror_path');
      path ??= await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Scegli cartella Markdown',
      );
      if (path == null || path.trim().isEmpty) return;

      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final shared = ref.read(sharedSpacesProvider);
      final blockedSharedIds = <String>{};
      final identity = shared.identity;
      for (final space in shared.spaces) {
        final role = identity == null ? null : space.roleFor(identity.id);
        if (role == null || !role.canEdit) {
          blockedSharedIds.addAll(space.contentIds);
        }
      }
      final eligible = snapshot.notes
          .where((note) => !blockedSharedIds.contains(note.id))
          .toList(growable: false);

      final result = await MarkdownFolderMirror.sync(path, eligible);

      // Re-check collaboration permissions immediately before persistence.
      final latestShared = ref.read(sharedSpacesProvider);
      final latestIdentity = latestShared.identity;
      for (final note in result.updatedNotes) {
        for (final space in latestShared.spaces) {
          if (!space.contentIds.contains(note.id)) continue;
          final role =
              latestIdentity == null ? null : space.roleFor(latestIdentity.id);
          if (role == null || !role.canEdit) {
            throw const FormatException(
              'La cartella Markdown non può modificare un contenuto Shared Space in sola lettura.',
            );
          }
        }
        await ref.read(workspaceProvider.notifier).save(note);
      }

      // The merge base becomes trusted only after DB writes have succeeded.
      await MarkdownFolderMirror.finalize(path, result);
      await prefs.setString('markdown_mirror_path', path);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cartella Markdown sincronizzata: ${result.writtenFiles} file scritti, '
            '${result.updatedNotes.length} aggiornamenti esterni, '
            '${result.conflicts} conflitti preservati.',
          ),
          action: SnackBarAction(
            label: 'Cambia cartella',
            onPressed: () async {
              final settings = await SharedPreferences.getInstance();
              await settings.remove('markdown_mirror_path');
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(error),
          ),
          action: SnackBarAction(
            label: 'Cambia cartella',
            onPressed: () async {
              final settings = await SharedPreferences.getInstance();
              await settings.remove('markdown_mirror_path');
            },
          ),
        ),
      );
    }
  }

  Future<void> _exportMarkdownWorkspace() async {
    try {
      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final syncedBlocks =
          await ref.read(knowledgeStoreProvider).syncedBlocks();
      final prefs = await SharedPreferences.getInstance();
      var sourceInstance = prefs.getString('interop_workspace_id_v1');
      if (sourceInstance == null || sourceInstance.trim().isEmpty) {
        sourceInstance = const Uuid().v4();
        await prefs.setString('interop_workspace_id_v1', sourceInstance);
      }
      final bytes = MarkdownWorkspaceBundle.encode(
        snapshot.notes,
        syncedBlocks: syncedBlocks,
        sourceInstance: sourceInstance,
      );
      final now = DateTime.now();
      final stamp = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta workspace Markdown',
        fileName: 'notes-markdown-$stamp.zip',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workspace Markdown esportato senza lock-in.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(error),
          ),
        ),
      );
    }
  }

  Future<void> _importMarkdownWorkspace() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('Impossibile leggere l’archivio Markdown.');
      }
      final package = MarkdownWorkspaceBundle.decodePackage(
        Uint8List.fromList(bytes),
      );
      final documents = package.documents;
      final sourceInstance = package.sourceInstance ??
          MarkdownWorkspaceBundle.fallbackSourceInstance(documents);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importare Markdown?'),
          content: Text(
            'Analizzerò ${documents.length} documenti. I re-import della stessa '
            'sorgente sono idempotenti: aggiorno solo ciò che è cambiato e '
            'preservo i conflitti senza sovrascrivere modifiche locali.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importa'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      const source = 'notes-markdown';
      final imported = <ImportDocument>[];
      for (final document in documents) {
        final tags = <String>{
          ...document.tags,
          'import-markdown',
        }.toList(growable: false);
        final identity = ImportIdentity(
          source: source,
          sourceInstance: sourceInstance,
          externalId: document.sourceId?.trim().isNotEmpty == true
              ? document.sourceId!.trim()
              : document.fileName.toLowerCase(),
        );
        imported.add(
          ImportDocument(
            identity: identity,
            title: document.title,
            body: document.body,
            tags: tags,
            taskJson: document.taskJson,
            externalFingerprint: ImportProvenance.fingerprint(
              title: document.title,
              body: document.body,
              tags: tags,
              taskJson: document.taskJson,
            ),
          ),
        );
      }

      final notifier = ref.read(workspaceProvider.notifier);
      final service = ImportApplicationService(
        ref.read(importProvenanceStoreProvider),
      );
      final summary = await service.apply(
        source: source,
        sourceInstance: sourceInstance,
        documents: imported,
        currentNotes: ref.read(workspaceProvider).notes,
        save: notifier.save,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import Markdown · ${summary.userLabel()}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userErrorText(error))),
      );
    }
  }

  Future<void> _importObsidianVault() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('Impossibile leggere il vault ZIP.');
      }
      final vault = ObsidianMigration.decode(Uint8List.fromList(bytes));
      if (vault.documents.isEmpty) {
        throw const FormatException('Nessuna nota Markdown trovata nel vault.');
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importare vault Obsidian?'),
          content: Text(
            '${vault.report.userLabel()}\n\n'
            'Wikilink, frontmatter compatibile e allegati supportati verranno '
            'convertiti. I re-import non duplicano le note già riconosciute.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importa vault'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      const source = 'obsidian-vault';
      final cleanFileName = result.files.single.name.trim().toLowerCase();
      final sourceInstance = cleanFileName.isNotEmpty
          ? cleanFileName
          : 'vault-${vault.sourceInstanceHint}';
      final provenance = ref.read(importProvenanceStoreProvider);
      final current = ref.read(workspaceProvider).notes;
      final currentById = {for (final note in current) note.id: note};

      final planned =
          <({ObsidianDocument document, ImportIdentity identity, String id})>[];
      for (final document in vault.documents) {
        final identity = ImportIdentity(
          source: source,
          sourceInstance: sourceInstance,
          externalId: document.path.toLowerCase(),
        );
        final record = await provenance.find(identity);
        final currentTarget =
            record == null ? null : currentById[record.targetNoteId];
        final id = currentTarget != null && !currentTarget.isDeleted
            ? currentTarget.id
            : const Uuid().v4();
        planned.add((document: document, identity: identity, id: id));
      }

      final store = await AttachmentStore.open();
      final assetRows = <({String path, String key})>[];
      for (final asset in vault.assets) {
        final key = await store.ingest(asset.bytes, asset.type);
        assetRows.add((path: asset.path, key: key));
      }
      final assetLookup = ObsidianMigration.assetLookup(assetRows);
      final noteLookup = ObsidianMigration.noteLookup([
        for (final item in planned)
          (
            path: item.document.path,
            title: item.document.title,
            id: item.id,
          ),
      ]);

      final imported = <ImportDocument>[];
      for (final item in planned) {
        final body = ObsidianMigration.resolveBody(
          document: item.document,
          noteIdsByKey: noteLookup,
          assetKeysByPath: assetLookup,
        );
        final tags = <String>{
          ...item.document.tags,
          'import-obsidian',
        }.toList(growable: false);
        imported.add(
          ImportDocument(
            identity: item.identity,
            title: item.document.title,
            body: body,
            tags: tags,
            externalFingerprint: ImportProvenance.fingerprint(
              title: item.document.title,
              body: body,
              tags: tags,
            ),
            targetIdHint: item.id,
          ),
        );
      }

      final summary = await ImportApplicationService(provenance).apply(
        source: source,
        sourceInstance: sourceInstance,
        documents: imported,
        currentNotes: current,
        save: ref.read(workspaceProvider.notifier).save,
      );
      await _cleanupAttachments(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import Obsidian · ${summary.userLabel()} · '
            '${vault.report.userLabel()}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userErrorText(error))),
      );
    }
  }

  Future<void> _exportBackup() async {
    try {
      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final store = await AttachmentStore.open();
      final properties = await ref.read(propertyStoreProvider).exportBackup();
      final knowledge = await ref.read(knowledgeStoreProvider).exportBackup();
      final derivatives =
          await ref.read(derivativeStoreProvider).exportBackup();
      final projects = await ref.read(projectStoreProvider).exportBackup();
      final bytes = await MediaBundle.encode(
        snapshot,
        store,
        properties: properties,
        knowledge: knowledge,
        derivatives: derivatives,
        projects: projects,
      );
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta backup completo Notes',
        fileName: 'notes-ecosistema-$stamp.zip',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup completo esportato con allegati.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(error),
          ),
        ),
      );
    }
  }

  Future<Uint8List> _createRecoveryBundleBytes() async {
    final workspace = ref.read(workspaceProvider.notifier);
    final database = ref.read(databaseProvider);
    final snapshot = await workspace.snapshot();
    final revisions = await database.recoveryRevisions();
    final blocks = await database.recoveryBlocks();
    final properties = await ref.read(propertyStoreProvider).exportBackup();
    final knowledge = await ref.read(knowledgeStoreProvider).exportBackup();
    final derivatives = await ref.read(derivativeStoreProvider).exportBackup();
    final projects = await ref.read(projectStoreProvider).exportBackup();
    final study = await ref.read(studyStoreProvider).exportBackup();
    final documents = await ref.read(documentStoreProvider).exportBackup();
    final importProvenance =
        await ref.read(importProvenanceStoreProvider).exportBackup();
    final automations =
        await ref.read(workflowAutomationStoreProvider).exportBackup();
    final shared = ref.read(sharedSpacesProvider.notifier).snapshot();
    final store = await AttachmentStore.open();

    final bytes = await DisasterRecoveryBundle.encode(
      snapshot: snapshot,
      revisions: revisions,
      blocks: blocks,
      properties: properties,
      knowledge: knowledge,
      derivatives: derivatives,
      projects: projects,
      study: study,
      documents: documents,
      importProvenance: importProvenance,
      automations: automations,
      sharedSpaces: shared,
      store: store,
    );

    // The decoded preview validates integrity, references and every asset.
    DisasterRecoveryBundle.decode(bytes);
    return bytes;
  }

  Future<void> _exportDisasterRecovery() async {
    try {
      final bytes = await _createRecoveryBundleBytes();

      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final savedBackup = await FilePicker.platform.saveFile(
        dialogTitle: 'Crea backup di ripristino Notes',
        fileName: 'notes-recovery-$stamp.zip',
        bytes: bytes,
      );
      if (savedBackup == null || savedBackup.trim().isEmpty) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup di ripristino creato e verificato.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userErrorText(error))),
      );
    }
  }

  Future<void> _applyDisasterRecovery(
    DisasterRecoveryPreview recovery,
  ) async {
    final noteIds = recovery.snapshot.notes.map((note) => note.id).toSet();
    final sharedIds =
        recovery.sharedSpaces.spaces.map((space) => space.id).toSet();
    // Content-addressed originals must survive until the journal is cleared.
    final store = await AttachmentStore.open();
    for (final entry in recovery.assets.entries) {
      await store.put(entry.key, entry.value);
    }

    await ref.read(databaseProvider).restoreExact(
          snapshot: recovery.snapshot,
          revisions: recovery.revisions,
          blocks: recovery.blocks,
        );
    await ref.read(propertyStoreProvider).restoreBackupExact(
          recovery.properties,
          noteIds: noteIds,
        );
    await ref.read(knowledgeStoreProvider).restoreBackupExact(
          recovery.knowledge,
          noteIds: noteIds,
        );
    await ref.read(derivativeStoreProvider).restoreBackupExact(
          recovery.derivatives,
          noteIds: noteIds,
        );
    await ref.read(sharedSpacesProvider.notifier).restoreExact(
          recovery.sharedSpaces,
        );
    await ref.read(projectStoreProvider).restoreBackupExact(
          recovery.projects,
          noteIds: noteIds,
          sharedSpaceIds: sharedIds,
        );
    await ref.read(studyStoreProvider).restoreBackupExact(
          recovery.study,
          noteIds: noteIds,
        );
    await ref.read(documentStoreProvider).restoreBackupExact(
          recovery.documents,
          noteIds: noteIds,
          assetKeys: recovery.assets.keys.toSet(),
        );
    await ref.read(importProvenanceStoreProvider).restoreBackupExact(
          recovery.importProvenance,
          noteIds: noteIds,
        );
    await ref.read(workflowAutomationStoreProvider).restoreBackupExact(
          recovery.automations,
          noteIds: noteIds,
        );

    await ref.read(workspaceProvider.notifier).refresh();
    await ref.read(workflowAutomationProvider.notifier).refresh();
    await ref.read(studyProvider.notifier).refresh();
    await ref.read(projectWorkspaceProvider.notifier).refresh();
    // Never GC original assets inside an uncommitted cross-store restore.
  }

  Future<void> _restoreDisasterRecovery() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ripristino distruttivo disponibile solo con journal locale nativo.',
          ),
        ),
      );
      return;
    }
    if (!_recoveryGateOpen || _restoreBusy) return;
    _restoreBusy = true;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException(
          'Impossibile leggere il backup di ripristino.',
        );
      }

      // Decode validates the whole archive, file whitelist, checksums,
      // object graph and attachments before any persistent state is changed.
      final recovery = DisasterRecoveryBundle.decode(
        Uint8List.fromList(bytes),
      );
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ripristinare lo stato Notes?'),
          content: Text(
            'Questa operazione sostituisce lo stato locale con il backup: '
            '${recovery.snapshot.notes.length} elementi, '
            '${recovery.snapshot.collections.length} raccolte, '
            '${recovery.assets.length} allegati e i relativi metadati. '
            'Il pacchetto migrazione/import rimane separato e continua a '
            'creare copie. Usa Ripristino solo per disaster recovery. '
            'Prima di scrivere è obbligatorio salvare una copia di '
            'sicurezza dello stato attuale.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ripristina stato'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      // Refuse destructive restore while Shared Live Sync is writing.
      // The pause prevents foreground, delayed and periodic sync from starting
      // while the external safety ZIP is being saved, checked and restored.
      await _acquireRecoveryPause();

      // Cross-store restores are NOT one atomic transaction. Require a
      // recoverable copy of the current state before touching any store.
      // Cancelling this Save As operation leaves the existing data intact.
      final safetyBytes = await _createRecoveryBundleBytes();
      final savedSafetyCopy = await FilePicker.platform.saveFile(
        dialogTitle: 'Salva prima il backup di sicurezza obbligatorio',
        fileName:
            'notes-pre-ripristino-${DateTime.now().millisecondsSinceEpoch}.zip',
        bytes: safetyBytes,
      );
      if (savedSafetyCopy == null || savedSafetyCopy.trim().isEmpty) {
        return;
      }

      // Saving is not sufficient evidence for Android SAF or external
      // document providers. The user must re-open the externally stored copy.
      // All persistent restore writes are below this gate.
      if (!mounted) return;
      final verifyReadback = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Verifica il backup di sicurezza'),
          content: const Text(
            'Prima di ripristinare, seleziona il file ZIP appena salvato. '
            'Notes confronterà tutti i byte del file con il backup creato. '
            'Puoi annullare senza modificare alcun dato.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla ripristino'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Seleziona copia salvata'),
            ),
          ],
        ),
      );
      if (verifyReadback != true) return;
      final externalCopy = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (externalCopy == null || externalCopy.files.isEmpty) return;
      RecoverySafety.requireVerifiedExternalCopy(
        generated: safetyBytes,
        readBack: externalCopy.files.single.bytes,
      );
      // Hide all interactive app surfaces while the multi-store transaction
      // runs. The existing picker/confirmation dialogs have already closed.
      if (!mounted) return;
      setState(() {
        _recoveryGateOpen = false;
        _recoveryGateError = null;
      });

      final journal = _recoveryJournal ?? await RecoveryJournal.open();
      _recoveryJournal = journal;
      // The externally verified bytes are additionally persisted in an
      // integrity-checked private undo journal BEFORE the first store write.
      await RecoveryTransaction.run(
        journal: journal,
        originalSnapshot: safetyBytes,
        applyCandidate: () => _applyDisasterRecovery(recovery),
        applyOriginal: (bytes) =>
            _applyDisasterRecovery(DisasterRecoveryBundle.decode(bytes)),
      );
      // Do not garbage-collect pre-restore CAS originals automatically.
      // The journal can no longer require them, but device backup is safer
      // when cleanup is an explicit later operation.

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Stato Notes ripristinato con identità originali.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              error,
              fallback:
                  'Ripristino non completato: conserva la copia pre-ripristino prima di riprovare, perché più archivi possono essere stati modificati.',
            ),
          ),
        ),
      );
    } finally {
      var pending = false;
      try {
        pending =
            _recoveryJournal != null && await _recoveryJournal!.hasUnsettled;
      } catch (_) {
        // A failed durability check is unresolved recovery, not success.
        // Keep the sync pause and always expose the retry affordance.
        pending = true;
      }
      if (!pending) await _releaseRecoveryPause();
      _restoreBusy = false;
      if (mounted) {
        setState(() {
          _recoveryGateOpen = !pending;
          _recoveryGateError = pending
              ? 'Ripristino interrotto. È necessario completare il recupero '
                  'prima di usare Notes.'
              : null;
        });
      }
    }
  }

  Future<void> _exportOpenArchive() async {
    try {
      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final store = await AttachmentStore.open();
      final bytes = await OpenExportBundle.encode(
        snapshot: snapshot,
        properties: await ref.read(propertyStoreProvider).exportBackup(),
        knowledge: await ref.read(knowledgeStoreProvider).exportBackup(),
        projects: await ref.read(projectStoreProvider).exportBackup(),
        study: await ref.read(studyStoreProvider).exportBackup(),
        documents: await ref.read(documentStoreProvider).exportBackup(),
        automations:
            await ref.read(workflowAutomationStoreProvider).exportBackup(),
        store: store,
      );
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta archivio aperto Notes',
        fileName: 'notes-open-export-$stamp.zip',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open Export creato: Markdown, JSON strutturato e media.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userErrorText(error))),
      );
    }
  }

  Future<void> _exportLegacyJson() async {
    try {
      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta backup JSON Notes',
        fileName: 'notes-ecosistema-$stamp.json',
        bytes: backupUtf8(snapshot),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup JSON esportato.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(error),
          ),
        ),
      );
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['zip', 'json'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('Impossibile leggere il backup.');
      }

      final isZip = file.extension?.toLowerCase() == 'zip';
      late final BackupSnapshot snapshot;
      MediaBundlePreview? bundle;
      if (isZip) {
        bundle = MediaBundle.decode(Uint8List.fromList(bytes));
        snapshot = bundle.snapshot;
      } else {
        snapshot = BackupCodec.decode(
          utf8.decode(bytes, allowMalformed: false),
        );
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importare il backup?'),
          content: Text(
            'Verranno create copie separate: '
            '${snapshot.notes.length} elementi, '
            '${snapshot.collections.length} raccolte e '
            '${snapshot.drafts.length} bozze.'
            '${bundle == null ? '' : ' Il pacchetto include ${bundle.assets.length} allegati.'} '
            'I dati esistenti non verranno sovrascritti.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importa copie'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      if (bundle != null) {
        final store = await AttachmentStore.open();
        await MediaBundle.installAssets(bundle, store);
      }
      final plan =
          await ref.read(workspaceProvider.notifier).importCopies(snapshot);
      if (bundle != null) {
        await ref.read(propertyStoreProvider).importBackup(
              bundle.properties,
              noteIdMap: plan.noteIdMap,
            );
        final blockMap = await ref.read(knowledgeStoreProvider).importBackup(
              bundle.knowledge,
              noteIdMap: plan.noteIdMap,
            );
        await ref.read(derivativeStoreProvider).importBackup(
              bundle.derivatives,
              noteIdMap: plan.noteIdMap,
            );
        await ref.read(projectStoreProvider).importBackup(
              bundle.projects,
              noteIdMap: plan.noteIdMap,
            );
        await ref.read(projectWorkspaceProvider.notifier).refresh();

        if (blockMap.isNotEmpty) {
          final notifier = ref.read(workspaceProvider.notifier);
          for (final note in plan.notes) {
            if (note.isVisual) continue;
            final body = SyncedBlockCodec.remapReferences(note.body, blockMap);
            if (body != note.body) {
              await notifier.save(
                note.copyWith(
                  body: body,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                ),
              );
            }
          }
          final database = ref.read(databaseProvider);
          for (final draft in plan.drafts) {
            final body = SyncedBlockCodec.remapReferences(
              draft.body,
              blockMap,
            );
            if (body == draft.body) continue;
            await database.saveDraft(
              BackupDraft(
                id: draft.id,
                title: draft.title,
                body: body,
                collectionId: draft.collectionId,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
                tags: draft.tags,
              ),
            );
          }
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bundle == null
                ? 'Backup JSON importato come copie.'
                : 'Backup completo importato con allegati e metadati sidecar.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(error),
          ),
        ),
      );
    }
  }

  Future<void> _restoreFromTrash(String id) async {
    await ref.read(workspaceProvider.notifier).restore(id);
  }

  Future<void> _deleteForever(String id) async {
    final shared = ref.read(sharedSpacesProvider);
    final identity = shared.identity;
    final linkedSpaces = shared.spaces
        .where((space) => space.contentIds.contains(id))
        .toList(growable: false);

    if (linkedSpaces.isNotEmpty) {
      if (identity == null) {
        throw const FormatException(
          'Impossibile verificare i permessi dello Shared Space.',
        );
      }
      for (final space in linkedSpaces) {
        final role = space.roleFor(identity.id);
        if (role == null || !role.canEdit) {
          throw const FormatException(
            'Questo elemento è ancora condiviso in uno spazio che non puoi modificare. '
            'Rimuovilo dallo spazio prima dell’eliminazione definitiva.',
          );
        }
      }
      for (final space in linkedSpaces) {
        await ref
            .read(sharedSpacesProvider.notifier)
            .unlinkContent(space.id, id);
      }
    }

    await ref.read(workspaceProvider.notifier).deleteForever(id);
    await ref.read(propertyStoreProvider).deleteValuesForNote(id);
    await ref.read(knowledgeStoreProvider).deleteForNote(id);
    await ref.read(derivativeStoreProvider).deleteForNote(id);
    await ref.read(semanticIndexStoreProvider).deleteForNote(id);
    await ref.read(documentStoreProvider).deleteForNote(id);
    await ref.read(projectStoreProvider).deleteLinksForNote(id);
    await ref.read(importProvenanceStoreProvider).deleteForNote(id);
    await ref.read(workflowAutomationStoreProvider).deleteRunsForNote(id);
    await ref.read(projectWorkspaceProvider.notifier).refresh();
    await _cleanupAttachments(silent: true);
    if (linkedSpaces.isNotEmpty) {
      await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
    }
  }

  Future<void> _cleanupAttachments({bool silent = false}) async {
    try {
      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final derivativeAssetKeys =
          await ref.read(derivativeStoreProvider).referencedAssetKeys();
      final documentAssetKeys =
          await ref.read(documentStoreProvider).referencedAssetKeys();
      final referenced = Attachments.referencedKeys(
        noteBodies: snapshot.notes.map((note) => note.body),
        draftBodies: snapshot.drafts.map((draft) => draft.body),
        sidecarKeys: <String?>{
          ...derivativeAssetKeys,
          ...documentAssetKeys,
        },
      );

      final store = await AttachmentStore.open();
      final result = await store.cleanup(referenced);
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.files == 0
                ? 'Nessun allegato orfano trovato.'
                : 'Rimossi ${result.files} allegati orfani '
                    '(${(result.bytes / 1024 / 1024).toStringAsFixed(1)} MiB).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(error),
          ),
        ),
      );
    }
  }

  Future<void> _selectLanguage(BuildContext sheetContext) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(AppStrings.of(dialogContext).language),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'system'),
            child: Text(AppStrings.of(dialogContext).systemLanguage),
          ),
          for (final code in const ['it', 'en', 'es', 'fr', 'de', 'pt'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, code),
              child: Text(AppLocale.label(code)),
            ),
        ],
      ),
    );
    if (selected == null) return;
    widget.onLocaleChanged(selected == 'system' ? null : selected);
    if (sheetContext.mounted) Navigator.pop(sheetContext);
  }

  Future<void> _settings(BuildContext context) => showNotesBottomSheet<void>(
        context: context,
        expand: true,
        builder: (context) => SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const EditorialAppTitle('Impostazioni'),
              const SizedBox(height: 16),
              EditorialSection(AppStrings.of(context).profile),
              ListTile(
                leading: const Icon(Icons.translate),
                title: Text(AppStrings.of(context).language),
                subtitle: Text(AppLocale.label(widget.localeCode)),
                onTap: () => _selectLanguage(context),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Tema scuro'),
                value: widget.dark,
                onChanged: widget.onDarkChanged,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.hub_outlined),
                title: const Text('Ricerca semantica locale'),
                subtitle: const Text(
                  'Indice vettoriale sul dispositivo. Disattivandolo resta sempre disponibile la ricerca classica.',
                ),
                value: _semanticSearchEnabled,
                onChanged: (value) async {
                  setState(() => _semanticSearchEnabled = value);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(_semanticSearchPreference, value);
                  if (!value) {
                    await ref.read(semanticIndexStoreProvider).clear();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.security_update_good_outlined),
                title: const Text('Crea backup di ripristino'),
                subtitle: const Text(
                  'Disaster recovery: conserva identità, blocchi, cronologia, metadati e allegati.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _exportDisasterRecovery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.restore_page_outlined),
                title: const Text('Ripristina stato Notes'),
                subtitle: const Text(
                  'Sostituisce lo stato locale con un backup di ripristino verificato.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _restoreDisasterRecovery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Esporta pacchetto migrazione'),
                subtitle: const Text(
                  'Media Bundle v3: portabile e importabile come copie.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _exportBackup();
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Importa pacchetto / backup legacy'),
                subtitle: const Text(
                    'Importa come copie senza sovrascrivere i dati attuali.'),
                onTap: () {
                  Navigator.pop(context);
                  _importBackup();
                },
              ),
              ListTile(
                leading: const Icon(Icons.sync_outlined),
                title: const Text('Sincronizza cartella Markdown'),
                subtitle: const Text(
                  'Mirror interoperabile con protezione dei cambi esterni e conflitti.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _syncMarkdownFolder();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_zip_outlined),
                title: const Text('Esporta archivio aperto'),
                subtitle: const Text(
                  'Markdown + JSON strutturato + media, leggibili senza Notes.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _exportOpenArchive();
                },
              ),
              ListTile(
                leading: const Icon(Icons.text_snippet_outlined),
                title: const Text('Esporta workspace Markdown'),
                subtitle: const Text(
                  'ZIP con file .md leggibili anche fuori da Notes.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _exportMarkdownWorkspace();
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_folder_upload_outlined),
                title: const Text('Importa Markdown'),
                subtitle: const Text(
                  'Re-import sicuro: aggiorna ciò che cambia senza duplicare.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _importMarkdownWorkspace();
                },
              ),
              ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: const Text('Importa vault Obsidian'),
                subtitle: const Text(
                  'ZIP con Markdown, frontmatter, wikilink e allegati supportati.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _importObsidianVault();
                },
              ),
              ListTile(
                leading: const Icon(Icons.data_object),
                title: const Text('Esporta JSON compatibile'),
                subtitle: const Text(
                  'Backup v6 senza file multimediali, per compatibilità Kotlin.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _exportLegacyJson();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Pulisci allegati orfani'),
                subtitle: const Text(
                  'Rimuove solo file non referenziati da note, bozze, OCR o annotazioni PDF.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _cleanupAttachments();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Scorciatoia Nuova nota'),
                subtitle: const Text(
                  'Aggiunge alla Home un accesso diretto al Quick Capture.',
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final requested = await QuickCaptureBridge.pinNoteShortcut();
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        requested
                            ? 'Richiesta scorciatoia inviata alla Home.'
                            : 'Launcher non compatibile: tieni premuta l’icona di Notes.',
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.widgets_outlined),
                title: const Text('Aggiungi widget Quick Capture'),
                subtitle: const Text(
                  'Widget Home con Nuova nota e Checklist.',
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final requested = await QuickCaptureBridge.pinCaptureWidget();
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        requested
                            ? 'Richiesta widget inviata alla Home.'
                            : 'Apri il selettore Widget Android e cerca Notes.',
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('GitHub Sync'),
                subtitle: const Text(
                  'Sincronizza note e allegati con un repository GitHub.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).push(
                    MaterialPageRoute(
                      builder: (_) => GitHubSyncScreen(
                        database: ref.read(databaseProvider),
                        onLocalChanged: () =>
                            ref.read(workspaceProvider.notifier).refresh(),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifiche promemoria'),
                subtitle: const Text(
                  'Abilita le notifiche Android per i promemoria delle attività.',
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final allowed = await ReminderBridge.requestPermission();
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        allowed
                            ? 'Notifiche promemoria abilitate.'
                            : 'Notifiche non abilitate. I promemoria restano salvati.',
                      ),
                      action: allowed
                          ? null
                          : SnackBarAction(
                              label: 'Impostazioni',
                              onPressed: () {
                                ReminderBridge.openSettings();
                              },
                            ),
                    ),
                  );
                },
              ),
              const ListTile(
                title: Text('Notes · Flutter 0.45.0'),
                subtitle: Text(
                  'Shared Spaces selettivi · database locale ancora compatibile con Room v8.',
                ),
              ),
            ],
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const Icon(Icons.error_outline, size: 42),
          const SizedBox(height: 12),
          Text(
            'Database non disponibile.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Il port Flutter non ha modificato i dati. Riprova ad aprire il database locale.',
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      );
}
