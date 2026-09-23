# Notes Ecosistema Flutter 0.25.1
# google_mlkit_text_recognition references optional recognizers for scripts that
# are not packaged because Smart Capture currently uses the Latin recognizer.
# Keep R8 shrinking enabled while allowing those optional classes to stay absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
