import Foundation
import AppKit
import Photos
import CryptoKit

struct Manifest: Decodable {
    let version: Int
    let operations: [Operation]
}

struct Operation: Decodable {
    let action: String
    let album: String?
    let start: String?
    let end: String?
    let outputDir: String?
    let livePhotoExport: String?
    let expectedAssets: Int?
    let expectedUnfavorite: Int?
    let expectedFavorite: Int?
    let allowAlbumOutside: Bool?
    let allowDeleteFavorites: Bool?
    let containerAlbum: String?
    let sourceAlbums: [String]?
    let excludeAlbums: [String]?
    let reuseAlbums: [String]?

    enum CodingKeys: String, CodingKey {
        case action, album, start, end
        case outputDir = "output_dir"
        case livePhotoExport = "live_photo_export"
        case expectedAssets = "expected_assets"
        case expectedUnfavorite = "expected_unfavorite"
        case expectedFavorite = "expected_favorite"
        case allowAlbumOutside = "allow_album_outside"
        case allowDeleteFavorites = "allow_delete_favorites"
        case containerAlbum = "container_album"
        case sourceAlbums = "source_albums"
        case excludeAlbums = "exclude_albums"
        case reuseAlbums = "reuse_albums"
    }
}

struct AssetStats {
    let assets: Int
    let images: Int
    let videos: Int
    let live: Int
    let favorites: Int
    let gps: Int
    let firstDate: String
    let lastDate: String
    let days: [String: Int]

    var json: [String: Any] {
        [
            "assets": assets,
            "images": images,
            "videos": videos,
            "live": live,
            "favorites": favorites,
            "unfavorite": assets - favorites,
            "gps": gps,
            "first_date": firstDate,
            "last_date": lastDate,
            "days": days,
        ]
    }
}

struct PreparedOperation {
    let index: Int
    let operation: Operation
    let album: PHAssetCollection?
    let assets: [PHAsset]
    let albumAssets: [PHAsset]
    let deleteTargets: [PHAsset]
    let albumOutside: Int
    let albumMissing: Int
}

struct AlbumAssetIndex {
    let title: String
    let identifier: String
    let assetIDs: Set<String>
    let totalAssets: Int
}

struct ClusterAlbumOverlap {
    let album: AlbumAssetIndex
    let matchedAssets: Int
}

let supportedActions: Set<String> = [
    "archive_album",
    "archive_favorites_album",
    "archive_unfavorites_album",
    "archive_date_range",
    "create_album_from_date_range",
    "create_remainder_album",
    "merge_albums_keep_assets",
    "move_favorites_to_album_delete_unfavorites_and_source",
    "delete_album_assets_and_album",
    "delete_album_assets_keep_album",
    "delete_unfavorite_assets_keep_album",
    "delete_unfavorite_assets_and_album",
    "delete_favorite_assets_keep_album",
    "delete_favorite_assets_and_album",
    "delete_album_keep_assets",
    "delete_album_if_contained",
]

let archiveActions: Set<String> = [
    "archive_album",
    "archive_favorites_album",
    "archive_unfavorites_album",
    "archive_date_range",
]

let supportedLivePhotoExportModes: Set<String> = ["full_pair", "still_only"]

let destructiveActions: Set<String> = [
    "delete_album_assets_and_album",
    "delete_album_assets_keep_album",
    "delete_unfavorite_assets_keep_album",
    "delete_unfavorite_assets_and_album",
    "delete_favorite_assets_keep_album",
    "delete_favorite_assets_and_album",
    "delete_album_keep_assets",
    "delete_album_if_contained",
]

let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

func emit(_ type: String, _ fields: [String: Any] = [:]) {
    var payload = fields
    payload["type"] = type
    do {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        fflush(stdout)
    } catch {
        fputs("{\"type\":\"error\",\"code\":\"JSON_OUTPUT_ERROR\"}\n", stderr)
        fflush(stderr)
    }
}

func fail(_ code: String, _ message: String, _ context: [String: Any] = [:], exitCode: Int32 = 2) -> Never {
    var fields = context
    fields["code"] = code
    fields["message"] = message
    emit("error", fields)
    exit(exitCode)
}

func argumentValues(_ name: String) -> [String] {
    let args = CommandLine.arguments
    var result: [String] = []
    var index = 0
    while index < args.count {
        if args[index] == name, index + 1 < args.count {
            result.append(args[index + 1])
            index += 2
        } else {
            index += 1
        }
    }
    return result
}

func argumentValue(_ name: String) -> String? {
    argumentValues(name).last
}

func hasArgument(_ name: String) -> Bool {
    CommandLine.arguments.contains(name)
}

func parseDate(_ text: String, field: String) -> Date {
    if text.count == 10, let date = dayFormatter.date(from: text) {
        return date
    }
    let simple = ISO8601DateFormatter()
    simple.formatOptions = [.withInternetDateTime]
    if let date = isoFormatter.date(from: text) ?? simple.date(from: text) {
        return date
    }
    fail("DATE_ERROR", "Invalid date", ["field": field, "value": text])
}

func iso(_ date: Date?) -> String {
    guard let date else { return "" }
    return isoFormatter.string(from: date)
}

func assetArray(_ fetch: PHFetchResult<PHAsset>) -> [PHAsset] {
    var assets: [PHAsset] = []
    assets.reserveCapacity(fetch.count)
    fetch.enumerateObjects { asset, _, _ in assets.append(asset) }
    return assets
}

func albumFetch(_ title: String) -> PHFetchResult<PHAssetCollection> {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "localizedTitle == %@", title)
    return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
}

func exactAlbum(_ title: String, required: Bool = true) -> PHAssetCollection? {
    let albums = albumFetch(title)
    if albums.count > 1 {
        fail("DUPLICATE_ALBUM", "Exact album title is not unique", ["album": title, "found": albums.count])
    }
    if albums.count == 0 {
        if required {
            fail("ALBUM_NOT_FOUND", "Album was not found", ["album": title])
        }
        return nil
    }
    return albums.firstObject
}

func stats(_ assets: [PHAsset]) -> AssetStats {
    var images = 0
    var videos = 0
    var live = 0
    var favorites = 0
    var gps = 0
    var dates: [Date] = []
    var days: [String: Int] = [:]
    for asset in assets {
        if asset.mediaType == .image { images += 1 }
        if asset.mediaType == .video { videos += 1 }
        if asset.mediaSubtypes.contains(.photoLive) { live += 1 }
        if asset.isFavorite { favorites += 1 }
        if asset.location != nil { gps += 1 }
        if let date = asset.creationDate {
            dates.append(date)
            days[dayFormatter.string(from: date), default: 0] += 1
        }
    }
    let sortedDates = dates.sorted()
    return AssetStats(
        assets: assets.count,
        images: images,
        videos: videos,
        live: live,
        favorites: favorites,
        gps: gps,
        firstDate: iso(sortedDates.first),
        lastDate: iso(sortedDates.last),
        days: days
    )
}

func fetchDateRange(start: Date, end: Date) -> [PHAsset] {
    guard start < end else {
        fail("DATE_RANGE_ERROR", "start must be before end")
    }
    let options = PHFetchOptions()
    options.predicate = NSPredicate(
        format: "creationDate >= %@ AND creationDate < %@",
        start as NSDate,
        end as NSDate
    )
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    return assetArray(PHAsset.fetchAssets(with: options))
}

func originalResources(for asset: PHAsset, liveMode: String) -> [(resource: PHAssetResource, role: String)]? {
    let resources = PHAssetResource.assetResources(for: asset)
    if asset.mediaType == .video {
        guard let video = resources.first(where: { $0.type == .video })
                ?? resources.first(where: { $0.type == .fullSizeVideo }) else {
            return nil
        }
        return [(video, "video")]
    }
    guard let still = resources.first(where: { $0.type == .photo })
        ?? resources.first(where: { $0.type == .fullSizePhoto })
        ?? resources.first(where: { $0.type == .alternatePhoto }) else {
        return nil
    }
    guard asset.mediaSubtypes.contains(.photoLive), liveMode == "full_pair" else {
        return [(still, asset.mediaSubtypes.contains(.photoLive) ? "live_still" : "photo")]
    }
    guard let motion = resources.first(where: { $0.type == .pairedVideo })
        ?? resources.first(where: { $0.type == .fullSizePairedVideo }) else {
        return nil
    }
    return [(still, "live_still"), (motion, "live_motion")]
}

func safeFilename(_ original: String, asset: PHAsset, used: inout Set<String>) -> String {
    let clean = original.replacingOccurrences(of: "/", with: "_")
    let url = URL(fileURLWithPath: clean)
    let stem = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    var candidate = clean
    if used.contains(candidate.lowercased()) {
        let token = asset.localIdentifier
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "-", with: "")
        candidate = ext.isEmpty ? "\(stem)__\(token.prefix(10))" : "\(stem)__\(token.prefix(10)).\(ext)"
    }
    var suffix = 2
    while used.contains(candidate.lowercased()) {
        candidate = ext.isEmpty ? "\(stem)__\(suffix)" : "\(stem)__\(suffix).\(ext)"
        suffix += 1
    }
    used.insert(candidate.lowercased())
    return candidate
}

func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while true {
        let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
        if data.isEmpty { break }
        digest.update(data: data)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
}

