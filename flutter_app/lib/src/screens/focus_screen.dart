import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../domain/focus.dart';
import '../domain/note.dart';
import '../domain/planner.dart';

class FocusSessionScreen extends StatefulWidget {
  const FocusSessionScreen({
    required this.note,
    required this.onSave,
    super.key,
  });

  final Note note;
  final Future<void> Function(Note note) onSave;

  @override
  State<FocusSessionScreen> createState() => _FocusSessionScreenState();
}

class _FocusSessionScreenState extends State<FocusSessionScreen> {
  Timer? _ticker;
  FocusClock? _clock;
  bool _busy = false;
  String? _error;

  TaskDetails get _task => TaskDetails.decode(widget.note.taskJson!);

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    FocusClock? clock;
    final raw = prefs.getString('planner_focus_active_v1');
    if (raw != null) {
      try {
        final decoded = FocusClock.decode(raw);
        if (decoded.taskId == widget.note.id) clock = decoded;
      } catch (_) {}
    }
    if (clock == null) {
      final minutes = (_task.plannedDate == null ? 25 : _task.plannedMinutes)
          .clamp(1, 120)
          .toInt();
      clock = FocusClock.start(
        sessionId: const Uuid().v4(),
        taskId: widget.note.id,
        minutes: minutes,
        now: DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setString('planner_focus_active_v1', clock.encode());
    }
    if (!mounted) return;
    setState(() => _clock = clock);
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _clock?.pausedMillis == null) setState(() {});
    });
  }

  Future<void> _persist(FocusClock? clock) async {
    final prefs = await SharedPreferences.getInstance();
    if (clock == null) {
      await prefs.remove('planner_focus_active_v1');
    } else {
      await prefs.setString('planner_focus_active_v1', clock.encode());
    }
  }

  Future<void> _pauseResume() async {
    final current = _clock;
    if (current == null || _busy) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final next = current.pausedMillis == null
          ? current.pause(now)
          : current.resume(now);
      await _persist(next);
      if (mounted) setState(() => _clock = next);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e.toString().replaceFirst('FormatException: ', ''));
      }
    }
  }

  Future<void> _recordCurrent({required bool nextInterval}) async {
    final current = _clock;
    if (current == null || _busy || current.phase != FocusPhase.work) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = current.durationSeconds - current.remaining(now);
    if (elapsed <= 0) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updatedTask = _task.addFocusSession(
        sessionId: current.sessionId,
        seconds: elapsed.clamp(1, 7200).toInt(),
        endedAt: now,
      );
      await widget.onSave(
        widget.note.copyWith(
          taskJson: updatedTask.encode(),
          updatedAt: now,
        ),
      );

      FocusClock? next;
      if (nextInterval) {
        final finished = current.finished(now)
            ? current
            : current.copyWith(
                deadline: now,
                pausedMillis: null,
              );
        next = finished.next(now, const Uuid().v4());
      }
      await _persist(next);
      if (!mounted) return;
      if (next == null) {
        Navigator.pop(context);
      } else {
        setState(() {
          _clock = next;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }

  Future<void> _next() async {
    final current = _clock;
    if (current == null || _busy) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!current.finished(now)) return;

    if (current.phase == FocusPhase.work) {
      await _recordCurrent(nextInterval: true);
      return;
    }

    try {
      final next = current.next(now, const Uuid().v4());
      await _persist(next);
      if (mounted) setState(() => _clock = next);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e.toString().replaceFirst('FormatException: ', ''));
      }
    }
  }

  Future<void> _discard() async {
    await _persist(null);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final clock = _clock;
    if (clock == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = clock.remaining(now);
    final progress =
        1 - remaining / clock.durationSeconds.clamp(1, 7200).toDouble();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: Text(
          clock.phase == FocusPhase.work
              ? 'Il tuo momento'
              : 'Prenditi una pausa',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            child: Column(
              children: [
                Text(
                  clock.phase == FocusPhase.work
                      ? 'FOCUS · BLOCCO ' +
                          (clock.completedBlocks + 1).toString()
                      : 'PAUSA · ' +
                          clock.completedBlocks.toString() +
                          ' BLOCCHI REGISTRATI',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.note.title.isEmpty ? 'Attività' : widget.note.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress.clamp(0, 1),
                        strokeWidth: 10,
                        color: Theme.of(context).colorScheme.onPrimary,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .onPrimary
                            .withValues(alpha: 0.2),
                      ),
                      Text(
                        (remaining ~/ 60).toString().padLeft(2, '0') +
                            ':' +
                            (remaining % 60).toString().padLeft(2, '0'),
                        style: Theme.of(context)
                            .textTheme
                            .displayMedium
                            ?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onPrimary,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  clock.pausedMillis != null
                      ? 'Timer in pausa. Il tempo non aumenta.'
                      : clock.finished(now)
                          ? 'Intervallo concluso.'
                          : 'Il conteggio continua anche uscendo dalla schermata.',
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                if (!clock.finished(now))
                  FilledButton.tonal(
                    onPressed: _busy ? null : _pauseResume,
                    child: Text(
                      clock.pausedMillis == null ? 'Metti in pausa' : 'Riprendi',
                    ),
                  ),
                if (clock.finished(now))
                  FilledButton.tonal(
                    onPressed: _busy ? null : _next,
                    child: Text(
                      clock.phase == FocusPhase.work
                          ? 'Registra e inizia pausa'
                          : 'Inizia prossimo Focus',
                    ),
                  ),
                if (clock.phase == FocusPhase.work)
                  FilledButton.tonal(
                    onPressed: _busy ||
                            currentElapsed(clock, now) <= 0
                        ? null
                        : () => _recordCurrent(nextInterval: false),
                    child: const Text('Termina e registra'),
                  ),
                TextButton(
                  onPressed: _busy ? null : _discard,
                  style: TextButton.styleFrom(
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: Text(
                    clock.phase == FocusPhase.work
                        ? 'Scarta intervallo'
                        : 'Termina pausa',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int currentElapsed(FocusClock clock, int now) =>
    clock.durationSeconds - clock.remaining(now);
