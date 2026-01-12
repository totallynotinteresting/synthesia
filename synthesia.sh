#!/bin/bash
cd "$(dirname "$0")"
DYLD_INSERT_LIBRARIES=hook.dylib ./Synthesia.o