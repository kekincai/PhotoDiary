# 缓存与测试改进计划

2026-10-31 调研结论 + 分阶段计划。先评审这份计划，再动代码。

## 现状

### 缓存分三层

| 层 | 现在的做法 | 文件 |
|---|---|---|
| 日记索引 | 整个 `IndexSnapshot`（条目 + change token + 地名/时区缓存 + 本 App 写过的）编码成一个 JSON，变化后防抖 1 秒整文件原子写入 `Application Support/diary-index.json` | `Library/IndexStore.swift`、`DiaryStore.scheduleSave` |
| 内存派生数据 | `entries` 每次赋值触发 `rebuildDerived()` 全量重算月份、日历、标签、地点、那年今日 | `DiaryStore.swift:306` |
| 图片 | `PHCachingImageManager` + `[String: PHAsset]` 字典；SwiftUI 视图按实际尺寸 `requestImage`，opportunistic 先低清后清晰 | `Library/AssetImages.swift`、`Design/Components.swift:5` |

### 测试

- 只有 `CaptionFormatTests` 一个套件，14 个用例，全部通过。覆盖说明格式解析、标签、过滤规则、`DiaryEntry` 编解码。
- 覆盖率报告显示 App 25.9%、`DiaryStore` 54%，但**这是假象**：测试宿主（`TEST_HOST`）启动了真 App，`store.start()` 对模拟器真实照片库跑了一遍全量扫描，代码被执行了但**没有任何断言**。
- 没有 UI 测试、集成测试、性能测试，也没有 CI。

## 发现的问题

### 正确性（应先修）

1. **`rebuildIndex()` 竞态**（`DiaryStore.swift:160`）：先 `cancel` 旧任务并把 `syncTask` 置 nil，再开新任务；旧任务被取消后仍会走到 `syncTask = nil; hasSynced = true`，把**新任务的引用清掉**。之后任何一次 `sync()` 都会再开一个并发同步。被取消的全量扫描还会对部分结果执行 `afterSync`（触发关键词改写）和 `scheduleSave`。
2. **测试会改模拟器照片库**：测试宿主启动即 `store.start()`，`afterSync` 可能调用 `reconcileKeywords` 真的改写照片关键词，并覆盖 `diary-index.json`。测试结果依赖模拟器里有什么照片。
3. **索引会被 iCloud 备份**：`Application Support` 默认参与备份。换机恢复后，旧设备的 `localIdentifier` 在新设备上不成立，启动时会先显示一批指向不存在照片的条目（空白缩略图），直到全量扫描完成。可重建的数据应设 `isExcludedFromBackup`。
4. **版本升级会丢地名缓存**：`currentVersion` 不匹配直接返回 nil，`placeCache`/`timeZoneCache` 一起丢掉。反向地理编码每次间隔 600ms，几千个地点要重查很久。地名缓存和索引生命周期不同，应拆成单独文件。
5. **`AssetImages.assets` 从不失效**：`forget(_:)` 没有任何调用方。照片被删除或修改后仍返回旧的 `PHAsset`。
6. **切到后台不落盘**：防抖 1 秒内被杀，最近解析出的地名丢失（token 和条目在同一快照里，所以不会不一致，只是白干）。

### 图片缓存（"缓存是个大问题"的主要来源）

1. **用了 `PHCachingImageManager` 却从没调用 `startCachingImages`**，等于普通 `PHImageManager`。Apple 的做法是滚动时对即将出现的照片预热、对离开的停止预热。
2. **请求尺寸不固定，缓存命中不了**：`AssetImage` 用 `onGeometryChange` 的实际尺寸作 `targetSize`，转场、弹簧动画、旋转期间尺寸连续变化，每变一次就取消重请求；而 PhotoKit 的缓存要求 `targetSize`、`contentMode`、`options` 完全一致才命中。
3. **没有解码后的内存缓存**：切标签页、来回滚动、列表↔日历切换都重新走 PhotoKit。缩略图应进 `NSCache`（按字节计 cost，系统内存紧张时自动清）。
4. **大图固定 3000×3000**（`PhotoViewer.swift:39`）：解码后约 36MB，连翻几张容易被系统杀。应先按屏幕像素请求，放大手势超过 1.5 倍再换高清。
5. `livePhoto` 用 `PHImageManager.default()` 且不可取消，离开页面后请求仍在跑；`playerItem` 同样。
6. 没有响应内存警告 / 进入后台（`stopCachingImagesForAllAssets`、清空 `NSCache`）。
7. iCloud 下载大图没有进度回调，网络慢时只是一片灰。

### 可测试性

