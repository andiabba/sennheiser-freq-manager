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

    // MARK: - Shure ULXD / QLX-D

    static let shureWirelessBands: [FrequencyBand] = [
        .init(id: "shure-g50",  manufacturer: "Shure ULXD", name: "G50",  startMHz: 470, endMHz: 534),
        .init(id: "shure-h50",  manufacturer: "Shure ULXD", name: "H50",  startMHz: 534, endMHz: 598),
        .init(id: "shure-h51",  manufacturer: "Shure ULXD", name: "H51",  startMHz: 534, endMHz: 598),
        .init(id: "shure-j50",  manufacturer: "Shure ULXD", name: "J50",  startMHz: 572, endMHz: 636),
        .init(id: "shure-j50a", manufacturer: "Shure ULXD", name: "J50A", startMHz: 572, endMHz: 616),
        .init(id: "shure-k51",  manufacturer: "Shure ULXD", name: "K51",  startMHz: 606, endMHz: 670),
        .init(id: "shure-l50",  manufacturer: "Shure ULXD", name: "L50",  startMHz: 632, endMHz: 698),
        .init(id: "shure-v50",  manufacturer: "Shure ULXD", name: "V50",  startMHz: 174, endMHz: 216),
    ]

    // MARK: - Shure SLX-D

    static let shureSLXDBands: [FrequencyBand] = [
        .init(id: "shure-g58",  manufacturer: "Shure SLX-D", name: "G58",  startMHz: 470, endMHz: 514),
        .init(id: "shure-g59",  manufacturer: "Shure SLX-D", name: "G59",  startMHz: 470, endMHz: 514),
        .init(id: "shure-h55",  manufacturer: "Shure SLX-D", name: "H55",  startMHz: 514, endMHz: 558),
        .init(id: "shure-h56",  manufacturer: "Shure SLX-D", name: "H56",  startMHz: 518, endMHz: 562),
        .init(id: "shure-j52",  manufacturer: "Shure SLX-D", name: "J52",  startMHz: 558, endMHz: 616),
        .init(id: "shure-j53",  manufacturer: "Shure SLX-D", name: "J53",  startMHz: 562, endMHz: 606),
        .init(id: "shure-l58",  manufacturer: "Shure SLX-D", name: "L58",  startMHz: 630, endMHz: 674),
        .init(id: "shure-l59",  manufacturer: "Shure SLX-D", name: "L59",  startMHz: 654, endMHz: 698),
        .init(id: "shure-s50",  manufacturer: "Shure SLX-D", name: "S50",  startMHz: 823, endMHz: 865),
    ]

    // MARK: - Shure BLX

    static let shureBLXBands: [FrequencyBand] = [
        .init(id: "shure-h8",   manufacturer: "Shure BLX", name: "H8",   startMHz: 518, endMHz: 542),
        .init(id: "shure-h9",   manufacturer: "Shure BLX", name: "H9",   startMHz: 512, endMHz: 542),
        .init(id: "shure-h10",  manufacturer: "Shure BLX", name: "H10",  startMHz: 542, endMHz: 572),
        .init(id: "shure-h11",  manufacturer: "Shure BLX", name: "H11",  startMHz: 572, endMHz: 596),
        .init(id: "shure-j10",  manufacturer: "Shure BLX", name: "J10",  startMHz: 584, endMHz: 608),
        .init(id: "shure-j11",  manufacturer: "Shure BLX", name: "J11",  startMHz: 596, endMHz: 616),
        .init(id: "shure-blx-k3e", manufacturer: "Shure BLX", name: "K3E", startMHz: 606, endMHz: 630),
        .init(id: "shure-blx-k12", manufacturer: "Shure BLX", name: "K12", startMHz: 614, endMHz: 638),
        .init(id: "shure-k14",  manufacturer: "Shure BLX", name: "K14",  startMHz: 614, endMHz: 638),
        .init(id: "shure-m17",  manufacturer: "Shure BLX", name: "M17",  startMHz: 662, endMHz: 686),
        .init(id: "shure-blx-s8", manufacturer: "Shure BLX", name: "S8", startMHz: 823, endMHz: 832),
        .init(id: "shure-blx-t11", manufacturer: "Shure BLX", name: "T11", startMHz: 863, endMHz: 865),
    ]

    // MARK: - Shure Axient Digital

    static let shureAxientBands: [FrequencyBand] = [
        .init(id: "shure-g53",  manufacturer: "Shure AD", name: "G53",  startMHz: 470, endMHz: 510),
        .init(id: "shure-g54",  manufacturer: "Shure AD", name: "G54",  startMHz: 479, endMHz: 565),
        .init(id: "shure-g55",  manufacturer: "Shure AD", name: "G55",  startMHz: 470, endMHz: 636),
        .init(id: "shure-g56",  manufacturer: "Shure AD", name: "G56",  startMHz: 470, endMHz: 636),
        .init(id: "shure-g57",  manufacturer: "Shure AD", name: "G57",  startMHz: 470, endMHz: 616),
        .init(id: "shure-g62",  manufacturer: "Shure AD", name: "G62",  startMHz: 510, endMHz: 530),
        .init(id: "shure-h54",  manufacturer: "Shure AD", name: "H54",  startMHz: 520, endMHz: 636),
        .init(id: "shure-k53",  manufacturer: "Shure AD", name: "K53",  startMHz: 606, endMHz: 698),
        .init(id: "shure-k54",  manufacturer: "Shure AD", name: "K54",  startMHz: 606, endMHz: 663),
        .init(id: "shure-k55",  manufacturer: "Shure AD", name: "K55",  startMHz: 606, endMHz: 694),
        .init(id: "shure-k56",  manufacturer: "Shure AD", name: "K56",  startMHz: 606, endMHz: 714),
        .init(id: "shure-k57",  manufacturer: "Shure AD", name: "K57",  startMHz: 606, endMHz: 790),
        .init(id: "shure-k58",  manufacturer: "Shure AD", name: "K58",  startMHz: 622, endMHz: 698),
        .init(id: "shure-l54",  manufacturer: "Shure AD", name: "L54",  startMHz: 630, endMHz: 787),
        .init(id: "shure-l57",  manufacturer: "Shure AD", name: "L57",  startMHz: 650, endMHz: 694),
    ]

    // MARK: - Shure PSM 300

    static let shurePSM300Bands: [FrequencyBand] = [
        .init(id: "shure-psm3-g20",  manufacturer: "Shure PSM 300", name: "G20",  startMHz: 488, endMHz: 512),
        .init(id: "shure-psm3-h20",  manufacturer: "Shure PSM 300", name: "H20",  startMHz: 518, endMHz: 542),
        .init(id: "shure-psm3-j13",  manufacturer: "Shure PSM 300", name: "J13",  startMHz: 566, endMHz: 590),
        .init(id: "shure-psm3-j10",  manufacturer: "Shure PSM 300", name: "J10",  startMHz: 584, endMHz: 608),
        .init(id: "shure-psm3-k3e",  manufacturer: "Shure PSM 300", name: "K3E",  startMHz: 606, endMHz: 630),
        .init(id: "shure-psm3-k12",  manufacturer: "Shure PSM 300", name: "K12",  startMHz: 614, endMHz: 638),
        .init(id: "shure-psm3-l19",  manufacturer: "Shure PSM 300", name: "L19",  startMHz: 630, endMHz: 654),
        .init(id: "shure-psm3-s8",   manufacturer: "Shure PSM 300", name: "S8",   startMHz: 823, endMHz: 832),
        .init(id: "shure-psm3-t11",  manufacturer: "Shure PSM 300", name: "T11",  startMHz: 863, endMHz: 865),
    ]

    // MARK: - Shure PSM 900 / 1000

    static let shurePSM900Bands: [FrequencyBand] = [
        .init(id: "shure-psm9-g6",   manufacturer: "Shure PSM 900",  name: "G6",   startMHz: 470, endMHz: 506),
        .init(id: "shure-psm9-g7",   manufacturer: "Shure PSM 900",  name: "G7",   startMHz: 506, endMHz: 542),
        .init(id: "shure-psm9-g14",  manufacturer: "Shure PSM 900",  name: "G14",  startMHz: 554, endMHz: 626),
        .init(id: "shure-psm9-k1",   manufacturer: "Shure PSM 900",  name: "K1",   startMHz: 596, endMHz: 668),
        .init(id: "shure-psm9-k2",   manufacturer: "Shure PSM 900",  name: "K2",   startMHz: 614, endMHz: 638),
        .init(id: "shure-psm9-l6",   manufacturer: "Shure PSM 900",  name: "L6",   startMHz: 656, endMHz: 680),
        .init(id: "shure-psm10-g10", manufacturer: "Shure PSM 1000", name: "G10",  startMHz: 470, endMHz: 542),
        .init(id: "shure-psm10-j8a", manufacturer: "Shure PSM 1000", name: "J8A",  startMHz: 554, endMHz: 616),
        .init(id: "shure-psm10-k8e", manufacturer: "Shure PSM 1000", name: "K8E",  startMHz: 606, endMHz: 694),
        .init(id: "shure-psm10-l8e", manufacturer: "Shure PSM 1000", name: "L8E",  startMHz: 626, endMHz: 698),
    ]

    static let allBands: [FrequencyBand] =
        sennheiserBands + shureWirelessBands + shureSLXDBands + shureBLXBands
        + shureAxientBands + shurePSM300Bands + shurePSM900Bands

    static var bandGroups: [(title: String, bands: [FrequencyBand])] {
        [
            ("Sennheiser EW G4", sennheiserBands),
            ("Shure ULXD / QLX-D", shureWirelessBands),
            ("Shure SLX-D", shureSLXDBands),
            ("Shure BLX", shureBLXBands),
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
