# ML Kit text recognition refers to its other scripts' recognizers
# (Chinese, Devanagari, Japanese, Korean), which TabCam doesn't bundle: it
# reads Latin script only. Without these, R8 fails the release build.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
