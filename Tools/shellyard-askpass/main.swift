//
//  main.swift
//  shellyard-askpass
//
//  OpenSSH runs this program whenever it needs a password, a passphrase, or an
//  answer about a host key. The prompt arrives as the first argument. The
//  answer goes to standard output. A non-zero exit means "cancelled".
//
//  The program holds no secret of its own. It asks Shellyard over a Unix socket
//  and prints what Shellyard sends back. Shellyard points it at the socket with
//  two environment variables:
//
//      SHELLYARD_AUTH_SOCK   the socket path
//      SHELLYARD_SESSION     a random token for one connection attempt
//
//  A secret therefore never appears in a command line, in the environment, or
//  in a file. The protocol lives in AskpassClient.swift, which this target
//  compiles together with this file.
//

import Foundation

let prompt = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let environment = ProcessInfo.processInfo.environment

guard let socketPath = environment["SHELLYARD_AUTH_SOCK"],
      let token = environment["SHELLYARD_SESSION"],
      let answer = AskpassClient.ask(socketPath: socketPath, token: token, prompt: prompt)
else {
    exit(1)
}

FileHandle.standardOutput.write(Data((answer + "\n").utf8))
exit(0)
