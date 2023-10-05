#!/usr/bin/env bash

set -o nounset
set -o errexit

echo "Setting up workspace..."
CWD="$(pwd)"
declare -r CWD
declare -r DEPS_DIR="$CWD/deps"

declare -r GNU_PARALLEL_HOME="$DEPS_DIR/parallel"
declare -r GNU_PARALLEL_BUILD="$DEPS_DIR/build-parallel"
declare -r GNU_PARALLEL_RELEASE="20210722"
declare -r GNU_PARALLEL_URL="https://ftp.gnu.org/gnu/parallel/parallel-$GNU_PARALLEL_RELEASE.tar.bz2"

declare -r D4J_HOME="$DEPS_DIR/defects4j"
declare -r D4J_URL="https://github.com/rjust/defects4j"
declare -r D4J_VERSION="v2.0.0"

declare -r MAJOR_HOME="$DEPS_DIR/major"
declare -r MAJOR_RELEASE="major-2.0.0-rc1_jre8.zip"
declare -r MAJOR_URL="https://mutation-testing.org/downloads/$MAJOR_RELEASE"

#
# Download and set up D4J and Major
#
main() {
  # Remove previously installed dependencies if they exist
  rm -rf "$GNU_PARALLEL_HOME" "$GNU_PARALLEL_BUILD" "$MAJOR_HOME" "$D4J_HOME" 

  # Download GNU Parallel
  echo "Download GNU Parallel..."
  wget "$GNU_PARALLEL_URL" -P "$DEPS_DIR" || failure "Download GNU Parallel" "wget failed to download $GNU_PARALLEL_URL."
  cd "$DEPS_DIR"
  tar xf "parallel-$GNU_PARALLEL_RELEASE.tar.bz2"
  mv "parallel-$GNU_PARALLEL_RELEASE" "$GNU_PARALLEL_BUILD"
  rm "parallel-$GNU_PARALLEL_RELEASE.tar.bz2"
  cd "$GNU_PARALLEL_BUILD"
  ./configure "--prefix=$GNU_PARALLEL_HOME"
  make
  make install
  cd "$CWD"
  rm -rf "$GNU_PARALLEL_BUILD"

  # Download and unzip Major
  echo "Download Major ..."
  wget "$MAJOR_URL" -P "$DEPS_DIR" || failure "Download Major" "wget failed to download $MAJOR_URL."
  (cd "$DEPS_DIR" && unzip "$MAJOR_RELEASE" && rm "$MAJOR_RELEASE")

  # Clone D4J and checkout v2.0.0 tag
  echo "Clone Defects4J and init $D4J_VERSION ..."
  git clone "$D4J_URL" "$D4J_HOME" || failure "git clone D4J" "git clone failed to check out $D4J_URL to $D4J_HOME"
  cd "$D4J_HOME"
  git checkout "$D4J_VERSION"
  ./init.sh || failure "Init Defects4J" "script \"$D4J_HOME/init.sh\""
}

#
# Report a failure and exit the script with an error code
#
failure() {
  local process="$1"
  local more_info="$2"
  local verb="$3"
  if [[ -n $more_info ]]; then
    more_info=" $more_info"
  fi
  if [[ -z $verb ]]; then
    verb=" failed"
  else
    verb=" $verb"
  fi

  echo "$process$verb.$more_info Aborting."
  cd "$CWD"

  # Download and unzip Major
  echo "Download Major ..."
  wget "$MAJOR_URL" -P "$DEPS_DIR" || failure "Download Major" "wget failed to download $MAJOR_URL."
  (cd "$DEPS_DIR" && unzip "$MAJOR_RELEASE" && rm "$MAJOR_RELEASE")

  # Clone D4J and checkout v2.0.0 tag
  echo "Clone Defects4J and init $D4J_VERSION ..."
  git clone "$D4J_URL" "$D4J_HOME" || failure "git clone D4J" "git clone failed to check out $D4J_URL to $D4J_HOME"
  cd "$D4J_HOME"
  git checkout "$D4J_VERSION"
  ./init.sh || failure "Init Defects4J" "script \"$D4J_HOME/init.sh\""
}

#
# Report a failure and exit the script with an error code
#
failure() {
  local process="$1"
  local more_info="$2"
  local verb="$3"
  if [[ -n $more_info ]]; then
    more_info=" $more_info"
  fi
  if [[ -z $verb ]]; then
    verb=" failed"
  else
    verb=" $verb"
  fi

  echo "$process$verb.$more_info Aborting."
  cd "$CWD"
  exit 1
}

main
