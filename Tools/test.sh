#!/bin/zsh
# 全部测试：单元测试、真实照片库测试、界面测试，iPhone 和 Watch 都编译一遍。
# 在一台专用的模拟器“照片日记 自动测试”上跑（没有就建一台），不碰平时用来看效果的模拟器。
# 每次先抹掉它、重新导入种子照片：测试会删照片、造照片、改设置，种子照片的日期也按当天算，
# 不抹掉的话跑过几次以后就不是同一个起点了。
#
#   Tools/test.sh              全部
#   Tools/test.sh unit         只跑单元测试和真实照片库测试
#   Tools/test.sh ui           只跑界面测试
#   Tools/test.sh --keep ...   不抹掉模拟器，接着上次的照片库跑（调试单个测试时省时间）
set -euo pipefail
cd "${0:A:h}/.."

NAME="照片日记 自动测试"
BUNDLE=com.kejincai.photodiary
DERIVED=build/test
keep=0
if [[ "${1:-}" == "--keep" ]]; then keep=1; shift; fi
if [[ "${1:-}" == "--fresh" ]]; then shift; fi  # 旧写法：现在默认就是抹掉重来
what="${1:-all}"

device=$(xcrun simctl list devices | grep -F "$NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [[ -z "$device" ]]; then
    # 最新的 iOS 运行时，和它支持的最后一种 iPhone（列表按年代排，最后一个最新；按名字取会取到 iPhone 6s 这种老机型）。
    read -r runtime type < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
r = runtimes[-1]
phones = [d for d in r["supportedDeviceTypes"] if d["productFamily"] == "iPhone"]
print(r["identifier"], phones[-1]["identifier"])')
    device=$(xcrun simctl create "$NAME" "$type" "$runtime")
    keep=0
fi
if (( ! keep )) || [[ ! -f "$DERIVED/.seeded-$device" ]]; then
    xcrun simctl shutdown "$device" 2>/dev/null || true
    xcrun simctl erase "$device"
    rm -f "$DERIVED"/.seeded-*
fi
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null

# 界面测试用的照片（带说明的、空白的），抹掉后导入一次。标记只给 --keep 用：没有标记就当没导入过，抹掉重来。
if [[ ! -f "$DERIVED/.seeded-$device" ]]; then
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
