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

    // MARK: - Shure ULXD / QLX-D / BLX

    static let shureWirelessBands: [FrequencyBand] = [
        .init(id: "shure-g50",  manufacturer: "Shure ULXD", name: "G50",  startMHz: 470, endMHz: 534),
        .init(id: "shure-h50",  manufacturer: "Shure ULXD", name: "H50",  startMHz: 534, endMHz: 598),
        .init(id: "shure-j50",  manufacturer: "Shure ULXD", name: "J50",  startMHz: 572, endMHz: 636),
        .init(id: "shure-j50a", manufacturer: "Shure ULXD", name: "J50A", startMHz: 572, endMHz: 616),
        .init(id: "shure-k51",  manufacturer: "Shure ULXD", name: "K51",  startMHz: 606, endMHz: 670),
        .init(id: "shure-l50",  manufacturer: "Shure ULXD", name: "L50",  startMHz: 632, endMHz: 696),
    ]

    // MARK: - Shure Axient Digital

    static let shureAxientBands: [FrequencyBand] = [
        .init(id: "shure-g57",  manufacturer: "Shure AD", name: "G57",  startMHz: 470, endMHz: 534),
        .init(id: "shure-h54",  manufacturer: "Shure AD", name: "H54",  startMHz: 534, endMHz: 598),
        .init(id: "shure-j52",  manufacturer: "Shure AD", name: "J52",  startMHz: 558, endMHz: 616),
        .init(id: "shure-x52",  manufacturer: "Shure AD", name: "X52",  startMHz: 580, endMHz: 602),
        .init(id: "shure-k53",  manufacturer: "Shure AD", name: "K53",  startMHz: 606, endMHz: 699),
        .init(id: "shure-k58",  manufacturer: "Shure AD", name: "K58",  startMHz: 622, endMHz: 698),
        .init(id: "shure-l57",  manufacturer: "Shure AD", name: "L57",  startMHz: 650, endMHz: 694),
        .init(id: "shure-q53",  manufacturer: "Shure AD", name: "Q53",  startMHz: 470, endMHz: 534),
    ]

    // MARK: - Shure PSM 300

    static let shurePSM300Bands: [FrequencyBand] = [
        .init(id: "shure-psm3-g20",  manufacturer: "Shure PSM 300", name: "G20",  startMHz: 488, endMHz: 512),
        .init(id: "shure-psm3-h20",  manufacturer: "Shure PSM 300", name: "H20",  startMHz: 518, endMHz: 542),
        .init(id: "shure-psm3-j10",  manufacturer: "Shure PSM 300", name: "J10",  startMHz: 584, endMHz: 608),
        .init(id: "shure-psm3-k3e",  manufacturer: "Shure PSM 300", name: "K3E",  startMHz: 606, endMHz: 630),
        .init(id: "shure-psm3-k12",  manufacturer: "Shure PSM 300", name: "K12",  startMHz: 614, endMHz: 638),
        .init(id: "shure-psm3-l19",  manufacturer: "Shure PSM 300", name: "L19",  startMHz: 630, endMHz: 654),
        .init(id: "shure-psm3-s8",   manufacturer: "Shure PSM 300", name: "S8",   startMHz: 823, endMHz: 832),
        .init(id: "shure-psm3-t11",  manufacturer: "Shure PSM 300", name: "T11",  startMHz: 863, endMHz: 865),
    ]

    // MARK: - Shure PSM 900 / 1000

    static let shurePSM900Bands: [FrequencyBand] = [
        .init(id: "shure-psm9-g6",   manufacturer: "Shure PSM 900", name: "G6",   startMHz: 470, endMHz: 506),
        .init(id: "shure-psm9-g7",   manufacturer: "Shure PSM 900", name: "G7",   startMHz: 506, endMHz: 542),
        .init(id: "shure-psm9-g14",  manufacturer: "Shure PSM 900", name: "G14",  startMHz: 554, endMHz: 626),
        .init(id: "shure-psm9-k1",   manufacturer: "Shure PSM 900", name: "K1",   startMHz: 596, endMHz: 668),
        .init(id: "shure-psm9-k2",   manufacturer: "Shure PSM 900", name: "K2",   startMHz: 614, endMHz: 638),
        .init(id: "shure-psm9-l6",   manufacturer: "Shure PSM 900", name: "L6",   startMHz: 656, endMHz: 680),
        .init(id: "shure-psm10-g10", manufacturer: "Shure PSM 1000", name: "G10", startMHz: 470, endMHz: 542),
        .init(id: "shure-psm10-j8a", manufacturer: "Shure PSM 1000", name: "J8A", startMHz: 554, endMHz: 616),
        .init(id: "shure-psm10-k8e", manufacturer: "Shure PSM 1000", name: "K8E", startMHz: 606, endMHz: 694),
        .init(id: "shure-psm10-l8e", manufacturer: "Shure PSM 1000", name: "L8E", startMHz: 626, endMHz: 698),
    ]

    static let allBands: [FrequencyBand] =
        sennheiserBands + shureWirelessBands + shureAxientBands + shurePSM300Bands + shurePSM900Bands

    static var bandGroups: [(title: String, bands: [FrequencyBand])] {
        [
            ("Sennheiser EW G4", sennheiserBands),
            ("Shure ULXD / QLX-D", shureWirelessBands),
            ("Shure Axient Digital", shureAxientBands),
            ("Shure PSM 300", shurePSM300Bands),
            ("Shure PSM 900 / 1000", shurePSM900Bands),
        ]
    }

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
