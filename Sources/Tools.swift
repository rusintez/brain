import Foundation

// Global flag for skipping confirmations (set by --yes flag)
var skipConfirmations = false

// MARK: - Tool Parsing

func parseToolCall(_ response: String) -> (tool: String, args: [String])? {
    guard let toolStart = response.range(of: "<tool>"),
          let toolEnd = response.range(of: "</tool>") else {
        return nil
    }
    
    let tool = String(response[toolStart.upperBound..<toolEnd.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    
    var args: [String] = []
    var searchRange = toolEnd.upperBound..<response.endIndex
    
    while let argStart = response.range(of: "<arg>", range: searchRange),
          let argEnd = response.range(of: "</arg>", range: argStart.upperBound..<response.endIndex) {
        let arg = String(response[argStart.upperBound..<argEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        args.append(arg)
        searchRange = argEnd.upperBound..<response.endIndex
    }
    
    return (tool, args)
}

// MARK: - Tool Execution

func executeTool(_ tool: String, args: [String], skills: [String: LoadedTool]) -> String? {
    switch tool {
    case "read":
        guard let path = args.first else { return "Error: missing path" }
        let expanded = (path as NSString).expandingTildeInPath
        do {
            let content = try String(contentsOfFile: expanded, encoding: .utf8)
            return content
        } catch {
            return "Error: Could not read \(expanded)"
        }
        
    case "write":
        guard args.count >= 2 else { return "Error: need path and content" }
        let path = (args[0] as NSString).expandingTildeInPath
        let content = args[1]
        
        // Confirm if file exists (overwrite protection)
        if FileManager.default.fileExists(atPath: path) && !skipConfirmations {
            fputs("⚠️  OVERWRITE: \(path) exists\n", stderr)
            fputs("Proceed? [y/N] ", stderr)
            guard let response = readLine(), response.lowercased() == "y" else {
                return "Cancelled by user"
            }
        }
        
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return "Wrote \(content.count) chars to \(path)"
        } catch {
            return "Error: Could not write to \(path)"
        }
        
    case "bash":
        guard let cmd = args.first else { return "Error: missing command" }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", cmd]
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.isEmpty ? "(no output)" : output
        } catch {
            return "Error: \(error.localizedDescription)"
        }
        
    case "done":
        return nil // Handled by caller
        
    default:
        // Check skills
        if let skill = skills[tool] {
            var cmd = skill.command
            for (i, argName) in skill.args.enumerated() where i < args.count {
                var argVal = (args[i] as NSString).expandingTildeInPath
                // Normalize unicode spaces (macOS screenshots use U+202F narrow no-break space)
                argVal = argVal.replacingOccurrences(of: " ", with: "*") // regular space -> glob
                argVal = argVal.replacingOccurrences(of: "\u{202F}", with: "*") // narrow no-break space -> glob
                argVal = argVal.replacingOccurrences(of: "\u{00A0}", with: "*") // non-breaking space -> glob
                cmd = cmd.replacingOccurrences(of: "{\(argName)}", with: argVal)
            }
            
            // Safety check for destructive operations
            let destructiveTools = ["rm", "move", "delete"]
            if destructiveTools.contains(tool) && !skipConfirmations {
                fputs("⚠️  \(tool.uppercased()): \(args.joined(separator: " "))\n", stderr)
                fputs("Proceed? [y/N] ", stderr)
                if let response = readLine(), response.lowercased() == "y" {
                    // Continue with execution
                } else {
                    return "Cancelled by user"
                }
            }
            
            let process = Process()
            let stdoutPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", cmd]
            process.standardOutput = stdoutPipe
            process.standardError = FileHandle.nullDevice // discard stderr from subagents
            
            do {
                try process.run()
                process.waitUntilExit()
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                return output.isEmpty ? "(no output)" : output
            } catch {
                return "Error: \(error.localizedDescription)"
            }
        }
        
        return "Unknown tool: \(tool)"
    }
}

// MARK: - Text Cleaning Helpers

func stripThinking(from text: String) -> String {
    var result = text
    while let thinkStart = result.range(of: "<think>"),
          let thinkEnd = result.range(of: "</think>") {
        result.removeSubrange(thinkStart.lowerBound..<thinkEnd.upperBound)
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

func stripToolTags(from text: String) -> String {
    var result = text
    result = result.replacingOccurrences(of: "<tool>done</tool>", with: "")
    result = result.replacingOccurrences(of: "<tool>", with: "")
    result = result.replacingOccurrences(of: "</tool>", with: "")
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

func extractThinking(from response: String) -> String? {
    guard let thinkStart = response.range(of: "<think>"),
          let thinkEnd = response.range(of: "</think>") else {
        return nil
    }
    return String(response[thinkStart.upperBound..<thinkEnd.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
