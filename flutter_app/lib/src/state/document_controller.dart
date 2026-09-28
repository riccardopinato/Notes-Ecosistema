import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/document_store.dart';

final documentStoreProvider = Provider<DocumentStore>((ref) {
  final store = DocumentStore();
  ref.onDispose(store.close);
  return store;
});