`DiaryStore` 直接调用 `PHPhotoLibrary`、静态的 `LibraryScanner`/`IndexStore`（写死文件路径）、`UserDefaults.standard`（`CaptionFilter`）、`DayStamp.today`/`.now`、真实的 `MKReverseGeocodingRequest`。不加注入点，同步、派生数据、地名这些核心逻辑都没法写确定性的测试。

## 计划

按顺序做，每阶段一个提交，阶段内先写测试再修。

### 阶段 1：测试基础设施（不改行为）

- `PhotoDiaryApp`：检测到在单元测试宿主里运行（`XCTestConfigurationFilePath` 环境变量）时不调用 `store.start()`。
- 加注入点，默认值就是现在的实现，App 代码调用方式不变：
  - `PhotoLibraryClient` 协议：`fullScan`、`incremental(since:)`、`fetchEntries`、`write`、`reconcileKeywords`、`delete`。`LibraryScanner` 作为默认实现。
  - `IndexStore` 改成带 `directory: URL` 的值类型，测试用临时目录。
  - `PlaceNaming` 协议包住 `PlaceNamer`。
  - `DiaryStore` 接受 `now: () -> Date`，派生数据里的“今天”“本周”都从它算。
  - `CaptionFilter` 接受 `UserDefaults`（测试用独立 suite，避免 Swift Testing 并行时互相干扰）。
- 测试目录加 `Fakes/`：`FakeLibrary`（内存里的照片表 + 可控的 token 过期 / 扫描批次 / 写入记录）、`FakePlaceNamer`。

### 阶段 2：索引与同步——测试 + 修 bug

先写测试（预计 30 个左右），再修上面正确性 1、3、4、5、6：

- **启动**：有快照先显示快照条目，再走增量；无快照走全量；快照版本不符、文件损坏、文件不存在都回落全量。
- **全量扫描**：分批可见；完成后用新结果替换（被删的消失）；被取消时不替换、不改 token、不触发关键词改写。
- **增量**：更新 / 删除 / 说明被清空；坐标没变保留地名，坐标变了重新解析；token 过期回落全量。
- **并发**：扫描中再调 `sync()` 只合并成一次后续增量；`rebuildIndex()` 期间任意时刻只有一个同步在跑（竞态的回归测试）。
- **写入**：新写 / 追加 / 编辑 / 清空四种模式写出的说明和 `writtenInApp`；标签改名、合并只产生一次批量写入。
- **关键词**：只改写“说明里有标签或本 App 写过”且不一致的照片；Lightroom 导入的关键词不动。把 `applyKeywords` 的增删计算抽成纯函数单测。
- **派生数据**：月份分组、日历月份含本月、那年今日、本周写作、本月篇数、标签排序、地点排序、过滤规则隐藏、跨天回前台重算、拍摄地时区改变日期。
- **搜索 / 导出**：多标签 AND、日期范围、正文和地名全文、`frequentShortCaptions`、Markdown 导出顺序。
- **地名**：同一坐标只查一次、命中缓存不查、失败不重试、批量写回。
- **持久化**：往返一致；文件保护等级；排除备份属性；索引版本升级后地名缓存仍在（拆出 `place-cache.json`）；进入后台立即落盘。

修复要点：
- `sync()` 用代次计数（generation）判断任务是否已被替换，被替换的任务不再写任何状态。
- 索引目录设 `isExcludedFromBackup`；地名缓存独立成文件，不随索引版本作废。
- `scenePhase == .background` 时取消防抖立即保存，用 `beginBackgroundTask` 保证写完。
- `AssetImages` 在收到照片库变更时按 `PHChange.changeDetails` 失效对应的 `PHAsset`（或直接改用 `NSCache` 并在变更时清空）。

### 阶段 3：图片缓存

- **尺寸分档**：缩略图请求尺寸归到固定几档（例如网格格子、日历格子、列表卡片、那年今日小图各一档，按 `displayScale` 算像素）；`AssetImage` 只在跨档时重请求。
- **`ThumbnailCache`**：`NSCache<Key, UIImage>`，Key = (id, 档位, contentMode)，cost = 宽×高×4，`totalCostLimit` 约 80MB；只缓存非 degraded 的结果；命中时同步给图，不闪灰底。
- **预热**：网格、日历、列表在可见范围变化时（`onScrollGeometryChange` 或 cell `onAppear`/`onDisappear` 汇总成可见索引区间），对前后各一屏 `startCachingImages`，离开的 `stopCachingImages`。网格设 `allowsCachingHighQualityImages = false`。预热窗口计算写成纯函数单测。
- **大图**：先按屏幕像素请求，缩放超过 1.5 倍再请求原图尺寸；离开页面取消。分享导出不变。
- **Live Photo / 视频**：改用同一个 manager，返回可取消的请求，`onDisappear` 取消。
- **内存与后台**：收到内存警告清 `ThumbnailCache` 并 `stopCachingImagesForAllAssets`；进入后台同样处理。
- **iCloud 进度**：大图请求带 `progressHandler`，详情页显示细进度条。
- 测试：用 `ImageManaging` 协议包住 PhotoKit，验证 degraded→最终两次交付后结束、出错结束、流终止时取消请求、尺寸分档、缓存命中不再请求、内存警告清空。
- 用 Instruments（Allocations + Time Profiler）对比改前改后：快速滑过 500 张网格的峰值内存、掉帧；连续翻 10 张大图的峰值内存。数字记在本文件末尾。