func validateOutputDirectory(_ path: String) {
    guard path.hasPrefix("/") else {
        fail("OUTPUT_PATH_ERROR", "output_dir must be absolute", ["output_dir": path])
    }
    let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    let forbidden: Set<String> = ["/", "/Users", "/Volumes", "/tmp"]
    guard !forbidden.contains(url.path) else {
        fail("OUTPUT_PATH_ERROR", "output_dir is too broad", ["output_dir": url.path])
    }
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
        guard isDirectory.boolValue else {
            fail("OUTPUT_PATH_ERROR", "output_dir is not a directory", ["output_dir": url.path])
        }
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
            guard contents.isEmpty else {
                fail("OUTPUT_NOT_EMPTY", "output_dir must be empty", ["output_dir": url.path, "entries": contents.count])
            }
        } catch {
            fail("OUTPUT_PATH_ERROR", error.localizedDescription, ["output_dir": url.path])
        }
    }
}

func validateManifestKeys(_ data: Data) {
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        fail("MANIFEST_JSON_ERROR", error.localizedDescription)
    }
    guard let root = object as? [String: Any] else {
        fail("MANIFEST_SCHEMA_ERROR", "Manifest root must be an object")
    }
    let allowedRoot: Set<String> = ["version", "operations"]
    let unknownRoot = Set(root.keys).subtracting(allowedRoot)
    guard unknownRoot.isEmpty else {
        fail("MANIFEST_SCHEMA_ERROR", "Unknown manifest fields", ["fields": Array(unknownRoot).sorted()])
    }
    guard let operations = root["operations"] as? [[String: Any]] else {
        fail("MANIFEST_SCHEMA_ERROR", "operations must be an array of objects")
    }
    let allowedOperation: Set<String> = [
        "action", "album", "start", "end", "output_dir", "live_photo_export", "expected_assets",
        "expected_unfavorite", "expected_favorite", "allow_album_outside", "allow_delete_favorites",
        "container_album", "source_albums", "exclude_albums", "reuse_albums",
    ]
    for (index, operation) in operations.enumerated() {
        let unknown = Set(operation.keys).subtracting(allowedOperation)
        guard unknown.isEmpty else {
            fail(
                "MANIFEST_SCHEMA_ERROR",
                "Unknown operation fields",
                ["index": index + 1, "fields": Array(unknown).sorted()]
            )
        }
    }
}

func loadManifest(_ path: String) -> Manifest {
    let data: Data
    do {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        fail("MANIFEST_READ_ERROR", error.localizedDescription, ["path": path])
    }
    validateManifestKeys(data)
    do {
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.version == 1 else {
            fail("MANIFEST_VERSION_ERROR", "Only version 1 is supported", ["version": manifest.version])
        }
        guard !manifest.operations.isEmpty else {
            fail("MANIFEST_SCHEMA_ERROR", "operations must not be empty")
        }
        for (offset, operation) in manifest.operations.enumerated() {
            let index = offset + 1
            guard supportedActions.contains(operation.action) else {
                fail("UNKNOWN_ACTION", "Unsupported action", ["index": index, "action": operation.action])
            }
            if archiveActions.contains(operation.action) {
                let liveMode = operation.livePhotoExport ?? "full_pair"
                guard supportedLivePhotoExportModes.contains(liveMode) else {
                    fail(
                        "MANIFEST_SCHEMA_ERROR",
                        "live_photo_export must be full_pair or still_only",
                        ["index": index, "value": liveMode]
                    )
                }
            } else if operation.livePhotoExport != nil {
                fail(
                    "MANIFEST_SCHEMA_ERROR",
                    "live_photo_export is allowed only for archive actions",
                    ["index": index, "action": operation.action]
                )
            }
        }
        return manifest
    } catch {
        fail("MANIFEST_SCHEMA_ERROR", error.localizedDescription)
    }
}

func requireAlbumTitle(_ operation: Operation, index: Int) -> String {
    guard let title = operation.album, !title.isEmpty else {
        fail("MANIFEST_SCHEMA_ERROR", "album is required", ["index": index])
    }
    return title
}

func checkExpected(_ operation: Operation, actual: Int, index: Int, apply: Bool) {
    if let expected = operation.expectedAssets {
        guard expected == actual else {
            fail(
                "ASSET_COUNT_CHANGED",
                "Asset count does not match expected_assets",
                ["index": index, "album": operation.album ?? "", "expected": expected, "actual": actual]
            )
        }
    } else if apply {
        fail("EXPECTED_COUNT_REQUIRED", "expected_assets is required for --apply", ["index": index])
    }
}

