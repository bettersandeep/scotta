import Foundation
import ScottaKit

let usage = """
usage: scotta <command>
  status                         show battery and controller state (JSON)
  limit <10-100>                 set the charge limit
  normal | pause | topup | discharge | calibrate | off
  sailing <0-30>                 drift this many % below the limit before charging again
  heat on|off [maxC]             pause charging above maxC (default 35)
  led system|off|indicate        MagSafe LED behaviour
  sleep on|off                   keep awake while charging up to the limit
  powermode <battery> <adapter>  each one of auto|low|high
  reset                          restore firmware defaults and stop controlling
"""

func fail(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1) }

let args = Array(CommandLine.arguments.dropFirst())
let client = DaemonClient()
let done = DispatchSemaphore(value: 0)

if args.first ?? "status" == "status" {
    client.status { r in
        switch r {
        case .success(let s):
            let e = JSONEncoder()
            e.dateEncodingStrategy = .iso8601
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try! e.encode(s), as: UTF8.self))
        case .failure(let err): fail(err.localizedDescription)
        }
        done.signal()
    }
} else {
    guard let cmd = Command.parse(args) else { fail(usage) }
    client.send(cmd) { err in
        if let err { fail(err) }
        done.signal()
    }
}
if done.wait(timeout: .now() + 10) == .timedOut { fail("daemon did not answer") }
