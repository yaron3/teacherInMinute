#!/bin/zsh

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

cd /Users/yaronjackoby/code/projects-own/teacherInMoment/teacher-minute/Android || exit 1

./gradlew bundleRelease

/usr/bin/open ../.build/Android/app/outputs/bundle/release

cd teacher-minute/.build/plugins/outputs/teacher-minute/TeacherMinute/destination/skipstone/TeacherMinute/build/jni-libs

zip -r native-debug-symbols.zip .

open .
