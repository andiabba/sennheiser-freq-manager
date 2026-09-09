import Foundation

struct FrequencyBand: Identifiable, Hashable {
    let id: String
    let manufacturer: String
    let name: String
    let startMHz: Int
    let endMHz: Int

    var rangeString: String { "\(startMHz)–\(endMHz) MHz" }
    var bandwidthMHz: Int { endMHz - startMHz }
}

extension FrequencyBand {

    // MARK: - Sennheiser EW G4

    static let sennheiserBands: [FrequencyBand] = [
        .init(id: "senn-a1",  manufacturer: "Sennheiser", name: "A1",  startMHz: 470, endMHz: 516),
        .init(id: "senn-a",   manufacturer: "Sennheiser", name: "A",   startMHz: 516, endMHz: 558),
        .init(id: "senn-as",  manufacturer: "Sennheiser", name: "AS",  startMHz: 520, endMHz: 558),
        .init(id: "senn-g1",  manufacturer: "Sennheiser", name: "G1",  startMHz: 558, endMHz: 608),
        .init(id: "senn-g",   manufacturer: "Sennheiser", name: "G",   startMHz: 566, endMHz: 608),
        .init(id: "senn-gw",  manufacturer: "Sennheiser", name: "Gw",  startMHz: 558, endMHz: 626),
        .init(id: "senn-gb",  manufacturer: "Sennheiser", name: "GB",  startMHz: 606, endMHz: 648),
        .init(id: "senn-b",   manufacturer: "Sennheiser", name: "B",   startMHz: 626, endMHz: 668),
        .init(id: "senn-c",   manufacturer: "Sennheiser", name: "C",   startMHz: 734, endMHz: 776),
        .init(id: "senn-d",   manufacturer: "Sennheiser", name: "D",   startMHz: 780, endMHz: 822),
        .init(id: "senn-e",   manufacturer: "Sennheiser", name: "E",   startMHz: 823, endMHz: 865),
    ]

    // MARK: - Shure (Wireless & PSM)

    static let shureBands: [FrequencyBand] = [
        .init(id: "shure-g50",  manufacturer: "Shure", name: "G50",  startMHz: 470, endMHz: 534),
        .init(id: "shure-g57",  manufacturer: "Shure", name: "G57",  startMHz: 470, endMHz: 534),
        .init(id: "shure-g20",  manufacturer: "Shure", name: "G20",  startMHz: 488, endMHz: 524),
        .init(id: "shure-h20",  manufacturer: "Shure", name: "H20",  startMHz: 518, endMHz: 554),
        .init(id: "shure-h50",  manufacturer: "Shure", name: "H50",  startMHz: 534, endMHz: 598),
        .init(id: "shure-h54",  manufacturer: "Shure", name: "H54",  startMHz: 534, endMHz: 598),
        .init(id: "shure-j52",  manufacturer: "Shure", name: "J52",  startMHz: 558, endMHz: 616),
        .init(id: "shure-j50a", manufacturer: "Shure", name: "J50A", startMHz: 572, endMHz: 616),
        .init(id: "shure-j50",  manufacturer: "Shure", name: "J50",  startMHz: 572, endMHz: 636),
        .init(id: "shure-j10",  manufacturer: "Shure", name: "J10",  startMHz: 584, endMHz: 644),
        .init(id: "shure-k1",   manufacturer: "Shure", name: "K1",   startMHz: 596, endMHz: 668),
        .init(id: "shure-k51",  manufacturer: "Shure", name: "K51",  startMHz: 606, endMHz: 670),
        .init(id: "shure-k53",  manufacturer: "Shure", name: "K53",  startMHz: 606, endMHz: 699),
        .init(id: "shure-l50",  manufacturer: "Shure", name: "L50",  startMHz: 632, endMHz: 696),
        .init(id: "shure-l57",  manufacturer: "Shure", name: "L57",  startMHz: 650, endMHz: 694),
        .init(id: "shure-p2",   manufacturer: "Shure", name: "P2",   startMHz: 702, endMHz: 736),
    ]

    static let allBands: [FrequencyBand] = sennheiserBands + shureBands

    // MARK: - Range merging

    struct ScanRange: Hashable {
        let startMHz: Int
        let endMHz: Int
        var bandwidthMHz: Int { endMHz - startMHz }
    }

    static func mergeRanges(_ bands: [FrequencyBand]) -> [ScanRange] {
        guard !bands.isEmpty else { return [] }
        let sorted = bands.sorted { $0.startMHz < $1.startMHz }
        var merged: [ScanRange] = [ScanRange(startMHz: sorted[0].startMHz, endMHz: sorted[0].endMHz)]
        for band in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if band.startMHz <= last.endMHz {
                merged[merged.count - 1] = ScanRange(
                    startMHz: last.startMHz,
                    endMHz: max(last.endMHz, band.endMHz)
                )
            } else {
                merged.append(ScanRange(startMHz: band.startMHz, endMHz: band.endMHz))
            }
        }
        return merged
    }

    static func totalChunks(ranges: [ScanRange], stepResolution: Int) -> Int {
        ranges.reduce(0) { $0 + ($1.bandwidthMHz + stepResolution - 1) / stepResolution }
    }
}
