#!/bin/bash

SYNTHESIA_MACOS_PATH="/Applications/Synthesia.app/Contents/MacOS"
REPO_URL="https://github.com/totallynotinteresting/synthesia.git"
RAW_URL="https://raw.githubusercontent.com/totallynotinteresting/synthesia/main"
RELEASE_URL="https://github.com/totallynotinteresting/synthesia/releases/latest/download/hook.dylib"

if [ ! -d "$SYNTHESIA_MACOS_PATH" ]; then
    echo "Synthesia.app was not found at $SYNTHESIA_MACOS_PATH"
    echo "please make sure that Synthesia.app is in /Applications/"
    exit 1
fi

cd "$SYNTHESIA_MACOS_PATH" || exit 1
echo "went into $(pwd)"

if git clone "$REPO_URL" synthesia_patch; then
    echo "cloned repo to $(pwd)"
    cd synthesia_patch || exit 1
    echo "building hook.dylib because this contains the logic"
    if clang -dynamiclib -framework Foundation -framework AppKit -o hook.dylib hook.m; then
        echo "Build successful."
    else
        echo "either somethings gone wrong or you dont have clang installed, so we're gonna download it from the gh directly"
        curl -L -o hook.dylib "$RELEASE_URL"
    fi
else
    mkdir -p synthesia_patch
    cd synthesia_patch || exit 1    
    curl -L -o synthesia.sh "$RAW_URL/synthesia.sh"
    curl -L -o hook.dylib "$RELEASE_URL"
fi

# ok well if it doesnt exist, you've clearly done something wrong
if [ ! -f hook.dylib ]; then
    echo "how the hell is hook.dylib not there?"
    cd ..
    rm -rf synthesia_patch
    exit 1
fi

echo "signing it because macos is specal like that"
codesign -f -s - hook.dylib

echo "blah blah moving it to where it belongs"
mv hook.dylib ..
mv ../Synthesia ../Synthesia.o
echo "gotta resign synthesia as well because something about macos doing hardened runtime"
codesign --remove-signature ../Synthesia.o
codesign --force --deep --sign - ../Synthesia.o
mv ./synthesia.sh ../Synthesia
chmod +x ../Synthesia

cd ..
rm -rf synthesia_patch

echo "uh sure try it out"
