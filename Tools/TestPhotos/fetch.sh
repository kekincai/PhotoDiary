#!/bin/zsh
# 下载一组 Unsplash 照片（Unsplash License，可免费使用），写入拍摄日期、GPS 和日记说明，
# 然后导入到已启动的模拟器。用法：Tools/TestPhotos/fetch.sh [模拟器 UDID，默认 booted]
set -euo pipefail
here=${0:A:h}
device=${1:-booted}
work=$(mktemp -d)
trap 'rm -rf $work' EXIT
mkdir -p $work/raw $work/tagged

ids=(
  1790293840932-a568128dbb1f 1790419062406-60c1a07f3022 1790313157313-cbc2c66a61ab 1790523069334-8cc3d26605f7
  1790152892429-75b73b06d190 1790206473704-cce295ba55b1 1790019852739-349585111186 1788469961932-6e166d1bdd23
  1711043217102-b6aed9490982 1788695968738-3c2818047036 1788839253126-fdf0f7899405 1789248742478-2c946e9f661f
  1789493183153-283e69085d16 1790213936669-e17a3e0bd6ce 1790011990347-c59091f9437e 1789539382502-b49e96773a43
  1771930554980-8d7b70f4217d 1790068853401-d5cdbc6755e6 1790233337798-8982fd955b52 1790102097653-ae0a9921934b
  1787920990418-a4d135a2316a 1790202557957-2639ca84db66 1789020622122-8ebdb0d49a05 1789947998062-393d05531f04
)
i=0
for id in $ids; do
  curl -sfL -o $work/raw/u_$(printf %02d $i).jpg "https://images.unsplash.com/photo-$id?w=1600&q=80&fm=jpg"
  i=$((i + 1))
done

swiftc -O $here/tag.swift -o $work/tag
$work/tag $here/spec.json $work/raw $work/tagged
xcrun simctl addmedia $device $work/tagged/*.jpg
echo "已导入 $(ls $work/tagged | wc -l | tr -d ' ') 张照片到模拟器 $device"
