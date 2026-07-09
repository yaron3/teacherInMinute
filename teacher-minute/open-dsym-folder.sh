#!/bin/zsh

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

PROJECT_HOME="/Users/yaronjackoby/code/projects-own/teacherInMoment"

cd "$PROJECT_HOME" || exit 1

DSYM_PATH=$(find . -name "*.dSYM" -type d | head -n 1)

if [ -z "$DSYM_PATH" ]; then
  echo "No .dSYM folder found under $PROJECT_HOME"
  exit 1
fi

DSYM_FOLDER=$(dirname "$DSYM_PATH")

echo "Found dSYM:"
echo "$DSYM_PATH"
echo "Opening folder:"
echo "$DSYM_FOLDER"

/usr/bin/open "$DSYM_FOLDER"
