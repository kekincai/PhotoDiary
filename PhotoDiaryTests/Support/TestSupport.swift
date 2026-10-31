import Foundation
import CoreLocation
@testable import PhotoDiary

/// 按坐标返回预设地名，并记下查询次数。
final class FakePlaceNamer: PlaceNaming {
    var results: [String: (name: String?, timeZone: String?)] = [:]
    private(set) var lookups = 0

    func set(_ name: String?, timeZone: String? = nil, latitude: Double, longitude: Double) {
        results[Self.key(latitude, longitude)] = (name, timeZone)
    }

    func place(for coordinate: CLLocationCoordinate2D) async -> (name: String?, timeZone: String?)? {
        lookups += 1
        return results[Self.key(coordinate.latitude, coordinate.longitude)]
    }

    private static func key(_ lat: Double, _ lon: Double) -> String { String(format: "%.2f,%.2f", lat, lon) }
}

/// 测试用的固定“现在”：2026-10-31 正午。
let fixedNow = Calendar.diary.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!

func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.diary.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

/// 每次一个新的空目录。
func temporaryDirectory() -> URL {
    URL.temporaryDirectory.appending(path: "PhotoDiaryTests-\(UUID().uuidString)")
}

/// 每次一个独立的 UserDefaults，测试并行时互不干扰。
func isolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "PhotoDiaryTests-\(UUID().uuidString)")!
}

/// 可以拨动的时钟，测试跨天。
final class TestClock {
    var now: Date
    init(_ now: Date = fixedNow) { self.now = now }
}

func makeStore(library: FakeLibrary, places: FakePlaceNamer = FakePlaceNamer(),
               directory: URL = temporaryDirectory(), defaults: UserDefaults = isolatedDefaults(),
               clock: TestClock = TestClock(), saveDelay: Duration = .zero) -> DiaryStore {
    DiaryStore(.init(library: library, index: IndexStore(directory: directory), placeNamer: places,
                     defaults: defaults, now: { clock.now }, saveDelay: saveDelay, changeDelay: .zero,
                     geocodeInterval: .zero))
}

/// 启动并等第一次同步结束。
func startedStore(_ library: FakeLibrary, places: FakePlaceNamer = FakePlaceNamer(),
                  directory: URL = temporaryDirectory(), defaults: UserDefaults = isolatedDefaults(),
                  clock: TestClock = TestClock()) async -> DiaryStore {
    let store = makeStore(library: library, places: places, directory: directory, defaults: defaults, clock: clock)
    await store.start()
    _ = await eventually { store.hasSynced && store.syncState == .idle }
    return store
}

/// 同步、保存都在后台任务里，等条件成立（最多 2 秒）。
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}