func prepare(_ manifest: Manifest, apply: Bool) -> [PreparedOperation] {
    var prepared: [PreparedOperation] = []
    var destructiveAlbums = Set<String>()
    var outputPaths = Set<String>()
    var plannedRangeSelections: [String: [PHAsset]] = [:]
    var plannedCreationAlbums = Set<String>()

    for (offset, operation) in manifest.operations.enumerated()
    where operation.action == "archive_date_range"
            || operation.action == "create_album_from_date_range"
            || operation.action == "create_remainder_album"
            || operation.action == "merge_albums_keep_assets" {
        let title = requireAlbumTitle(operation, index: offset + 1)
        guard plannedCreationAlbums.insert(title).inserted else {
            fail("CONFLICTING_OPERATIONS", "Only one album-creation operation per title is allowed", ["album": title])
        }
    }

    for (offset, operation) in manifest.operations.enumerated()
    where operation.action == "archive_date_range" || operation.action == "create_album_from_date_range" {
        let index = offset + 1
        let title = requireAlbumTitle(operation, index: index)
        guard plannedRangeSelections[title] == nil else {
            fail("CONFLICTING_OPERATIONS", "Only one planned date-range selection per album is allowed", ["album": title])
        }
        guard let startText = operation.start, let endText = operation.end else {
            fail("MANIFEST_SCHEMA_ERROR", "start and end are required", ["index": index])
        }
        plannedRangeSelections[title] = fetchDateRange(
            start: parseDate(startText, field: "start"),
            end: parseDate(endText, field: "end")
        )
    }

    for (offset, operation) in manifest.operations.enumerated() {
        let index = offset + 1
        guard supportedActions.contains(operation.action) else {
            fail("UNKNOWN_ACTION", "Unsupported action", ["index": index, "action": operation.action])
        }
        let title = requireAlbumTitle(operation, index: index)

        if destructiveActions.contains(operation.action)
                || operation.action == "move_favorites_to_album_delete_unfavorites_and_source" {
            guard !plannedCreationAlbums.contains(title) else {
                fail("CONFLICTING_OPERATIONS", "Album creation and deletion cannot target the same title in one batch", ["album": title])
            }
            guard destructiveAlbums.insert(title).inserted else {
                fail("CONFLICTING_OPERATIONS", "Only one destructive operation per album is allowed", ["album": title])
            }
        }

        var selected: [PHAsset] = []
        var album: PHAssetCollection?
        var currentAlbumAssets: [PHAsset] = []
        var deleteTargets: [PHAsset] = []
        var outside = 0
        var missing = 0
        var containerTitle: String?
        var containerAssetsCount = 0
        var missingInContainer = 0
        var containerExtra = 0

        switch operation.action {
        case "merge_albums_keep_assets":
            guard operation.start == nil, operation.end == nil, operation.outputDir == nil else {
                fail(
                    "MANIFEST_SCHEMA_ERROR",
                    "start, end, and output_dir are not allowed for merge_albums_keep_assets",
                    ["index": index]
                )
            }
            guard let sourceTitles = operation.sourceAlbums, sourceTitles.count >= 2 else {
                fail(
                    "MANIFEST_SCHEMA_ERROR",
                    "source_albums must contain at least two album titles",
                    ["index": index]
                )
            }
            guard Set(sourceTitles).count == sourceTitles.count else {
                fail("MANIFEST_SCHEMA_ERROR", "source_albums must not contain duplicates", ["index": index])
            }
            guard !sourceTitles.contains(title) else {
                fail(
                    "MANIFEST_SCHEMA_ERROR",
                    "The target album cannot also be a source album",
                    ["index": index, "album": title]
                )
            }
            var sourceCounts: [String: Int] = [:]
            var unionByID: [String: PHAsset] = [:]
            var sourceMemberships = 0
            for sourceTitle in sourceTitles {
                guard let sourceAlbum = exactAlbum(sourceTitle, required: true) else {
                    fail("ALBUM_NOT_FOUND", "Source album was not found", ["index": index, "album": sourceTitle])
                }
                let sourceAssets = assetArray(PHAsset.fetchAssets(in: sourceAlbum, options: nil))
                guard !sourceAssets.isEmpty else {
                    fail("EMPTY_SELECTION", "Source album contains no assets", ["index": index, "album": sourceTitle])
                }
                sourceCounts[sourceTitle] = sourceAssets.count
                sourceMemberships += sourceAssets.count
                for asset in sourceAssets { unionByID[asset.localIdentifier] = asset }
            }
            selected = Array(unionByID.values).sorted {
                ($0.creationDate ?? .distantPast, $0.localIdentifier)
                    < ($1.creationDate ?? .distantPast, $1.localIdentifier)
            }
            checkExpected(operation, actual: selected.count, index: index, apply: apply)
            album = exactAlbum(title, required: false)
            if let album {
                currentAlbumAssets = assetArray(PHAsset.fetchAssets(in: album, options: nil))
                let selectedIDs = Set(selected.map(\.localIdentifier))
                let currentIDs = Set(currentAlbumAssets.map(\.localIdentifier))
                outside = currentIDs.subtracting(selectedIDs).count
                missing = selectedIDs.subtracting(currentIDs).count
                if outside > 0 && operation.allowAlbumOutside != true {
                    fail(
                        "ALBUM_HAS_OUTSIDE_ASSETS",
                        "Existing merge target contains assets outside the source-album union",
                        ["index": index, "album": title, "outside": outside]
                    )
                }
            } else {
                missing = selected.count
            }
            emit(
                "merge_scope",
                [
                    "index": index,
                    "album": title,
                    "source_albums": sourceTitles,
                    "source_album_counts": sourceCounts,
                    "source_memberships": sourceMemberships,
                    "unique_assets": selected.count,
                    "overlapping_memberships": sourceMemberships - selected.count,
                ]
            )

        case "archive_date_range", "create_album_from_date_range":
            guard operation.start != nil, operation.end != nil else {
                fail("MANIFEST_SCHEMA_ERROR", "start and end are required", ["index": index])
            }
            if operation.action == "archive_date_range" {
                guard let output = operation.outputDir, !output.isEmpty else {
                    fail("MANIFEST_SCHEMA_ERROR", "output_dir is required", ["index": index])
                }
                let normalizedOutput = URL(fileURLWithPath: output).standardizedFileURL.path
                guard outputPaths.insert(normalizedOutput).inserted else {
                    fail("OUTPUT_PATH_CONFLICT", "Each archive operation needs a unique output_dir", ["output_dir": normalizedOutput])
                }
                validateOutputDirectory(output)
            } else if operation.outputDir != nil {
                fail("MANIFEST_SCHEMA_ERROR", "output_dir is not allowed for create_album_from_date_range", ["index": index])
            }
            selected = plannedRangeSelections[title] ?? []
            guard !selected.isEmpty else {
                fail("EMPTY_SELECTION", "Date range contains no assets", ["index": index, "album": title])
            }
            checkExpected(operation, actual: selected.count, index: index, apply: apply)
            album = exactAlbum(title, required: false)
            if let album {
                currentAlbumAssets = assetArray(PHAsset.fetchAssets(in: album, options: nil))
                let selectedIDs = Set(selected.map(\.localIdentifier))
                let currentIDs = Set(currentAlbumAssets.map(\.localIdentifier))
                outside = currentIDs.subtracting(selectedIDs).count
                missing = selectedIDs.subtracting(currentIDs).count
                if outside > 0 && operation.allowAlbumOutside != true {
                    fail(
                        "ALBUM_HAS_OUTSIDE_ASSETS",
                        "Existing album contains assets outside the selected date range",
                        ["index": index, "album": title, "outside": outside]
                    )
                }
            } else {
                missing = selected.count
            }

        case "create_remainder_album":
            guard let startText = operation.start, let endText = operation.end else {
                fail("MANIFEST_SCHEMA_ERROR", "start and end are required", ["index": index])
            }
            guard operation.outputDir == nil else {
                fail("MANIFEST_SCHEMA_ERROR", "output_dir is not allowed for create_remainder_album", ["index": index])
            }
            let excludedTitles = operation.excludeAlbums ?? []
            let reusedTitles = operation.reuseAlbums ?? []
            guard !excludedTitles.isEmpty || !reusedTitles.isEmpty else {
                fail("MANIFEST_SCHEMA_ERROR", "exclude_albums or reuse_albums is required", ["index": index])
            }
            guard Set(excludedTitles).count == excludedTitles.count else {
                fail("MANIFEST_SCHEMA_ERROR", "exclude_albums must not contain duplicates", ["index": index])
            }
            guard Set(reusedTitles).count == reusedTitles.count else {
                fail("MANIFEST_SCHEMA_ERROR", "reuse_albums must not contain duplicates", ["index": index])
            }
            guard Set(excludedTitles).isDisjoint(with: Set(reusedTitles)) else {
                fail("MANIFEST_SCHEMA_ERROR", "An album cannot be both excluded and reused", ["index": index])
            }
            guard !excludedTitles.contains(title) else {
                fail("MANIFEST_SCHEMA_ERROR", "Remainder album cannot exclude itself", ["index": index, "album": title])
            }
            guard !reusedTitles.contains(title) else {
                fail("MANIFEST_SCHEMA_ERROR", "Remainder album cannot reuse itself", ["index": index, "album": title])
            }

            let annualAssets = fetchDateRange(
                start: parseDate(startText, field: "start"),
                end: parseDate(endText, field: "end")
            )
            let annualIDs = Set(annualAssets.map(\.localIdentifier))
            var batchIDs = Set<String>()
            var batchMemberships = 0
            for excludedTitle in excludedTitles {
                let excludedAssets: [PHAsset]
                if let planned = plannedRangeSelections[excludedTitle] {
                    excludedAssets = planned
                } else {
                    guard let excludedAlbum = exactAlbum(excludedTitle, required: false) else {
                        fail(
                            "COVERAGE_ALBUM_NOT_FOUND",
                            "Excluded batch album is neither planned nor present",
                            ["index": index, "album": title, "excluded_album": excludedTitle]
                        )
                    }
                    excludedAssets = assetArray(PHAsset.fetchAssets(in: excludedAlbum, options: nil))
                }
                let excludedIDs = Set(excludedAssets.map(\.localIdentifier))
                let outsideYear = excludedIDs.subtracting(annualIDs).count
                guard outsideYear == 0 else {
                    fail(
                        "COVERAGE_ALBUM_OUTSIDE_YEAR",
                        "A batch album contains assets outside the annual range",
                        ["index": index, "excluded_album": excludedTitle, "outside": outsideYear]
                    )
                }
                batchMemberships += excludedIDs.count
                batchIDs.formUnion(excludedIDs)
            }
            let batchOverlap = batchMemberships - batchIDs.count
            guard batchOverlap == 0 else {
                fail(
                    "COVERAGE_BATCH_OVERLAP",
                    "Annual batch albums overlap; review batches must be disjoint",
                    ["index": index, "album": title, "overlapping_memberships": batchOverlap]
                )
            }

            var reusedIDs = Set<String>()
            var reusedMemberships = 0
            for reusedTitle in reusedTitles {
                guard let reusedAlbum = exactAlbum(reusedTitle, required: false) else {
                    fail(
                        "COVERAGE_ALBUM_NOT_FOUND",
                        "Reused album is not present",
                        ["index": index, "album": title, "reused_album": reusedTitle]
                    )
                }
                let allReusedIDs = Set(assetArray(PHAsset.fetchAssets(in: reusedAlbum, options: nil)).map(\.localIdentifier))
                let annualReusedIDs = allReusedIDs.intersection(annualIDs)
                guard !annualReusedIDs.isEmpty else {
                    fail(
                        "COVERAGE_REUSE_EMPTY",
                        "Reused album contains no assets from the annual range",
                        ["index": index, "reused_album": reusedTitle]
                    )
                }
                reusedMemberships += annualReusedIDs.count
                reusedIDs.formUnion(annualReusedIDs)
            }
            let newReuseOverlap = batchIDs.intersection(reusedIDs).count
            guard newReuseOverlap == 0 else {
                fail(
                    "COVERAGE_REUSE_NEW_OVERLAP",
                    "A newly proposed batch duplicates assets already covered by a reused album",
                    ["index": index, "overlap": newReuseOverlap]
                )
            }
            let coveredIDs = batchIDs.union(reusedIDs)
            let reusedOverlap = reusedMemberships - reusedIDs.count

            selected = annualAssets.filter { !coveredIDs.contains($0.localIdentifier) }
            checkExpected(operation, actual: selected.count, index: index, apply: apply)
            album = exactAlbum(title, required: false)
            if let album {
                currentAlbumAssets = assetArray(PHAsset.fetchAssets(in: album, options: nil))
                let selectedIDs = Set(selected.map(\.localIdentifier))
                let currentIDs = Set(currentAlbumAssets.map(\.localIdentifier))
                outside = currentIDs.subtracting(selectedIDs).count
                missing = selectedIDs.subtracting(currentIDs).count
                if outside > 0 && operation.allowAlbumOutside != true {
                    fail(
                        "ALBUM_HAS_OUTSIDE_ASSETS",
                        "Existing remainder album contains assets outside the computed remainder",
                        ["index": index, "album": title, "outside": outside]
                    )
                }
            } else {
                missing = selected.count
            }
            let annualStats = stats(annualAssets)
            emit(
                "annual_coverage_preflight",
                [
                    "index": index,
                    "album": title,
                    "annual_assets": annualAssets.count,
                    "batched_unique_assets": batchIDs.count,
                    "reused_unique_assets": reusedIDs.count,
                    "remainder_assets": selected.count,
                    "overlapping_batch_memberships": batchOverlap,
                    "overlapping_reused_memberships": reusedOverlap,
                    "new_reuse_overlap": newReuseOverlap,
                    "images": annualStats.images,
                    "videos": annualStats.videos,
                    "live": annualStats.live,
                ]
            )

        case "move_favorites_to_album_delete_unfavorites_and_source":
            guard operation.start == nil, operation.end == nil, operation.outputDir == nil else {
                fail(
                    "MANIFEST_SCHEMA_ERROR",
                    "start, end, and output_dir are not allowed for move_favorites_to_album_delete_unfavorites_and_source",
                    ["index": index]
                )
            }
            guard let targetTitle = operation.containerAlbum, !targetTitle.isEmpty else {
                fail("MANIFEST_SCHEMA_ERROR", "container_album is required", ["index": index])
            }
            guard targetTitle != title else {
                fail("MANIFEST_SCHEMA_ERROR", "album and container_album must differ", ["index": index])
            }
            album = exactAlbum(title)
            guard let targetAlbum = exactAlbum(targetTitle) else {
                fail("ALBUM_NOT_FOUND", "Destination album was not found", ["index": index, "album": targetTitle])
            }
            currentAlbumAssets = assetArray(PHAsset.fetchAssets(in: album!, options: nil))
            guard !currentAlbumAssets.isEmpty else {
                fail("EMPTY_SELECTION", "Source album contains no assets", ["index": index, "album": title])
            }
            checkExpected(operation, actual: currentAlbumAssets.count, index: index, apply: apply)
            selected = currentAlbumAssets.filter(\.isFavorite)
            deleteTargets = currentAlbumAssets.filter { !$0.isFavorite }
            guard !selected.isEmpty else {
                fail("EMPTY_SELECTION", "Source album contains no favorite assets to move", ["index": index, "album": title])
            }
            if let expected = operation.expectedFavorite {
                guard expected == selected.count else {
                    fail(
                        "FAVORITE_COUNT_CHANGED",
                        "Favorite count does not match expected_favorite",
                        ["index": index, "album": title, "expected": expected, "actual": selected.count]
                    )
                }
            } else if apply {
                fail("EXPECTED_COUNT_REQUIRED", "expected_favorite is required for --apply", ["index": index])
            }
            if let expected = operation.expectedUnfavorite {
                guard expected == deleteTargets.count else {
                    fail(
                        "UNFAVORITE_COUNT_CHANGED",
                        "Unfavorite count does not match expected_unfavorite",
                        ["index": index, "album": title, "expected": expected, "actual": deleteTargets.count]
                    )
                }
            } else if apply {
                fail("EXPECTED_COUNT_REQUIRED", "expected_unfavorite is required for --apply", ["index": index])
            }
            let targetAssets = assetArray(PHAsset.fetchAssets(in: targetAlbum, options: nil))
            let targetIDs = Set(targetAssets.map(\.localIdentifier))
            let favoriteIDs = Set(selected.map(\.localIdentifier))
            let unfavoriteIDs = Set(deleteTargets.map(\.localIdentifier))
            let deletionConflict = unfavoriteIDs.intersection(targetIDs).count
            guard deletionConflict == 0 else {
                fail(
                    "DESTINATION_DELETE_CONFLICT",
                    "Destination album already contains source assets selected for deletion",
                    ["index": index, "album": title, "container_album": targetTitle, "conflicting_assets": deletionConflict]
                )
            }
            containerTitle = targetTitle
            containerAssetsCount = targetAssets.count
            missingInContainer = favoriteIDs.subtracting(targetIDs).count
            containerExtra = targetIDs.subtracting(favoriteIDs).count

        case "archive_album", "archive_favorites_album", "archive_unfavorites_album":
            guard let output = operation.outputDir, !output.isEmpty else {
                fail("MANIFEST_SCHEMA_ERROR", "output_dir is required", ["index": index])
            }
            let normalizedOutput = URL(fileURLWithPath: output).standardizedFileURL.path
            guard outputPaths.insert(normalizedOutput).inserted else {
                fail("OUTPUT_PATH_CONFLICT", "Each archive operation needs a unique output_dir", ["output_dir": normalizedOutput])
            }
            validateOutputDirectory(output)
            album = exactAlbum(title)
            currentAlbumAssets = assetArray(PHAsset.fetchAssets(in: album!, options: nil))
            switch operation.action {
            case "archive_favorites_album":
                selected = currentAlbumAssets.filter(\.isFavorite)
            case "archive_unfavorites_album":
                selected = currentAlbumAssets.filter { !$0.isFavorite }
            default:
                selected = currentAlbumAssets
            }
            guard !selected.isEmpty else {
                fail("EMPTY_SELECTION", "The requested album selection is empty", ["index": index, "album": title, "action": operation.action])
            }
            checkExpected(operation, actual: selected.count, index: index, apply: apply)

        default:
            album = exactAlbum(title)
            currentAlbumAssets = assetArray(PHAsset.fetchAssets(in: album!, options: nil))
            selected = currentAlbumAssets
            checkExpected(operation, actual: currentAlbumAssets.count, index: index, apply: apply)
            if operation.action == "delete_album_assets_and_album" || operation.action == "delete_album_assets_keep_album" {
                let favoriteCount = currentAlbumAssets.filter(\.isFavorite).count
                if favoriteCount > 0 && operation.allowDeleteFavorites != true {
                    fail(
                        "FAVORITES_PROTECTED",
                        "Album contains favorites; set allow_delete_favorites only after explicit whole-album authorization",
                        ["index": index, "album": title, "favorites": favoriteCount]
                    )
                }
                deleteTargets = currentAlbumAssets
            } else if operation.action == "delete_unfavorite_assets_keep_album"
                    || operation.action == "delete_unfavorite_assets_and_album" {
                deleteTargets = currentAlbumAssets.filter { !$0.isFavorite }
                guard let expected = operation.expectedUnfavorite else {
                    if apply {
                        fail("EXPECTED_COUNT_REQUIRED", "expected_unfavorite is required for --apply", ["index": index])
                    }
                    break
                }
                guard expected == deleteTargets.count else {
                    fail(
                        "UNFAVORITE_COUNT_CHANGED",
                        "Unfavorite count does not match expected_unfavorite",
                        ["index": index, "album": title, "expected": expected, "actual": deleteTargets.count]
                    )
                }
            } else if operation.action == "delete_favorite_assets_keep_album"
                    || operation.action == "delete_favorite_assets_and_album" {
                deleteTargets = currentAlbumAssets.filter(\.isFavorite)
                guard let expected = operation.expectedFavorite else {
                    if apply {
                        fail("EXPECTED_COUNT_REQUIRED", "expected_favorite is required for --apply", ["index": index])
                    }
                    break
                }
                guard expected == deleteTargets.count else {
                    fail(
                        "FAVORITE_COUNT_CHANGED",
                        "Favorite count does not match expected_favorite",
                        ["index": index, "album": title, "expected": expected, "actual": deleteTargets.count]
                    )
                }
            } else if operation.action == "delete_album_if_contained" {
                guard let targetTitle = operation.containerAlbum, !targetTitle.isEmpty else {
                    fail("MANIFEST_SCHEMA_ERROR", "container_album is required", ["index": index])
                }
                guard targetTitle != title else {
                    fail("MANIFEST_SCHEMA_ERROR", "album and container_album must differ", ["index": index])
                }
                let targetAlbum = exactAlbum(targetTitle)
                let targetAssets = assetArray(PHAsset.fetchAssets(in: targetAlbum!, options: nil))
                let sourceIDs = Set(currentAlbumAssets.map(\.localIdentifier))
                let targetIDs = Set(targetAssets.map(\.localIdentifier))
                containerTitle = targetTitle
                containerAssetsCount = targetAssets.count
                missingInContainer = sourceIDs.subtracting(targetIDs).count
                containerExtra = targetIDs.subtracting(sourceIDs).count
                guard missingInContainer == 0 else {
                    fail(
                        "ALBUM_NOT_CONTAINED",
                        "Source album is not fully contained in container_album; no changes were made",
                        [
                            "index": index,
                            "album": title,
                            "container_album": targetTitle,
                            "source_assets": currentAlbumAssets.count,
                            "container_assets": targetAssets.count,
                            "missing_in_container": missingInContainer,
                        ]
                    )
                }
            }
        }

        let selectionStats = stats(selected)
        var event = selectionStats.json
        event["index"] = index
        event["action"] = operation.action
        event["album"] = title
        event["album_found"] = album == nil ? 0 : 1
        event["album_current_assets"] = currentAlbumAssets.count
        event["album_missing"] = missing
        event["album_outside"] = outside
        event["delete_targets"] = deleteTargets.count
        if let containerTitle {
            event["container_album"] = containerTitle
            event["container_assets"] = containerAssetsCount
            event["missing_in_container"] = missingInContainer
            event["container_extra"] = containerExtra
        }
        if let output = operation.outputDir { event["output_dir"] = output }
        if archiveActions.contains(operation.action) {
            event["live_photo_export"] = operation.livePhotoExport ?? "full_pair"
        }
        emit("operation_preflight", event)

        prepared.append(
            PreparedOperation(
                index: index,
                operation: operation,
                album: album,
                assets: selected,
                albumAssets: currentAlbumAssets,
                deleteTargets: deleteTargets,
                albumOutside: outside,
                albumMissing: missing
            )
        )
    }
    return prepared
}

