#!/bin/zsh
# 自动测试用的照片：不联网，6 张纯色图，3 张带日记说明（标签、地点、“去年今天”），3 张空白。
# 用法：Tools/TestPhotos/seed.sh <模拟器 UDID>
set -euo pipefail
here=${0:A:h}
device=$1
work=$(mktemp -d)
mkdir -p $work/raw $work/tagged
swiftc -O $here/blank.swift -o $work/blank
swiftc -O $here/tag.swift -o $work/tag
$work/blank $work/raw t_00.jpg t_01.jpg t_02.jpg t_03.jpg t_04.jpg t_05.jpg
$work/tag $here/ui-spec.json $work/raw $work/tagged
xcrun simctl addmedia $device $work/tagged/*.jpg
rm -rf $work
