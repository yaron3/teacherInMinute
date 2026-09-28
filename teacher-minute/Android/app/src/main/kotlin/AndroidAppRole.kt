package teacher.minute

/**
 * Which of the two apps this build is, read by AppRole.swift over JNI.
 *
 * Each product flavor in build.gradle.kts sets its own BuildConfig.APP_ROLE:
 * "student" for Instant Teacher, "teacher" for Pro Teacher.
 */
object AndroidAppRole {
    @JvmStatic
    fun appRole(): String = BuildConfig.APP_ROLE
}