func exportAssets(_ prepared: PreparedOperation) {
    guard let outputPath = prepared.operation.outputDir else { return }
    let output = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL
    do {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    } catch {
        fail("EXPORT_DIRECTORY_ERROR", error.localizedDescription, ["output_dir": output.path])
    }

    let manager = PHAssetResourceManager.default()
    let liveMode = prepared.operation.livePhotoExport ?? "full_pair"
    var used = Set<String>()
    var exportedAssets = 0
    var exportedResources = 0
    var totalBytes: Int64 = 0

    for asset in prepared.assets {
        guard let resources = originalResources(for: asset, liveMode: liveMode) else {
            let detail = asset.mediaSubtypes.contains(.photoLive) && liveMode == "full_pair"
                ? "A complete original Live Photo pair was not found"
                : "No original resource was found"
            fail("RESOURCE_NOT_FOUND", detail, ["album": prepared.operation.album ?? "", "asset": asset.localIdentifier])
        }
        for item in resources {
            let filename = safeFilename(item.resource.originalFilename, asset: asset, used: &used)
            let destination = output.appendingPathComponent(filename)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            let semaphore = DispatchSemaphore(value: 0)
            var writeError: Error?
            manager.writeData(for: item.resource, toFile: destination, options: options) { error in
                writeError = error
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .distantFuture)
            if let writeError {
                fail(
                    "EXPORT_ERROR",
                    writeError.localizedDescription,
                    ["album": prepared.operation.album ?? "", "asset": asset.localIdentifier, "filename": filename]
                )
            }
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                guard bytes > 0 else {
                    fail("EXPORT_VERIFY_ERROR", "Exported file is empty", ["filename": filename])
                }
                let checksum = try sha256(destination)
                totalBytes += bytes
                exportedResources += 1
                emit(
                    "exported_resource",
                    [
                        "album": prepared.operation.album ?? "",
                        "asset": asset.localIdentifier,
                        "filename": filename,
                        "resource_role": item.role,
                        "bytes": bytes,
                        "sha256": checksum,
                        "media": asset.mediaType == .video ? "video" : "image",
                        "live": asset.mediaSubtypes.contains(.photoLive),
                        "creation_date": iso(asset.creationDate),
                        "photos_creation_date": iso(asset.creationDate),
                        "capture_time_source": "photos_creation_date",
                    ]
                )
            } catch {
                fail("EXPORT_VERIFY_ERROR", error.localizedDescription, ["filename": filename])
            }
        }
        exportedAssets += 1
    }
    let expectedResources = prepared.assets.count
        + (liveMode == "full_pair" ? prepared.assets.filter { $0.mediaSubtypes.contains(.photoLive) }.count : 0)
    guard exportedAssets == prepared.assets.count, exportedResources == expectedResources else {
        fail(
            "EXPORT_VERIFY_ERROR",
            "Export count mismatch",
            [
                "expected_assets": prepared.assets.count,
                "actual_assets": exportedAssets,
                "expected_resources": expectedResources,
                "actual_resources": exportedResources,
            ]
        )
    }
    emit(
        "archive_complete",
        [
            "index": prepared.index,
            "album": prepared.operation.album ?? "",
            "assets": exportedAssets,
            "resource_files": exportedResources,
            "bytes": totalBytes,
            "output_dir": output.path,
            "live_mode": liveMode,
            "resource_mode": "unmodified_original",
            "embedded_metadata_preserved": true,
            "metadata_sidecar": "none",
            "capture_time_source": "photos_creation_date",
        ]
    )
}

