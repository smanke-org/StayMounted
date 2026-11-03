# StayMounted

Drive the app with `staymounted` (the app binary; `staymounted help`). See `.claude/skills/staymounted/SKILL.md`. Commands live in
`Sources/StayMounted/Agent/AgentCommands.swift`; test them on a Debug build with `APP_STORE=/tmp/<name>`, which starts a test
copy on its own shares and settings that never mounts, unmounts or probes anything (Release builds ignore it).
