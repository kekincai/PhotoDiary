#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// 纸的纤维颗粒：按屏幕上的点算，不是平铺一张小图，没有重复的格子，放多大都一样细。
// 两层：细颗粒（每个像素随机）和顺着一个方向拉长的纤维（低频噪声在一个方向上拉伸）。

namespace {
    float paperHash(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    float paperNoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(paperHash(i), paperHash(i + float2(1, 0)), u.x),
                   mix(paperHash(i + float2(0, 1)), paperHash(i + float2(1, 1)), u.x), u.y);
    }
}

[[ stitchable ]] half4 paperGrain(float2 position, half4 color, float strength) {
    float fine = paperHash(floor(position)) - 0.5;
    float fiber = paperNoise(position * float2(0.9, 0.12)) - 0.5;
    float g = (fine * 0.7 + fiber * 0.3) * strength;
    return half4(color.rgb + half3(g) * color.a, color.a);
}
