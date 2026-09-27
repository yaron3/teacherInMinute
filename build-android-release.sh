#!/bin/zsh

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

cd /Users/yaronjackoby/code/projects-own/teacherInMoment/teacher-minute/Android || exit 1

# Both apps: bundle/studentRelease (Instant Teacher) and
# bundle/teacherRelease (Pro Teacher).
./gradlew bundleRelease

/usr/bin/open ../.build/Android/app/outputs/bundle

cd teacher-minute/.build/plugins/outputs/teacher-minute/TeacherMinute/destination/skipstone/TeacherMinute/build/jni-libs

zip -r native-debug-symbols.zip .

open .