### 阶段 4：真照片库集成测试 + UI 冒烟

- 新建测试计划 `Integration.xctestplan`（默认不跑）：用 `Tools/TestPhotos/fetch.sh` 导入的照片，`simctl privacy grant photos` 授权，验证写说明→读回、关键词与标签一致、模拟器外部改说明后增量能拿到、token 归档往返。
- 新建 `PhotoDiaryUITests`，启动参数 `-UITestFixture` 让 App 用 `FakeLibrary` 加载固定数据，不碰真照片库：日记列表显示、四种视图切换、打开详情、写日记保存、搜索、三种语言各启动一次。只做冒烟，不追求覆盖率。
- 加一个测试：解析 `Localizable.xcstrings`，断言每个键都有 zh-Hans / ja / en 且没有 `needs_review`。

### 阶段 5：性能基线

- 1 万、5 万条目下：`rebuildDerived()` 耗时、`IndexStore` 编码 / 解码耗时与文件大小、全量扫描批次合并耗时。
- 判断标准：主线程单次超过 16ms 就要优化（例如批次合并时不每批全量重算、改成增量合并）；索引编码超过 200ms 或文件超过 20MB 再考虑换 SQLite / SwiftData。**在数据证明需要之前不换存储格式。**
- `Tools/test.sh` 一条命令跑单元测试 + 覆盖率；之后需要的话再加 GitHub Actions（取决于托管 runner 是否有 Xcode 27）。

## 进度

### 2026-10-31：阶段 1 完成，加了日志框架

- 测试宿主不再读照片库（`PhotoDiaryApp.isHostingUnitTests`）。真实 `LibraryScanner` 的覆盖率从 12% 降到 2%，说明测试已经不碰模拟器照片了。
- 注入点：`PhotoLibraryClient` / `PhotoKitLibrary`、`IndexStore(directory:)`、`PlaceNaming`，都放在 `DiaryStore.Dependencies` 里（还包括 `now`、过滤规则用的 `defaults`、各种防抖时长）。App 里的调用方式不变。
- 测试替身：`PhotoDiaryTests/Support/FakeLibrary.swift`（内存照片库，带 change token、token 失效、外部修改通知、写入记录），`TestSupport.swift`（`FakePlaceNamer`、`makeStore`、`eventually`、临时目录、独立的 UserDefaults）。
- 测试从 14 个增加到 27 个（新增 `DiaryStoreTests` 7 个、`IndexStoreTests` 5 个、`LogTests` 1 个），连续跑 20 遍都通过。`DiaryStore` 的覆盖率 77%，现在都有断言。
- 日志：`App/Log.swift`，基于 `os.Logger`，按 app / sync / index / library / places / images 分类；`Log.signposter` 给全量读取、增量同步、索引读写、派生数据重算打了区间（在 Instruments 的 Points of Interest 里看）。原来 `try?` 吞掉的错误现在都会记下来。设置里新增“导出诊断日志”。说明正文一律不进日志。

日志已经看出来的两件事，留给后面的阶段：
- **缩略图尺寸抖动**：同一张图先按 1050×787、再按 1049×787 请求，第一次被取消（`PHPhotosErrorDomain 3072`）。这正是阶段 3 尺寸分档要解决的问题。
- **没有变化的增量同步也花了约 3 秒**（模拟器里，从读入索引到同步结束）。阶段 2 再查：是 `fetchPersistentChanges` 本身慢，还是被别的工作挡住了。

## 需要你决定的

1. **是否把 `Model/` + `Library/` 抽成本地 Swift Package**：好处是单元测试不需要宿主 App、能在 Mac 上秒跑；代价是改动大、访问控制要加 `public`。计划默认**不抽**，只加注入点。
2. **集成测试会改写模拟器照片库的说明和关键词**：建议只在专用模拟器（现在的“照片日记测试”）上跑。
3. **缩略图内存缓存上限**：默认 80MB，老机型上可以按 `ProcessInfo.physicalMemory` 调低。
