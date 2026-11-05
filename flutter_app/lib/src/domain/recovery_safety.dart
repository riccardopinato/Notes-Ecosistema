import 'dart:typed_data';

/// A restore may start only after its current-state backup has been saved to
/// external storage AND read back byte-for-byte through a user-selected file.
///
/// This validates the safety copy, not the archive to be restored (the latter
/// is independently checked by DisasterRecoveryBundle.decode).
abstract final class RecoverySafety {
  static void requireVerifiedExternalCopy({
    required Uint8List generated,
    required Uint8List? readBack,
  }) {
    if (readBack == null || generated.length != readBack.length) {
      throw const FormatException(
        'Il backup pre-ripristino non è stato verificato: '
        'nessun dato è stato modificato.',
      );
    }
    // Constant-time with respect to the first mismatch, to avoid accepting
    // partial/corrupted copies while keeping memory usage bounded.
    var difference = 0;
    for (var i = 0; i < generated.length; i++) {
      difference |= generated[i] ^ readBack[i];
    }
    if (difference != 0) {
      throw const FormatException(
        'La copia pre-ripristino riletta non corrisponde al backup: '
        'nessun dato è stato modificato.',
      );
    }
  }
}
