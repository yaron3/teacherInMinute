-keeppackagenames **
-keep class skip.** { *; }
-keep class tools.skip.** { *; }
-keep class kotlin.jvm.functions.** {*;}
-keep class com.sun.jna.** { *; }
-dontwarn java.awt.**
-keep class * implements com.sun.jna.** { *; }
-keep class * implements skip.bridge.** { *; }
-keep class **._ModuleBundleAccessor_* { *; }
-keep class teacher.minute.** { *; }

# The Skip bridges look Kotlin methods up over JNI by signature, and those
# signatures name Firebase SDK types, e.g. FieldValue.Companion.serverTimestamp()
# is "()Lcom/google/firebase/firestore/FieldValue;". R8 renamed FieldValue to
# com.google.firebase.firestore.z, so the lookup found nothing and the bridge's
# force-unwrap trapped (SIGTRAP in libSkipFirebaseFirestore.so).
-keepnames class com.google.firebase.**

# MainActivity calls enableEdgeToEdge(), but R8 renames androidx.activity.EdgeToEdge
# (to androidx.activity.v) and can inline the call, so Play Console's scan of the
# bundle finds no edge-to-edge setup and warns "Edge-to-edge may not display for
# all users". Keeping the entry points leaves the call visible to that scan.
-keep class androidx.activity.EdgeToEdge {
    public static void enable(...);
}
