#!/bin/zsh
# 全部测试：单元测试、真实照片库测试、界面测试，iPhone 和 Watch 都编译一遍。
# 在一台专用的模拟器“照片日记 自动测试”上跑（没有就建一台），不碰平时用来看效果的模拟器。
#
#   Tools/test.sh              全部
#   Tools/test.sh unit         只跑单元测试和真实照片库测试
#   Tools/test.sh ui           只跑界面测试
#   Tools/test.sh --fresh ...  先抹掉测试模拟器（照片库清空，重新授权）
set -euo pipefail
cd "${0:A:h}/.."

NAME="照片日记 自动测试"
BUNDLE=com.kejincai.photodiary
DERIVED=build/test
fresh=0
if [[ "${1:-}" == "--fresh" ]]; then fresh=1; shift; fi
what="${1:-all}"

device=$(xcrun simctl list devices | grep -F "$NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [[ -z "$device" ]]; then
    runtime=$(xcrun simctl list runtimes | grep -E '^iOS ' | grep -v unavailable | tail -1 | sed -E 's/.* - (com\.apple[^ ]+).*/\1/')
    type=$(xcrun simctl list devicetypes | grep -E '^iPhone' | tail -1 | sed -E 's/.*\((com\.apple[^)]+)\).*/\1/')
    device=$(xcrun simctl create "$NAME" "$type" "$runtime")
    fresh=1
fi
if (( fresh )); then
    xcrun simctl shutdown "$device" 2>/dev/null || true
    xcrun simctl erase "$device"
fi
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null

# 界面测试用的照片（带说明的、空白的）只在抹掉后导入一次。
if (( fresh )) || [[ ! -f "$DERIVED/.seeded-$device" ]]; then
    Tools/TestPhotos/seed.sh "$device"
    mkdir -p "$DERIVED" && touch "$DERIVED/.seeded-$device"
fi
xcrun simctl privacy "$device" grant photos "$BUNDLE"

echo "▸ 编译 Watch App"
xcodebuild -scheme PhotoDiaryWatch -destination 'generic/platform=watchOS Simulator' -derivedDataPath "$DERIVED" build -quiet

case "$what" in
    unit) only=(-only-testing:PhotoDiaryTests) ;;
    ui) only=(-only-testing:PhotoDiaryUITests) ;;
    *) only=() ;;
esac

echo "▸ 测试（$NAME，$device）"
log="$DERIVED/test-$(date +%Y%m%d-%H%M%S).log"
TEST_RUNNER_PHOTODIARY_PHOTOKIT_TESTS=1 xcodebuild test -scheme PhotoDiary \
    -destination "id=$device" -derivedDataPath "$DERIVED" \
    -resultBundlePath "${log%.log}.xcresult" \
    "${only[@]}" > "$log" 2>&1 && result=0 || result=$?
# 单元测试（Swift Testing）一行一个 ✔/✘，界面测试（XCTest）一行一个 Test Case；CoreData 的噪音来自故意损坏数据库的测试。
{ grep -v CoreData "$log" || true; } | grep -E '✘|Test run with|error: -|Test Case .*(passed|failed)|\*\* TEST' \
    | sed -E "s#^$PWD/##; s/^Test Case '-\[PhotoDiaryUITests\.([A-Za-z]+) ([A-Za-z]+)\]'/  \1.\2/" || true
echo "完整日志：$log"
exit $result
