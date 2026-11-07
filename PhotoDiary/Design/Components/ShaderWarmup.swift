import SwiftUI

/// 着色器第一次用时要现编译，会卡一帧。在用到之前（进入那一页时）先在后台编好。
enum ShaderWarmup {
    /// 一年回顾的显影。
    static func developing() async {
        try? await ShaderLibrary.develop(.float(0), .float2(CGSize(width: 1, height: 1)), .color(.white), .float(0)).compile(as: .colorEffect)
    }

    /// 详情页上新追加的一段洇出来。
    static func ink() async {
        try? await ShaderLibrary.inkIn(.float(0), .float2(CGSize(width: 1, height: 1)), .float(1)).compile(as: .layerEffect)
    }

    /// 编辑器的纸纹。
    static func paper() async {
        try? await ShaderLibrary.paperGrain(.float(0)).compile(as: .colorEffect)
    }
}