func ensureAlbum(_ prepared: PreparedOperation) {
    guard prepared.operation.action == "archive_date_range"
            || prepared.operation.action == "create_album_from_date_range"
            || prepared.operation.action == "create_remainder_album" else { return }
    let title = prepared.operation.album!
    let selectedIDs = Set(prepared.assets.map(\.localIdentifier))

    if prepared.assets.isEmpty && prepared.operation.action == "create_remainder_album" {
        let existing = albumFetch(title)
        guard existing.count <= 1 else {
            fail("DUPLICATE_ALBUM", "Exact album title is not unique", ["album": title, "found": existing.count])
        }
        if let album = existing.firstObject {
            let current = assetArray(PHAsset.fetchAssets(in: album, options: nil))
            guard current.isEmpty else {
                fail("ALBUM_VERIFY_ERROR", "Empty remainder expected but album is not empty", ["album": title, "actual": current.count])
            }
        }
        emit(
            "album_sync_complete",
            ["album": title, "selected_assets": 0, "album_assets": 0, "missing": 0, "empty_remainder": true]
        )
        return
    }

    do {
        if let album = exactAlbum(title, required: false) {
            let current = assetArray(PHAsset.fetchAssets(in: album, options: nil))
            let currentIDs = Set(current.map(\.localIdentifier))
            let missing = prepared.assets.filter { !currentIDs.contains($0.localIdentifier) }
            if !missing.isEmpty {
                try PHPhotoLibrary.shared().performChangesAndWait {
                    guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
                    request.addAssets(missing as NSArray)
                }
            }
        } else {
            try PHPhotoLibrary.shared().performChangesAndWait {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                request.addAssets(prepared.assets as NSArray)
            }
        }
    } catch {
        fail("ALBUM_WRITE_ERROR", error.localizedDescription, ["album": title])
    }

    guard let verifiedAlbum = exactAlbum(title, required: true) else {
        fail("ALBUM_VERIFY_ERROR", "Album was not created", ["album": title])
    }
    let verified = assetArray(PHAsset.fetchAssets(in: verifiedAlbum, options: nil))
    let verifiedIDs = Set(verified.map(\.localIdentifier))
    let missingAfter = selectedIDs.subtracting(verifiedIDs).count
    guard missingAfter == 0 else {
        fail("ALBUM_VERIFY_ERROR", "Selected assets are missing after album update", ["album": title, "missing": missingAfter])
    }
    emit(
        "album_sync_complete",
        ["album": title, "selected_assets": prepared.assets.count, "album_assets": verified.count, "missing": 0]
    )
}

func mergeAlbumsKeepingAssets(_ prepared: PreparedOperation) {
    guard prepared.operation.action == "merge_albums_keep_assets" else { return }
    let targetTitle = prepared.operation.album!
    let sourceTitles = prepared.operation.sourceAlbums ?? []
    let selectedIDs = Set(prepared.assets.map(\.localIdentifier))
    var sourceAlbums: [PHAssetCollection] = []
    var currentUnionIDs = Set<String>()

    for sourceTitle in sourceTitles {
        guard let sourceAlbum = exactAlbum(sourceTitle, required: true) else {
            fail("ALBUM_NOT_FOUND", "Source album disappeared before merge", ["album": sourceTitle])
        }
        sourceAlbums.append(sourceAlbum)
        currentUnionIDs.formUnion(
            assetArray(PHAsset.fetchAssets(in: sourceAlbum, options: nil)).map(\.localIdentifier)
        )
    }
    guard currentUnionIDs == selectedIDs else {
        fail(
            "ASSET_COUNT_CHANGED",
            "Source album membership changed before merge",
            [
                "album": targetTitle,
                "expected": selectedIDs.count,
                "actual": currentUnionIDs.count,
            ]
        )
    }

    do {
        if let targetAlbum = exactAlbum(targetTitle, required: false) {
            let currentIDs = Set(assetArray(PHAsset.fetchAssets(in: targetAlbum, options: nil)).map(\.localIdentifier))
            let missing = prepared.assets.filter { !currentIDs.contains($0.localIdentifier) }
            try PHPhotoLibrary.shared().performChangesAndWait {
                if !missing.isEmpty, let request = PHAssetCollectionChangeRequest(for: targetAlbum) {
                    request.addAssets(missing as NSArray)
                }
                PHAssetCollectionChangeRequest.deleteAssetCollections(sourceAlbums as NSArray)
            }
        } else {
            try PHPhotoLibrary.shared().performChangesAndWait {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: targetTitle)
                request.addAssets(prepared.assets as NSArray)
                PHAssetCollectionChangeRequest.deleteAssetCollections(sourceAlbums as NSArray)
            }
        }
    } catch {
        fail("ALBUM_MERGE_ERROR", error.localizedDescription, ["album": targetTitle])
    }

    guard let verifiedTarget = exactAlbum(targetTitle, required: true) else {
        fail("ALBUM_MERGE_VERIFY_ERROR", "Merge target was not created", ["album": targetTitle])
    }
    let targetIDs = Set(assetArray(PHAsset.fetchAssets(in: verifiedTarget, options: nil)).map(\.localIdentifier))
    let missing = selectedIDs.subtracting(targetIDs).count
    let outside = targetIDs.subtracting(selectedIDs).count
    guard missing == 0 else {
        fail("ALBUM_MERGE_VERIFY_ERROR", "Merge target is missing source assets", ["album": targetTitle, "missing": missing])
    }
    guard outside == 0 || prepared.operation.allowAlbumOutside == true else {
        fail("ALBUM_MERGE_VERIFY_ERROR", "Merge target contains unexpected assets", ["album": targetTitle, "outside": outside])
    }
    for sourceTitle in sourceTitles {
        let remaining = albumFetch(sourceTitle).count
        guard remaining == 0 else {
            fail(
                "ALBUM_MERGE_VERIFY_ERROR",
                "Source album still exists after merge",
                ["album": sourceTitle, "remaining_albums": remaining]
            )
        }
    }
    let retained = selectedIDs.isEmpty
        ? 0
        : PHAsset.fetchAssets(withLocalIdentifiers: Array(selectedIDs), options: nil).count
    guard retained == selectedIDs.count else {
        fail(
            "ALBUM_MERGE_VERIFY_ERROR",
            "One or more source assets were not retained",
            ["expected_retained": selectedIDs.count, "retained": retained]
        )
    }
    emit(
        "album_merge_complete",
        [
            "album": targetTitle,
            "source_albums_deleted": sourceTitles.count,
            "assets": selectedIDs.count,
            "target_assets": targetIDs.count,
            "retained_assets": retained,
            "missing": 0,
            "outside": outside,
        ]
    )
}

