python3 build-system/Make/Make.py \
    --overrideXcodeVersion \
    --cacheDir="$HOME/telegram-bazel-cache" \
    build \
    --configurationPath="$HOME/telegram-configuration" \
    --buildNumber=100001 \
    --configuration=release_universal

