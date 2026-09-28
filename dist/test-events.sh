#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/event-tests
clang -std=c11 -Wall -Wextra -Werror \
  -fsanitize=undefined,float-cast-overflow -fno-sanitize-recover=all \
  -I Tests/ISSInternalTestSupport/include \
  Sources/ISS/event_serialize.c Sources/ISS/gesture_event.c \
  Tests/ISSInternalTestSupport/EventAssertions.c Tests/Standalone/main.c \
  -framework ApplicationServices -framework CoreFoundation \
  -o build/event-tests/events
build/event-tests/events
