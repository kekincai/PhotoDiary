#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// 拍立得显影，逐像素算（DevelopingPhoto.swift 用 colorEffect 调）。
// 每个像素按自己的亮度决定什么时候显出来：暗部先浮出来，亮部最后褪去乳白；
// 药水铺得不匀，整张上有一团团先后；刚出来时颜色淡、反差低、偏暖，带一点颗粒，显完全部消失。

namespace {
    float hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    // 平滑的值噪声，0…1。
    float valueNoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        float a = hash(i);
        float b = hash(i + float2(1, 0));
        float c = hash(i + float2(0, 1));
        float d = hash(i + float2(1, 1));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }
}

[[ stitchable ]] half4 develop(float2 position, half4 color, float progress, float2 size, half4 milk, float seed) {
    float3 rgb = float3(color.rgb);
    float p = clamp(progress, 0.0, 1.0);

    // 药水的斑：两层低频噪声，按照片短边缩放，横竖图一样大小。
    float2 uv = position / max(min(size.x, size.y), 1.0);
    float blotch = valueNoise(uv * 3.0 + seed) * 0.65 + valueNoise(uv * 7.0 - seed) * 0.35;

    // 这个像素显影的起点：越亮越晚，斑块再错开一点。
    float lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    float start = 0.38 * lum + 0.16 * blotch;
    float local = smoothstep(start, start + 0.55, p);

    // 颜色和反差整张一起慢慢到位。
    float saturation = 0.1 + 0.9 * smoothstep(0.35, 1.0, p);
    float contrast = 0.55 + 0.45 * smoothstep(0.2, 0.95, p);
    float3 gray = float3(lum);
    float3 developed = mix(gray, rgb, saturation);
    developed = (developed - 0.5) * contrast + 0.5;
    // 刚浮出来时偏暖、偏青灰。
    developed *= float3(1.0, 0.95 + 0.05 * p, 0.86 + 0.14 * p);

    float3 result = mix(float3(milk.rgb), developed, local);

    // 颗粒：显影越早越明显，完成时没有。
    float grain = (hash(position + seed * 17.0) - 0.5) * 0.06 * (1.0 - p);
    result = clamp(result + grain, 0.0, 1.0);

    return half4(half3(result), 1.0h) * color.a;
}