func moveFavoritesToAlbumAndDeleteRemainder(_ prepared: PreparedOperation) {
    guard prepared.operation.action == "move_favorites_to_album_delete_unfavorites_and_source" else { return }
    let sourceTitle = prepared.operation.album!
    let targetTitle = prepared.operation.containerAlbum!
    guard let sourceAlbum = exactAlbum(sourceTitle, required: true) else {
        fail("ALBUM_NOT_FOUND", "Source album disappeared before apply", ["album": sourceTitle])
    }
    guard let targetAlbum = exactAlbum(targetTitle, required: true) else {
        fail("ALBUM_NOT_FOUND", "Destination album disappeared before apply", ["album": targetTitle])
    }

    let currentSource = assetArray(PHAsset.fetchAssets(in: sourceAlbum, options: nil))
    let currentSourceIDs = Set(currentSource.map(\.localIdentifier))
    let preparedSourceIDs = Set(prepared.albumAssets.map(\.localIdentifier))
    guard currentSourceIDs == preparedSourceIDs else {
        fail(
            "ASSET_COUNT_CHANGED",
            "Source album membership changed before apply",
            ["album": sourceTitle, "expected": preparedSourceIDs.count, "actual": currentSourceIDs.count]
        )
    }

    let favorites = currentSource.filter(\.isFavorite)
    let unfavorites = currentSource.filter { !$0.isFavorite }
    guard favorites.count == prepared.assets.count else {
        fail(
            "FAVORITE_COUNT_CHANGED",
            "Favorite marker selection changed before apply",
            ["album": sourceTitle, "expected": prepared.assets.count, "actual": favorites.count]
        )
    }
    guard unfavorites.count == prepared.deleteTargets.count else {
        fail(
            "UNFAVORITE_COUNT_CHANGED",
            "Unfavorite marker selection changed before apply",
            ["album": sourceTitle, "expected": prepared.deleteTargets.count, "actual": unfavorites.count]
        )
    }

    let favoriteIDs = Set(favorites.map(\.localIdentifier))
    let preparedFavoriteIDs = Set(prepared.assets.map(\.localIdentifier))
    guard favoriteIDs == preparedFavoriteIDs else {
        fail("FAVORITE_COUNT_CHANGED", "Favorite marker membership changed before apply", ["album": sourceTitle])
    }
    let unfavoriteIDs = Set(unfavorites.map(\.localIdentifier))
    let preparedUnfavoriteIDs = Set(prepared.deleteTargets.map(\.localIdentifier))
    guard unfavoriteIDs == preparedUnfavoriteIDs else {
        fail("UNFAVORITE_COUNT_CHANGED", "Unfavorite marker membership changed before apply", ["album": sourceTitle])
    }

    let targetBefore = assetArray(PHAsset.fetchAssets(in: targetAlbum, options: nil))
    let targetBeforeIDs = Set(targetBefore.map(\.localIdentifier))
    let deletionConflict = unfavoriteIDs.intersection(targetBeforeIDs).count
    guard deletionConflict == 0 else {
        fail(
            "DESTINATION_DELETE_CONFLICT",
            "Destination album contains source assets selected for deletion; no changes were made",
            ["album": sourceTitle, "container_album": targetTitle, "conflicting_assets": deletionConflict]
        )
    }
    let missingFavorites = favorites.filter { !targetBeforeIDs.contains($0.localIdentifier) }
    let unfavoriteFetch = PHAsset.fetchAssets(withLocalIdentifiers: Array(unfavoriteIDs), options: nil)
    guard unfavoriteFetch.count == unfavoriteIDs.count else {
        fail(
            "DELETE_FETCH_ERROR",
            "Could not refetch every unmarked deletion target",
            ["expected": unfavoriteIDs.count, "actual": unfavoriteFetch.count]
        )
    }

    emit(
        "favorite_move_delete_scope",
        [
            "album": sourceTitle,
            "container_album": targetTitle,
            "source_assets": currentSource.count,
            "favorite_assets": favorites.count,
            "favorites_already_in_container": favorites.count - missingFavorites.count,
            "favorites_to_add": missingFavorites.count,
            "unfavorite_assets_to_delete": unfavorites.count,
            "container_assets_before": targetBefore.count,
        ]
    )

    do {
        try PHPhotoLibrary.shared().performChangesAndWait {
            if !missingFavorites.isEmpty, let request = PHAssetCollectionChangeRequest(for: targetAlbum) {
                request.addAssets(missingFavorites as NSArray)
            }
            if unfavoriteFetch.count > 0 { PHAssetChangeRequest.deleteAssets(unfavoriteFetch) }
            PHAssetCollectionChangeRequest.deleteAssetCollections([sourceAlbum] as NSArray)
        }
    } catch {
        fail(
            "FAVORITE_MOVE_DELETE_ERROR",
            error.localizedDescription,
            ["album": sourceTitle, "container_album": targetTitle]
        )
    }

    guard albumFetch(sourceTitle).count == 0 else {
        fail("FAVORITE_MOVE_DELETE_VERIFY_ERROR", "Source album still exists", ["album": sourceTitle])
    }
    guard let verifiedTarget = exactAlbum(targetTitle, required: true) else {
        fail("FAVORITE_MOVE_DELETE_VERIFY_ERROR", "Destination album is missing", ["container_album": targetTitle])
    }
    let targetAfterIDs = Set(assetArray(PHAsset.fetchAssets(in: verifiedTarget, options: nil)).map(\.localIdentifier))
    let missingOriginalTarget = targetBeforeIDs.subtracting(targetAfterIDs).count
    let missingFavoritesAfter = favoriteIDs.subtracting(targetAfterIDs).count
    guard missingOriginalTarget == 0 && missingFavoritesAfter == 0 else {
        fail(
            "FAVORITE_MOVE_DELETE_VERIFY_ERROR",
            "Destination album verification failed",
            [
                "container_album": targetTitle,
                "missing_original_target_assets": missingOriginalTarget,
                "missing_favorite_assets": missingFavoritesAfter,
            ]
        )
    }
    let retainedFavorites = PHAsset.fetchAssets(withLocalIdentifiers: Array(favoriteIDs), options: nil).count
    guard retainedFavorites == favoriteIDs.count else {
        fail(
            "FAVORITE_MOVE_DELETE_VERIFY_ERROR",
            "One or more favorite assets were not retained",
            ["expected": favoriteIDs.count, "retained": retainedFavorites]
        )
    }
    let remainingUnfavorites = unfavoriteIDs.isEmpty
        ? 0
        : PHAsset.fetchAssets(withLocalIdentifiers: Array(unfavoriteIDs), options: nil).count
    guard remainingUnfavorites == 0 else {
        fail(
            "FAVORITE_MOVE_DELETE_VERIFY_ERROR",
            "One or more unmarked assets remain in Photos",
            ["remaining": remainingUnfavorites]
        )
    }
    emit(
        "favorite_move_delete_complete",
        [
            "album": sourceTitle,
            "container_album": targetTitle,
            "moved_favorites": favoriteIDs.count,
            "deleted_unfavorites": unfavoriteIDs.count,
            "source_album_deleted": true,
            "container_assets": targetAfterIDs.count,
            "retained_favorites": retainedFavorites,
            "remaining_unfavorites": 0,
        ]
    )
}

