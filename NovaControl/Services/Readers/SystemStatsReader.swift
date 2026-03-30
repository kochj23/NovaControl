// NovaControl — System Stats Reader
// Written by Jordan Koch
// Reads CPU, RAM, and process data directly via sysctl / mach APIs

import Foundation
import Darwin

actor SystemStatsReader {
    static let shared = SystemStatsReader()

    func fetchStats() -> SystemStats {
        // CPU load via host_cpu_load_info
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        withUnsafeMutablePointer(to: &cpuLoad) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                _ = host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPtr, &count)
            }
        }
        let user   = Double(cpuLoad.cpu_ticks.0)
        let system = Double(cpuLoad.cpu_ticks.1)
        let idle   = Double(cpuLoad.cpu_ticks.2)
        let nice   = Double(cpuLoad.cpu_ticks.3)
        let total  = user + system + idle + nice
        let cpuUser   = total > 0 ? (user / total) * 100.0 : 0
        let cpuSystem = total > 0 ? (system / total) * 100.0 : 0

        // Memory via vm_statistics64
        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { reboundPtr in
                _ = host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &vmCount)
            }
        }
        let pageSize  = Double(vm_page_size)
        let gbDivisor = 1_073_741_824.0
        let usedPages = Double(vmStats.active_count + vmStats.wire_count + vmStats.compressor_page_count)
        let freePages = Double(vmStats.free_count + vmStats.inactive_count)
        let memUsed   = (usedPages * pageSize) / gbDivisor
        let memTotal  = ((usedPages + freePages) * pageSize) / gbDivisor

        // Uptime via sysctl kern.boottime
        var boottime = timeval()
        var btSize = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boottime, &btSize, nil, 0)
        let uptime = Date().timeIntervalSince1970 - Double(boottime.tv_sec)

        return SystemStats(
            cpuUser: cpuUser,
            cpuSystem: cpuSystem,
            memUsedGB: memUsed,
            memTotalGB: memTotal,
            diskReadMBs: 0,
            diskWriteMBs: 0,
            uptime: uptime
        )
    }

    func fetchProcesses() -> [ProcessInfo] {
        let output = runCommand("/bin/ps", args: ["-eo", "pid,pcpu,pmem,comm,user", "-r"])
        let lines = output.components(separatedBy: "\n").dropFirst() // drop header
        return lines.prefix(20).compactMap { line -> ProcessInfo? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let mem = Double(parts[2]) else { return nil }
            let command = String(parts[3])
            let user    = String(parts[4])
            return ProcessInfo(pid: pid, command: command, cpuPercent: cpu, memPercent: mem, user: user)
        }
    }

    private func runCommand(_ cmd: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cmd)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
