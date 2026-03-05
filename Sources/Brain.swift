import ArgumentParser
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Darwin

// MARK: - Main CLI

@main
struct Brain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "brain",
        abstract: "Local LLM agent with tools - runs 100% on device"
    )
    
    @Argument(help: "Prompt")
    var prompt: String?
    
    @Option(name: .shortAndLong, help: "Input file")
    var input: String?
    
    @Option(name: .shortAndLong, help: "Model: 0.6b, 1.7b, 4b, r1 (reasoning), q2-*")
    var model: String = "0.6b"
    
    @Option(name: .shortAndLong, help: "Max tokens per turn")
    var tokens: Int = 2000
    
    @Option(name: .long, help: "Max agent turns")
    var maxTurns: Int = 10
    
    @Flag(name: .shortAndLong, help: "Simple mode (no tools)")
    var simple: Bool = false
    
    @Flag(name: .shortAndLong, help: "Verbose - show tool calls")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "List models")
    var listModels: Bool = false
    
    @Flag(name: .long, help: "List available skills/tools")
    var listSkills: Bool = false
    
    @Flag(name: .long, help: "Force online mode (skip local cache)")
    var online: Bool = false
    
    @Flag(name: .shortAndLong, help: "Skip confirmation prompts (dangerous)")
    var yes: Bool = false
    
    func run() async throws {
        // Set global flag for tool confirmations
        skipConfirmations = yes
        let skills = loadSkills()
        
        if listModels {
            print("Models:")
            for (name, path) in availableModels.sorted(by: { $0.key < $1.key }) {
                print("  \(name): \(path)")
            }
            return
        }
        
        if listSkills {
            print("Built-in tools:")
            print("  read: Read file contents")
            print("  write: Write to file")
            print("  bash: Run shell command")
            print("  done: Final response")
            
            print("\nSkill tools:")
            for (name, tool) in skills.sorted(by: { $0.key < $1.key }) {
                print("  \(name): \(tool.description)")
            }
            return
        }
        
        guard let userPrompt = prompt else {
            print("Usage: brain \"your prompt\"")
            print("       brain \"summarize\" -i file.txt")
            print("       brain --list-skills")
            return
        }
        
        guard let modelId = availableModels[model] else {
            fputs("Unknown model: \(model)\n", stderr)
            return
        }
        
        // Build prompt with optional input file
        var fullPrompt = userPrompt
        if let inputPath = input {
            let path = (inputPath as NSString).expandingTildeInPath
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                fullPrompt += "\n\n---\nINPUT:\n\(content)"
            }
        }
        
        // Load model
        let config = resolveModelPath(modelId, forceOnline: online)
        if verbose {
            fputs("┌─ brain [\(model)]\n", stderr)
        }
        let container = try await LLMModelFactory.shared.loadContainer(configuration: config)
        
        if simple || input != nil {
            try await generateSimple(container: container, prompt: fullPrompt)
        } else {
            try await runAgent(container: container, prompt: fullPrompt, skills: skills)
        }
    }
    
    // MARK: - Simple Generation (no tools)
    
    func generateSimple(container: ModelContainer, prompt: String) async throws {
        let messages: [[String: String]] = [
            ["role": "user", "content": prompt]
        ]
        
        let maxToks = tokens
        let stream: AsyncStream<Generation> = try await container.perform { context in
            let promptTokens = try context.tokenizer.applyChatTemplate(messages: messages)
            let input = LMInput(tokens: MLXArray(promptTokens))
            let params = GenerateParameters(maxTokens: maxToks)
            return try MLXLMCommon.generate(input: input, parameters: params, context: context)
        }
        
        for await generation in stream {
            if let chunk = generation.chunk {
                print(chunk, terminator: "")
                fflush(stdout)
            }
        }
        print()
    }
    
    // MARK: - Agent Loop
    
    func runAgent(container: ModelContainer, prompt: String, skills: [String: LoadedTool]) async throws {
        let systemPrompt = buildSystemPrompt(skills: skills)
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": prompt]
        ]
        
        for _ in 0..<maxTurns {
            // Generate response
            let maxToks = tokens
            var response = ""
            
            let stream: AsyncStream<Generation> = try await container.perform { context in
                let promptTokens = try context.tokenizer.applyChatTemplate(messages: messages)
                let input = LMInput(tokens: MLXArray(promptTokens))
                let params = GenerateParameters(maxTokens: maxToks)
                return try MLXLMCommon.generate(input: input, parameters: params, context: context)
            }
            
            for await generation in stream {
                if let chunk = generation.chunk {
                    response += chunk
                }
            }
            
            // Extract thinking for verbose display
            let thinking = extractThinking(from: response)
            
            // Strip thinking from response before adding to context
            let cleanResponse = stripThinking(from: response)
            messages.append(["role": "assistant", "content": cleanResponse])
            
            // Parse tool call
            guard let (tool, args) = parseToolCall(cleanResponse) else {
                if verbose {
                    fputs("├─ \(model) responded (no tool)\n", stderr)
                }
                let output = stripToolTags(from: cleanResponse)
                if output.isEmpty {
                    fputs("Error: empty response (may have run out of tokens)\n", stderr)
                    Darwin.exit(1)
                }
                print(output)
                return
            }
            
            if verbose {
                if let t = thinking, !t.isEmpty {
                    let indented = t.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { "│  \($0)" }.joined(separator: "\n")
                    fputs("├─ thinking:\n\(indented)\n", stderr)
                }
                let argsStr = args.map { "\"\($0)\"" }.joined(separator: ", ")
                fputs("├─ \(tool)(\(argsStr))\n", stderr)
            }
            
            if tool == "done" {
                if verbose {
                    fputs("└─ done\n", stderr)
                }
                let output = stripToolTags(from: args.first ?? "")
                print(output)
                return
            }
            
            // Execute tool
            if let result = executeTool(tool, args: args, skills: skills) {
                // Show full result in verbose mode
                if verbose {
                    let indented = result.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { "│  \($0)" }.joined(separator: "\n")
                    fputs("\(indented)\n", stderr)
                }
                
                // Strip thinking from subagent output before adding to context
                let cleanResult = stripThinking(from: result)
                messages.append(["role": "user", "content": "Tool result:\n\(cleanResult)"])
            } else {
                return
            }
        }
        
        fputs("Error: max turns reached without completion\n", stderr)
        Darwin.exit(1)
    }
}
