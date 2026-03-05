import Foundation

// MARK: - Skill System Types

struct SkillTool: Codable {
    let description: String
    let command: String
    let args: [String]?
}

struct Skill: Codable {
    let name: String
    let description: String?
    let tools: [String: SkillTool]
}

struct LoadedTool {
    let name: String
    let description: String
    let command: String
    let args: [String]
}

// MARK: - Skill Loading

func loadSkills() -> [String: LoadedTool] {
    var tools: [String: LoadedTool] = [:]
    let skillsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/brain/skills")
    
    guard let files = try? FileManager.default.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil) else {
        return tools
    }
    
    for file in files where file.pathExtension == "json" {
        guard let data = try? Data(contentsOf: file),
              let skill = try? JSONDecoder().decode(Skill.self, from: data) else {
            continue
        }
        
        for (toolName, toolDef) in skill.tools {
            tools[toolName] = LoadedTool(
                name: toolName,
                description: toolDef.description,
                command: toolDef.command,
                args: toolDef.args ?? []
            )
        }
    }
    
    return tools
}

// MARK: - System Prompt

func buildSystemPrompt(skills: [String: LoadedTool]) -> String {
    var toolLines = [
        "- read <path>: Read file contents",
        "- write <path> <content>: Write to file",
        "- bash <command>: Run shell command",
        "- done <message>: Final response to user",
    ]
    
    for (name, tool) in skills.sorted(by: { $0.key < $1.key }) {
        toolLines.append("- \(name): \(tool.description)")
    }
    
    let cwd = FileManager.default.currentDirectoryPath
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    
    return """
    /no_think
    Fast tool assistant. Call tools, get results, answer.

    cwd: \(cwd)
    home: \(home)

    TOOLS:
    \(toolLines.joined(separator: "\n"))

    FORMAT - always include <arg>:
    <tool>ls</tool>
    <arg>.</arg>

    <tool>done</tool>
    <arg>your answer here</arg>

    RULES:
    - ALWAYS pass arguments to tools
    - Use "." for current directory
    - Max 3 tool calls
    - End with done
    """
}
