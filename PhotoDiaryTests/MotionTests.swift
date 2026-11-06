import Testing
import CoreGraphics
@testable import PhotoDiary

/// 跟手动效的判断：松手按速度推算落点，往回拉就取消。
@MainActor
struct MotionTests {
    @Test func smallSlowDragSpringsBack() {
        #expect(!DragToDismiss.shouldDismiss(translation: 60, velocity: 0, height: 800))
    }

    @Test func longDragDismisses() {
        #expect(DragToDismiss.shouldDismiss(translation: 300, velocity: 0, height: 800))
    }

    /// 拖得不远但甩得快：按惯性落点关闭。
    @Test func flickDismisses() {
        #expect(DragToDismiss.shouldDismiss(translation: 40, velocity: 1200, height: 800))
    }

    /// 拖得很远，但松手时正在往回拉：取消。
    @Test func draggingBackUpCancels() {
        #expect(!DragToDismiss.shouldDismiss(translation: 300, velocity: -400, height: 800))
    }

    @Test func photoShrinksToAtMostEightyPercent() {
        #expect(DragToDismiss.scale(DragToDismiss.progress(0, height: 800)) == 1)
        #expect(DragToDismiss.scale(DragToDismiss.progress(10_000, height: 800)) == 0.8)
    }

    @Test func rubberBandResistsAndNeverExceedsDimension() {
        #expect(DragToDismiss.rubberBand(100) < 100)
        #expect(DragToDismiss.rubberBand(100_000) < 400)
        #expect(DragToDismiss.rubberBand(0) == 0)
    }
}
