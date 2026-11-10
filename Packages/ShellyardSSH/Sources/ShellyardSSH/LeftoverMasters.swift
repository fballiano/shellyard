//
//  LeftoverMasters.swift
//  ShellyardSSH
//

import Darwin
import Foundation

/// Control masters and sockets that an earlier run of Shellyard left behind.
///
/// A control master is a process of its own. A normal quit closes every
/// master. When Shellyard is killed instead (a crash, Force Quit, or a UI test
/// that ends), its masters keep running with launchd as their parent, with
/// their connections and tunnels still open. A master that died leaves its
/// socket file, and OpenSSH then refuses to put a new master on that path.
enum LeftoverMasters {
    /// The start of every socket name. `SSHEngine` makes the names.
    static let socketPrefix = "tc-"
    static let socketSuffix = ".sock"

    /// What `clear(in:)` did, for the tests.
    struct Outcome: Equatable, Sendable {
        var closedMasters = 0
        var removedSockets = 0
    }

    /// Closes the masters in `directory` that lost their parent, and removes
    /// the sockets that no master answers.
    ///
    /// A master whose parent still runs belongs to a copy of Shellyard that is
    /// running now, so it is left alone.
    @discardableResult
    static func clear(in directory: URL) async -> Outcome {
        var outcome = Outcome()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []

        for name in names where name.hasPrefix(socketPrefix) && name.hasSuffix(socketSuffix) {
            let path = directory.appendingPathComponent(name).path
            guard isSocket(path) else { continue }

            let check = await ProcessRunner.run(
                SSHCommand.executable, ["-S", path, "-O", "check", "shellyard"], limit: 5
            )
            guard check.succeeded else {
                // No master answers. The file is all that is left.
                if (try? FileManager.default.removeItem(atPath: path)) != nil {
                    outcome.removedSockets += 1
                }
                continue
            }

            guard let pid = masterPID(in: check.errorOutput + check.output),
                  isOrphanedSSH(pid)
            else { continue }

            let exit = await ProcessRunner.run(
                SSHCommand.executable, ["-S", path, "-O", "exit", "shellyard"], limit: 5
            )
            if exit.succeeded { outcome.closedMasters += 1 }
        }
        return outcome
    }

    /// Reads `Master running (pid=12345)`, the answer to `ssh -O check`.
    static func masterPID(in text: String) -> pid_t? {
        guard let start = text.range(of: "pid=") else { return nil }
        let digits = text[start.upperBound...].prefix { $0.isNumber }
        return pid_t(digits)
    }

    /// True when the process is `ssh` and launchd has adopted it, which
    /// happens when the program that started it is gone.
    private static func isOrphanedSSH(_ pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
            return false
        }
        let command = withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return info.kp_eproc.e_ppid == 1 && command == "ssh"
    }

    private static func isSocket(_ path: String) -> Bool {
        let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType
        return type == .typeSocket
    }
}