func verifyAnnualCoverage(_ prepared: [PreparedOperation]) {
    for item in prepared where item.operation.action == "create_remainder_album" {
        guard let startText = item.operation.start,
              let endText = item.operation.end,
              let remainderTitle = item.operation.album else {
            fail("MANIFEST_SCHEMA_ERROR", "Remainder coverage fields are missing", ["index": item.index])
        }
        let excludedTitles = item.operation.excludeAlbums ?? []
        let reusedTitles = item.operation.reuseAlbums ?? []

        let annualAssets = fetchDateRange(
            start: parseDate(startText, field: "start"),
            end: parseDate(endText, field: "end")
        )
        let annualIDs = Set(annualAssets.map(\.localIdentifier))
        var batchIDs = Set<String>()
        var memberships = 0

        for title in excludedTitles {
            guard let album = exactAlbum(title, required: true) else {
                fail("ANNUAL_COVERAGE_VERIFY_ERROR", "Batch album is missing", ["album": title])
            }
            let assets = assetArray(PHAsset.fetchAssets(in: album, options: nil))
            let ids = Set(assets.map(\.localIdentifier))
            let outside = ids.subtracting(annualIDs).count
            guard outside == 0 else {
                fail(
                    "ANNUAL_COVERAGE_VERIFY_ERROR",
                    "Batch album contains assets outside the annual range",
                    ["album": title, "outside": outside]
                )
            }
            memberships += ids.count
            batchIDs.formUnion(ids)
        }

        let overlap = memberships - batchIDs.count
        guard overlap == 0 else {
            fail(
                "ANNUAL_COVERAGE_VERIFY_ERROR",
                "Batch albums overlap after creation",
                ["overlapping_memberships": overlap]
            )
        }

        var reusedIDs = Set<String>()
        var reusedMemberships = 0
        for title in reusedTitles {
            guard let album = exactAlbum(title, required: true) else {
                fail("ANNUAL_COVERAGE_VERIFY_ERROR", "Reused album is missing", ["album": title])
            }
            let allIDs = Set(assetArray(PHAsset.fetchAssets(in: album, options: nil)).map(\.localIdentifier))
            let annualReusedIDs = allIDs.intersection(annualIDs)
            guard !annualReusedIDs.isEmpty else {
                fail("ANNUAL_COVERAGE_VERIFY_ERROR", "Reused album no longer covers the year", ["album": title])
            }
            reusedMemberships += annualReusedIDs.count
            reusedIDs.formUnion(annualReusedIDs)
        }
        let newReuseOverlap = batchIDs.intersection(reusedIDs).count
        guard newReuseOverlap == 0 else {
            fail(
                "ANNUAL_COVERAGE_VERIFY_ERROR",
                "A new batch overlaps a reused existing album",
                ["overlap": newReuseOverlap]
            )
        }
        let reusedOverlap = reusedMemberships - reusedIDs.count

        let remainderAssets: [PHAsset]
        if let remainderAlbum = exactAlbum(remainderTitle, required: false) {
            remainderAssets = assetArray(PHAsset.fetchAssets(in: remainderAlbum, options: nil))
        } else {
            remainderAssets = []
        }
        let remainderIDs = Set(remainderAssets.map(\.localIdentifier))
        let remainderOutside = remainderIDs.subtracting(annualIDs).count
        guard remainderOutside == 0 else {
            fail(
                "ANNUAL_COVERAGE_VERIFY_ERROR",
                "Remainder album contains assets outside the annual range",
                ["album": remainderTitle, "outside": remainderOutside]
            )
        }
        let coveredIDs = batchIDs.union(reusedIDs)
        let crossOverlap = remainderIDs.intersection(coveredIDs).count
        guard crossOverlap == 0 else {
            fail(
                "ANNUAL_COVERAGE_VERIFY_ERROR",
                "Remainder album overlaps a batch album",
                ["album": remainderTitle, "overlap": crossOverlap]
            )
        }

        let capturedIDs = coveredIDs.union(remainderIDs)
        let missing = annualIDs.subtracting(capturedIDs).count
        let unexpected = capturedIDs.subtracting(annualIDs).count
        guard missing == 0 && unexpected == 0 else {
            fail(
                "ANNUAL_COVERAGE_VERIFY_ERROR",
                "Annual review albums do not exactly cover the year",
                ["missing": missing, "unexpected": unexpected]
            )
        }

        let annualStats = stats(annualAssets)
        emit(
            "annual_coverage_verified",
            [
                "annual_assets": annualAssets.count,
                "batched_unique_assets": batchIDs.count,
                "reused_unique_assets": reusedIDs.count,
                "remainder_assets": remainderIDs.count,
                "captured_unique_assets": capturedIDs.count,
                "overlapping_batch_memberships": 0,
                "overlapping_reused_memberships": reusedOverlap,
                "new_reuse_overlap": 0,
                "missing": 0,
                "images": annualStats.images,
                "videos": annualStats.videos,
                "live": annualStats.live,
            ]
        )
    }
}

func applyDeletions(_ prepared: [PreparedOperation]) {
    let deletionOps = prepared.filter { destructiveActions.contains($0.operation.action) }
    guard !deletionOps.isEmpty else { return }

    var targetIDs = Set<String>()
    var protectedIDs = Set<String>()
    var memberships = 0
    var albumsToDelete: [PHAssetCollection] = []
    for item in deletionOps {
        memberships += item.deleteTargets.count
        targetIDs.formUnion(item.deleteTargets.map(\.localIdentifier))
        if item.operation.action == "delete_unfavorite_assets_keep_album"
                || item.operation.action == "delete_unfavorite_assets_and_album" {
            protectedIDs.formUnion(item.albumAssets.filter(\.isFavorite).map(\.localIdentifier))
        } else if item.operation.action == "delete_favorite_assets_keep_album"
                || item.operation.action == "delete_favorite_assets_and_album" {
            protectedIDs.formUnion(item.albumAssets.filter { !$0.isFavorite }.map(\.localIdentifier))
        } else if item.operation.action == "delete_album_keep_assets"
                || item.operation.action == "delete_album_if_contained" {
            protectedIDs.formUnion(item.albumAssets.map(\.localIdentifier))
        }
        if item.operation.action == "delete_album_assets_and_album"
                || item.operation.action == "delete_album_keep_assets"
                || item.operation.action == "delete_unfavorite_assets_and_album"
                || item.operation.action == "delete_favorite_assets_and_album"
                || item.operation.action == "delete_album_if_contained" {
            if let album = item.album { albumsToDelete.append(album) }
        }
    }

    let protectedConflict = targetIDs.intersection(protectedIDs).count
    guard protectedConflict == 0 else {
        fail(
            "PROTECTED_ASSET_CONFLICT",
            "A grouped deletion would remove assets another operation must retain",
            ["conflicting_assets": protectedConflict]
        )
    }

    emit(
        "deletion_scope",
        [
            "operations": deletionOps.count,
            "asset_memberships": memberships,
            "unique_assets": targetIDs.count,
            "overlapping_memberships": memberships - targetIDs.count,
            "protected_assets": protectedIDs.count,
            "protected_conflicts": 0,
            "albums_to_delete": albumsToDelete.count,
        ]
    )

    let targetFetch = PHAsset.fetchAssets(withLocalIdentifiers: Array(targetIDs), options: nil)
    guard targetFetch.count == targetIDs.count else {
        fail("DELETE_FETCH_ERROR", "Could not refetch every deletion target", ["expected": targetIDs.count, "actual": targetFetch.count])
    }

    do {
        try PHPhotoLibrary.shared().performChangesAndWait {
            if targetFetch.count > 0 { PHAssetChangeRequest.deleteAssets(targetFetch) }
            if !albumsToDelete.isEmpty {
                PHAssetCollectionChangeRequest.deleteAssetCollections(albumsToDelete as NSArray)
            }
        }
    } catch {
        fail("DELETE_ERROR", error.localizedDescription)
    }

    let remainingDeleted = targetIDs.isEmpty
        ? 0
        : PHAsset.fetchAssets(withLocalIdentifiers: Array(targetIDs), options: nil).count
    guard remainingDeleted == 0 else {
        fail("DELETE_VERIFY_ERROR", "Deleted assets remain in Photos", ["remaining": remainingDeleted])
    }

    for item in deletionOps {
        let title = item.operation.album!
        let action = item.operation.action
        let albums = albumFetch(title)
        if action == "delete_album_assets_and_album"
                || action == "delete_album_keep_assets"
                || action == "delete_unfavorite_assets_and_album"
                || action == "delete_favorite_assets_and_album"
                || action == "delete_album_if_contained" {
            guard albums.count == 0 else {
                fail("DELETE_VERIFY_ERROR", "Album still exists", ["album": title, "remaining_albums": albums.count])
            }
            var verification: [String: Any] = [
                "album": title,
                "album_preserved": false,
                "remaining_assets_in_album": 0,
            ]
            if action == "delete_unfavorite_assets_and_album" {
                let retainedIDs = item.albumAssets.filter(\.isFavorite).map(\.localIdentifier)
                let retained = retainedIDs.isEmpty
                    ? 0
                    : PHAsset.fetchAssets(withLocalIdentifiers: retainedIDs, options: nil).count
                guard retained == retainedIDs.count else {
                    fail(
                        "DELETE_VERIFY_ERROR",
                        "One or more favorite assets were not retained",
                        ["album": title, "expected_favorites": retainedIDs.count, "retained_favorites": retained]
                    )
                }
                verification["retained_favorites"] = retained
            }
            if action == "delete_favorite_assets_and_album" {
                let retainedIDs = item.albumAssets.filter { !$0.isFavorite }.map(\.localIdentifier)
                let retained = retainedIDs.isEmpty
                    ? 0
                    : PHAsset.fetchAssets(withLocalIdentifiers: retainedIDs, options: nil).count
                guard retained == retainedIDs.count else {
                    fail(
                        "DELETE_VERIFY_ERROR",
                        "One or more unmarked assets were not retained",
                        ["album": title, "expected_unmarked": retainedIDs.count, "retained_unmarked": retained]
                    )
                }
                verification["retained_unmarked"] = retained
            }
            if action == "delete_album_keep_assets" {
                let retainedIDs = item.albumAssets.map(\.localIdentifier)
                let retained = retainedIDs.isEmpty
                    ? 0
                    : PHAsset.fetchAssets(withLocalIdentifiers: retainedIDs, options: nil).count
                guard retained == retainedIDs.count else {
                    fail(
                        "DELETE_VERIFY_ERROR",
                        "One or more album assets were not retained",
                        ["album": title, "expected_retained": retainedIDs.count, "retained": retained]
                    )
                }
                verification["retained_assets"] = retained
            }
            if action == "delete_album_if_contained", let containerTitle = item.operation.containerAlbum {
                guard let container = exactAlbum(containerTitle) else {
                    fail("DELETE_VERIFY_ERROR", "Container album is missing", ["container_album": containerTitle])
                }
                let containerAssets = assetArray(PHAsset.fetchAssets(in: container, options: nil))
                let sourceIDs = Set(item.albumAssets.map(\.localIdentifier))
                let containerIDs = Set(containerAssets.map(\.localIdentifier))
                let missing = sourceIDs.subtracting(containerIDs).count
                guard missing == 0 else {
                    fail(
                        "DELETE_VERIFY_ERROR",
                        "Container album lost source assets",
                        ["container_album": containerTitle, "missing": missing]
                    )
                }
                verification["container_album"] = containerTitle
                verification["container_assets"] = containerAssets.count
                verification["missing_in_container"] = 0
            }
            emit("deletion_verified", verification)
        } else {
            guard albums.count == 1, let album = albums.firstObject else {
                fail("DELETE_VERIFY_ERROR", "Preserved album is missing or duplicated", ["album": title, "found": albums.count])
            }
            let remaining = assetArray(PHAsset.fetchAssets(in: album, options: nil))
            let originalIDs = Set(item.albumAssets.map(\.localIdentifier))
            let expectedRemaining = originalIDs.subtracting(targetIDs).count
            guard remaining.count == expectedRemaining else {
                fail(
                    "DELETE_VERIFY_ERROR",
                    "Preserved album count is unexpected",
                    ["album": title, "expected": expectedRemaining, "actual": remaining.count]
                )
            }
            emit(
                "deletion_verified",
                ["album": title, "album_preserved": true, "remaining_assets_in_album": remaining.count]
            )
        }
    }
    emit("deletion_complete", ["unique_assets": targetIDs.count, "deleted_albums": albumsToDelete.count])
}

