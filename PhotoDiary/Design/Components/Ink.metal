#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// 刚写进去的一段字像墨水渗进纸里：按书写顺序（从上到下、从左到右，带一点不匀）一块块洇出来，
// 刚洇出来的地方笔画略粗、颜色略深（湿墨），随后收细到正常的字。InkIn.swift 用 layerEffect 调。

namespace {
    float inkHash(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    float inkNoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(inkHash(i), inkHash(i + float2(1, 0)), u.x),
                   mix(inkHash(i + float2(0, 1)), inkHash(i + float2(1, 1)), u.x), u.y);
    }
}

[[ stitchable ]] half4 inkIn(float2 position, SwiftUI::Layer layer, float progress, float2 size, float lineHeight) {
    // 书写顺序：第几行为主，行内从左到右；再加一点低频噪声，边缘不齐。
    float lines = max(size.y / max(lineHeight, 1.0), 1.0);
    float line = floor(position.y / max(lineHeight, 1.0));
    float order = (line + position.x / max(size.x, 1.0)) / lines;
    order = order * 0.8 + inkNoise(position / 14.0) * 0.2;

    // progress 走完时所有地方都已洇完。
    float p = progress * 1.25;
    float shown = smoothstep(order - 0.08, order + 0.04, p);
    // 洇出来之后还“湿”一会儿：笔画向外扩一点。
    float wet = 1.0 - smoothstep(order + 0.04, order + 0.3, p);

    half4 base = layer.sample(position);
    float r = 1.2 * wet;
    half4 spread = base;
    spread = max(spread, layer.sample(position + float2(r, 0)));
    spread = max(spread, layer.sample(position - float2(r, 0)));
    spread = max(spread, layer.sample(position + float2(0, r)));
    spread = max(spread, layer.sample(position - float2(0, r)));
    half4 ink = mix(base, spread, half(0.4 * wet));
    // 湿墨深一点。
    ink.rgb *= half(1.0 - 0.15 * wet);
    return ink * half(shown);
}
