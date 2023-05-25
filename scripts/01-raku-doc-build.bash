#!/usr/bin/env bash

# 01-raku-doc-build.bash is a bash script that builds raku doc website given
# TIMTOADY_RAKU_DOC_CHECKOUT.

set -e

set -o errexit
set -o nounset
# SCRIPT_PATH="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P)"
function die {
    echo "ERROR $? IN ${BASH_SOURCE[0]} AT LINE ${BASH_LINENO[0]}" 1>&2
    exit 1
}
trap die ERR

TEMP_DIR="$(mktemp -d)"
DOC_SRC="https://github.com/andinus/doc"
OUTPUT_DIR="/var/www/unfla.me.oxygen.raku-doc.*"

function cleanup {
    printf '\n=> %s %s\n' "$(date)" "cleaning up."
    rm -frv "$TEMP_DIR"
}
trap cleanup EXIT

printf '\n=> %s %s\n' "$(date)" "git --version."
git --version
printf '\n=> %s %s\n' "$(date)" "raku --version."
raku --version
printf '\n=> %s %s\n' "$(date)" "zef --version."
zef --version

if [ ! -d "$OUTPUT_DIR" ]; then
    printf '\n=> %s %s\n' "$(date)" "output directory does not exist: $OUTPUT_DIR" 1>&2
    exit 1
fi

if [ -z "$TIMTOADY_RAKU_DOC_CHECKOUT" ]; then
    printf '\n=> %s %s\n' "$(date)" "TIMTOADY_RAKU_DOC_CHECKOUT was not set." 1>&2
    exit 1
fi

if [ -d "$OUTPUT_DIR/$TIMTOADY_RAKU_DOC_CHECKOUT" ]; then
    printf '\n=> %s %s\n' "$(date)" "build output already exists: $OUTPUT_DIR/$TIMTOADY_RAKU_DOC_CHECKOUT"
    exit 0
fi


cd "$TEMP_DIR"

# get the latest builder.
printf '=> %s %s\n' "$(date)" "cloning latest builder."
git clone https://github.com/Raku/doc-website doc-website/
cd "$TEMP_DIR/doc-website"

# configure builder to not clone documentation source.
printf '\n=> %s %s\n' "$(date)" "configuring builder."

sed -i 's/source-refresh<git -C local_raku_docs\/ pull>/source-refresh()/g' config.raku
sed -i \
    's/source-obtain<git clone https\:\/\/github.com\/Raku\/doc.git local_raku_docs\/>/source-obtain()/g' \
    config.raku

cat config.raku

printf '\n=> %s %s\n' "$(date)" "fetching dependencies."

# fetch dependencies.
zef install . --deps-only --/test --exclude="dot"

# get documentation source.
printf '\n=> %s %s\n' "$(date)" "cloning documentation source."
git clone "$DOC_SRC" local_raku_docs/

# checkout to desired build of documentation.
printf '\n=> %s %s\n' "$(date)" "checkout to desired build: $TIMTOADY_RAKU_DOC_CHECKOUT."
cd local_raku_docs
git checkout "$TIMTOADY_RAKU_DOC_CHECKOUT"
cd ../

printf '\n=> %s %s\n' "$(date)" "building documentation."
bin_files/build-site --no-status --without-completion
printf '\n=> %s %s\n' "$(date)" "build complete."

printf '\n=> %s %s\n' "$(date)" "deploying build."
mkdir "$OUTPUT_DIR/$TIMTOADY_RAKU_DOC_CHECKOUT/"
cp -vr rendered_html/* "$OUTPUT_DIR/$TIMTOADY_RAKU_DOC_CHECKOUT/"

cd "$OUTPUT_DIR/$TIMTOADY_RAKU_DOC_CHECKOUT/"
find . -type d -exec chmod 755 {} \; ; find . -type f -exec chmod 644 {} \; ;
printf '\n=> %s %s\n' "$(date)" "deployed."
