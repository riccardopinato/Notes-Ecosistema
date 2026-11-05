# Notes Ecosistema Flutter 0.25.1
# google_mlkit_text_recognition references optional recognizers for scripts that
# are not packaged because Smart Capture currently uses the Latin recognizer.
# Keep R8 shrinking enabled while allowing those optional classes to stay absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# PDFBox-Android JPXFilter references optional Gemalto JPEG2000 codecs.
# These codecs are not packaged; suppress only the missing optional classes.
# JPX/JPEG2000 PDF fidelity is not certified without physical-device testing.
-dontwarn com.gemalto.jp2.JP2Decoder
-dontwarn com.gemalto.jp2.JP2Encoder