func inspectAlbums() {
    let titles = argumentValues("--album")
    guard !titles.isEmpty else {
        fail("ARGUMENT_ERROR", "inspect requires one or more --album values")
    }
    for title in titles {
        let albums = albumFetch(title)
        if albums.count == 0 {
            emit("album_inspection", ["album": title, "found": 0])
            continue
        }
        if albums.count > 1 {
            emit("album_inspection", ["album": title, "found": albums.count, "error": "duplicate_title"])
            continue
        }
        let assets = assetArray(PHAsset.fetchAssets(in: albums.firstObject!, options: nil))
        var result = stats(assets).json
        result["album"] = title
        result["found"] = 1
        emit("album_inspection", result)
    }
    emit("inspect_complete", ["albums": titles.count])
}

func userAlbumIndex() -> [AlbumAssetIndex] {
    let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
    var result: [AlbumAssetIndex] = []
    collections.enumerateObjects { album, _, _ in
        guard let title = album.localizedTitle, !title.isEmpty else { return }
        let assets = assetArray(PHAsset.fetchAssets(in: album, options: nil))
        result.append(
            AlbumAssetIndex(
                title: title,
                identifier: album.localIdentifier,
                assetIDs: Set(assets.map(\.localIdentifier)),
                totalAssets: assets.count
            )
        )
    }
    return result
}

func scanTravelClusters() {
    guard let startText = argumentValue("--start"), let endText = argumentValue("--end") else {
        fail("ARGUMENT_ERROR", "scan requires --start and --end")
    }
    let gapHours = Double(argumentValue("--gap-hours") ?? "36") ?? 36
    guard gapHours > 0 else { fail("ARGUMENT_ERROR", "--gap-hours must be positive") }
    let assets = fetchDateRange(
        start: parseDate(startText, field: "start"),
        end: parseDate(endText, field: "end")
    ).filter { $0.creationDate != nil }
    let existingAlbums = userAlbumIndex()

    var clusters: [[PHAsset]] = []
    for asset in assets {
        if let last = clusters.last?.last?.creationDate,
           let current = asset.creationDate,
           current.timeIntervalSince(last) <= gapHours * 3600 {
            clusters[clusters.count - 1].append(asset)
        } else {
            clusters.append([asset])
        }
    }

    for (offset, cluster) in clusters.enumerated() {
        var result = stats(cluster).json
        let clusterIDs = Set(cluster.map(\.localIdentifier))
        var coveredIDs = Set<String>()
        var overlaps: [ClusterAlbumOverlap] = []
        for album in existingAlbums {
            let matchedIDs = clusterIDs.intersection(album.assetIDs)
            guard !matchedIDs.isEmpty else { continue }
            coveredIDs.formUnion(matchedIDs)
            overlaps.append(ClusterAlbumOverlap(album: album, matchedAssets: matchedIDs.count))
        }
        overlaps.sort {
            if $0.matchedAssets != $1.matchedAssets { return $0.matchedAssets > $1.matchedAssets }
            if $0.album.totalAssets != $1.album.totalAssets { return $0.album.totalAssets < $1.album.totalAssets }
            return $0.album.title.localizedStandardCompare($1.album.title) == .orderedAscending
        }
        let fullCover = overlaps.filter { $0.matchedAssets == cluster.count }
        result["existing_album_coverage"] = overlaps.map {
            [
                "album": $0.album.title,
                "album_identifier": $0.album.identifier,
                "matched_assets": $0.matchedAssets,
                "album_assets": $0.album.totalAssets,
                "outside_cluster": $0.album.totalAssets - $0.matchedAssets,
                "complete_cluster_cover": $0.matchedAssets == cluster.count,
            ] as [String: Any]
        }
        result["existing_album_covered_unique_assets"] = coveredIDs.count
        result["uncovered_assets"] = clusterIDs.subtracting(coveredIDs).count
        result["fully_covered_by_one_existing_album"] = !fullCover.isEmpty
        result["fully_covered_by_existing_albums_union"] = coveredIDs.count == cluster.count
        result["complete_cover_albums"] = fullCover.map { $0.album.title }
        let locations = cluster.compactMap(\.location)
        if !locations.isEmpty {
            result["centroid_latitude"] = locations.map { $0.coordinate.latitude }.reduce(0, +) / Double(locations.count)
            result["centroid_longitude"] = locations.map { $0.coordinate.longitude }.reduce(0, +) / Double(locations.count)
        }
        result["cluster"] = offset + 1
        emit("travel_cluster", result)
    }
    emit("scan_complete", ["assets": assets.count, "clusters": clusters.count, "gap_hours": gapHours])
}

func runBatch() {
    guard let manifestPath = argumentValue("--manifest") else {
        fail("ARGUMENT_ERROR", "batch requires --manifest")
    }
    let apply = hasArgument("--apply")
    let manifest = loadManifest(manifestPath)
    let prepared = prepare(manifest, apply: apply)
    emit("batch_preflight_complete", ["operations": prepared.count, "apply": apply])
    guard apply else {
        emit("batch_complete", ["operations": prepared.count, "applied": false])
        return
    }

    for item in prepared where item.operation.action == "archive_album"
            || item.operation.action == "archive_favorites_album"
            || item.operation.action == "archive_unfavorites_album"
            || item.operation.action == "archive_date_range" {
        exportAssets(item)
    }
    for item in prepared where item.operation.action == "archive_date_range"
            || item.operation.action == "create_album_from_date_range" {
        ensureAlbum(item)
    }
    for item in prepared where item.operation.action == "create_remainder_album" {
        ensureAlbum(item)
    }
    for item in prepared where item.operation.action == "merge_albums_keep_assets" {
        mergeAlbumsKeepingAssets(item)
    }
    for item in prepared where item.operation.action == "move_favorites_to_album_delete_unfavorites_and_source" {
        moveFavoritesToAlbumAndDeleteRemainder(item)
    }
    verifyAnnualCoverage(prepared)
    applyDeletions(prepared)
    emit("batch_complete", ["operations": prepared.count, "applied": true])
}

func validateManifestCommand() {
    guard let manifestPath = argumentValue("--manifest") else {
        fail("ARGUMENT_ERROR", "validate-manifest requires --manifest")
    }
    let manifest = loadManifest(manifestPath)
    emit("manifest_valid", ["version": manifest.version, "operations": manifest.operations.count])
}

func runCommand() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        fail("ARGUMENT_ERROR", "Expected status, inspect, scan, or batch")
    }
    switch args[1] {
    case "inspect": inspectAlbums()
    case "scan": scanTravelClusters()
    case "batch": runBatch()
    case "validate-manifest": validateManifestCommand()
    default: fail("ARGUMENT_ERROR", "Unknown command", ["command": args[1]])
    }
    Thread.sleep(forTimeInterval: 0.35)
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        let args = CommandLine.arguments
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if args.count >= 2, args[1] == "status" {
            emit("authorization", ["status": status.rawValue, "authorized": status == .authorized || status == .limited])
            Thread.sleep(forTimeInterval: 0.35)
            exit(0)
        }
        if args.count >= 2, args[1] == "validate-manifest" {
            runCommand()
        }

        if status == .authorized || status == .limited {
            DispatchQueue.global(qos: .userInitiated).async { runCommand() }
        } else if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                guard newStatus == .authorized || newStatus == .limited else {
                    fail("AUTHORIZATION_DENIED", "Full Photos access was not granted", ["status": newStatus.rawValue], exitCode: 3)
                }
                DispatchQueue.global(qos: .userInitiated).async { runCommand() }
            }
        } else {
            fail("AUTHORIZATION_DENIED", "Photos access is denied or restricted", ["status": status.rawValue], exitCode: 3)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
