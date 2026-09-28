import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/document_store.dart';
import '../data/study_store.dart';

final studyStoreProvider = Provider<StudyStore>((ref) {
  final store = StudyStore();
  ref.onDispose(store.close);
  return store;
});

final documentStoreProvider = Provider<DocumentStore>((ref) {
  final store = DocumentStore();
  ref.onDispose(store.close);
  return store;
});
