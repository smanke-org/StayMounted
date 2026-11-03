import Foundation

// `staymounted <command>` (the app binary under a short name): run it against the running app
// and exit, without starting a second copy. See Agent/AgentCLI.swift.
if let code = AgentCLI.runIfRequested() { exit(code) }

StayMountedApp.main()
