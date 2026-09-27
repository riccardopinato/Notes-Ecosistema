import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const double notesBottomSheetMaxHeightFactor = 0.92;

Future<T?> showNotesBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool expand = false,
  bool showDragHandle = true,
  double maxHeightFactor = notesBottomSheetMaxHeightFactor,
}) {
  assert(maxHeightFactor > 0 && maxHeightFactor <= 1);
  final media = MediaQuery.of(context);
  final availableHeight =
      media.size.height - media.padding.top - media.padding.bottom;
  final maxHeight = availableHeight * maxHeightFactor;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: showDragHandle,
    constraints: BoxConstraints(maxHeight: maxHeight),
    builder: (sheetContext) {
      final child = builder(sheetContext);
      return expand ? SizedBox(height: maxHeight, child: child) : child;
    },
  );
}

String userErrorText(
  Object error, {
  String fallback = 'Operazione non riuscita. Riprova.',
}) {
  if (error is FormatException) {
    final message = error.message.toString().trim();
    return message.isEmpty ? fallback : message;
  }
  if (error is SocketException) {
    return 'Connessione non disponibile. Controlla la rete e riprova.';
  }
  if (error is FileSystemException) {
    return 'Impossibile accedere al file richiesto.';
  }

  String raw;
  if (error is PlatformException) {
    raw = (error.message ?? '').trim();
  } else {
    raw = error.toString().trim();
  }

  raw = raw
      .replaceFirst(RegExp(r'^PlatformException\([^,]+,\s*'), '')
      .replaceFirst(RegExp(r'^FormatException:\s*'), '')
      .replaceFirst(RegExp(r'^Exception:\s*'), '');

  final lower = raw.toLowerCase();
  final looksTechnical = raw.isEmpty ||
      lower.contains('nullpointerexception') ||
      lower.contains('java.lang.') ||
      lower.contains('attempt to invoke virtual method') ||
      lower.contains('r8-map-id') ||
      lower.contains('stack trace') ||
      lower.contains('stacktrace') ||
      RegExp(r'\bat\s+[a-z0-9_.$<>]+\(', caseSensitive: false)
          .hasMatch(raw);

  if (looksTechnical || raw.length > 320) return fallback;
  return raw;
}
