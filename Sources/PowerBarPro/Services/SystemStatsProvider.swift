import Foundation
import Darwin

/// Lightweight system stats read directly via syscalls — no subprocesses.
/// Each call costs microseconds; safe to invoke per UI render tick.
struct SystemStats {
    let swapUsedBytes: UInt64
    let swapTotalBytes: UInt64
    let diskFreeBytes: Int64
    let diskTotalBytes: Int64
    let loadAvg1: Double
}

enum SystemStatsProvider {

    static func current() -> SystemStats {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &xsw, &size, nil, 0)

        var diskTotal: Int64 = 0
        var diskFree: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            diskTotal = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            diskFree = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }

        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)

        return SystemStats(
            swapUsedBytes: xsw.xsu_used,
            swapTotalBytes: xsw.xsu_total,
            diskFreeBytes: diskFree,
            diskTotalBytes: diskTotal,
            loadAvg1: loads[0]
        )
    }
}
