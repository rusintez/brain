# Brain Roadmap

## Current State (v0.1.2)

**Eval Results: 20% pass rate (2/10 tests)**

| Difficulty | Pass Rate |
|------------|-----------|
| Low        | 25% (1/4) |
| Mid        | 25% (1/4) |
| High       | 0% (0/2)  |

### Critical Issues Identified

1. **`ls()` called without arguments** - model ignores "ALWAYS pass arguments" instruction
2. **Wrong tool selection** - uses `today()` instead of `bash("date")`, `ls` instead of `grep`
3. **Hallucination** - fabricates answers (48 files when there are 4)
4. **grep/peek tools ignored** - model doesn't use new investigation tools
5. **JSON skill format too complex** - small models struggle with structure

---

## Research Findings

### Model Selection (from benchmarks)

| Model | Tool Calling Score | Recommendation |
|-------|-------------------|----------------|
| Qwen3-0.6B | 0.880 (#1 tie) | **Best for simple tasks** |
| Qwen3-4B | 0.880 (#1 tie) | Best overall |
| Qwen3-1.7B | 0.670 | **AVOID** - "capability valley" |

**Key insight**: Rankings are non-monotonic. 0.6B > 4B > 1.7B. The 1.7B is large enough to be aggressive about calling tools, but not large enough to know when to decline.

### Tool Definition Format

**Current: JSON schema** - token-heavy, confusing for small models

**Recommended: Natural Language Tools (NLT)**
- +18.4% accuracy improvement over JSON
- 70% reduction in output variance  
- 31% fewer tokens

**Example transformation:**
```
# BEFORE (JSON)
{
  "name": "ls",
  "description": "List files in a directory",
  "command": "ls -la {path}",
  "args": ["path"]
}

# AFTER (Plain text)
ls <path> - List files in a directory (use . for current dir)
Example: ls .
```

### Prompting Best Practices

1. **Provide explicit examples** - few-shot dramatically improves performance
2. **Separate concerns** - don't ask model to think + select tools + format output simultaneously
3. **Use flat output format** - `TOOL: name / ARG: value` instead of nested JSON
4. **Temperature 0.6-0.7** - never use 0.0, causes repetition loops
5. **Thinking mode** - enable for complex tasks, disable for simple tool calls

### Code Mode (Cloudflare Approach)

From [Cloudflare's Code Mode MCP](https://blog.cloudflare.com/code-mode-mcp/):

Instead of defining many tools with JSON schemas, expose just 2 tools:
- `search()` - discover capabilities via code
- `execute()` - run code to accomplish tasks

**Key insight**: Let the model write code (TypeScript/JS) to call functions directly:

```javascript
// Instead of: TOOL: ls, ARG: .
// Model writes:
await fs.readdir(".")

// Instead of: TOOL: grep, ARG: pattern, ARG: path  
// Model writes:
await exec(`rg "${pattern}" ${path}`)
```

**Benefits:**
- 99.9% token reduction vs full tool schemas
- Model can chain operations in one call
- Code is naturally compositional
- Works with coder models' training

**For brain:** Could expose shell as typed SDK:
```typescript
const shell = {
  ls: (path: string) => string[],
  cat: (path: string) => string,
  grep: (pattern: string, path: string) => string[],
  write: (path: string, content: string) => void,
}
```

### Qwen2.5-Coder Models

**Alternative to Qwen3 base models** - specialized for code tasks.

| Model | Size | Notes |
|-------|------|-------|
| Qwen2.5-Coder-0.5B | 500MB | Smallest, trained on 5.5T code tokens |
| Qwen2.5-Coder-1.5B | 1.5GB | Good balance |
| Qwen2.5-Coder-7B | 7GB | Best quality |

**Why consider:**
- Trained specifically on code (5.5T tokens of source code)
- Better at JSON parsing, bash commands, structured output
- May handle tool-calling format better than base models
- Same architecture, easy to swap

**Trade-off:** May be worse at general conversation/reasoning.

---

## Roadmap

### Phase 1: Fix Critical Issues (v0.2.0)

- [ ] **P0: Rewrite skill format to plain text**
  ```
  # ~/.config/brain/skills/files.txt
  
  ls <path> - List files (use . for current directory)
  Example: ls .
  
  cat <path> - Show file contents
  Example: cat README.md
  
  grep <pattern> <path> - Search for text in files
  Example: grep "TODO" src/
  ```

- [ ] **P0: Add built-in Unix tools**
  - `ls`, `cat`, `grep`, `cd`, `pwd`, `mkdir`, `touch`, `cp`, `mv`, `rm`
  - These should be native, not skills

- [ ] **P0: Improve system prompt with examples**
  ```
  When user asks to list files:
  TOOL: ls
  ARG: .
  
  When user asks for today's date:
  TOOL: bash
  ARG: date
  ```

- [ ] **P1: Default `ls` argument to "."** - handle missing args gracefully

- [ ] **P1: Add retry logic** - on malformed output, retry once with "Please format as TOOL: name / ARG: value"

### Phase 2: Improve Reliability (v0.3.0)

- [ ] **Structured output parser** - extract TOOL/ARG from response more robustly
- [ ] **Tool validation** - check if tool exists before "executing" hallucinated tools
- [ ] **Context window management** - truncate old tool results to preserve context
- [ ] **Error recovery** - when tool fails, suggest alternatives

### Phase 3: Advanced Features (v0.4.0)

- [ ] **Subagent delegation** - use 0.6B for simple tasks, escalate to 4B/R1 for complex
- [ ] **Man page integration** - `man <tool>` via subagent for help
- [ ] **Memory/scratchpad** - persist findings across turns
- [ ] **Confidence scoring** - detect when model is uncertain

### Phase 4: Code Mode (v0.5.0)

- [ ] **Experiment with code-style tool calling**
  ```
  // Instead of TOOL: ls, ARG: .
  shell.ls(".")
  
  // Instead of TOOL: grep, ARG: TODO, ARG: src/
  shell.grep("TODO", "src/")
  ```

- [ ] **Try Qwen2.5-Coder models**
  - Test Qwen2.5-Coder-0.5B vs Qwen3-0.6B on eval suite
  - Coder models may handle structured output better

- [ ] **Implement simple code executor**
  - Parse function calls from output
  - Map to shell commands
  - Sandboxed execution

### Phase 5: Fine-tuning (v0.6.0)

- [ ] **Create training dataset** from eval successes/failures
- [ ] **Fine-tune 0.6B** on tool-calling patterns
- [ ] **Benchmark against base model**

---

## Eval Targets

| Version | Target Pass Rate |
|---------|-----------------|
| v0.1.2 (current) | 20% |
| v0.2.0 | 60% |
| v0.3.0 | 80% |
| v0.4.0 | 90% |

---

## Key Decisions

### Use 0.6B as default (keep)
Despite intuition, 0.6B ties for #1 on tool-calling benchmarks. It's fast and capable for simple tasks.

### Avoid 1.7B for tool calling
It's in a "capability valley" - over-calls tools without judgment.

### Switch from JSON to plain text skills
Research shows +18% accuracy with natural language tool definitions.

### Keep thinking enabled but short
The `/no_think` directive helps but model still outputs `<think>` tags. Focus on keeping thinking brief via prompt.

---

## Open Questions

1. Should skills be defined in the binary or loaded from files?
2. How to handle multi-arg tools in plain text format?
3. Should we implement a ReAct-style loop or keep current approach?
4. Is fine-tuning worth the effort vs better prompting?
5. **Code mode vs TOOL/ARG format** - which is more natural for small models?
6. **Qwen3 vs Qwen2.5-Coder** - is code specialization worth the trade-off?
7. **man page integration** - too much context or useful for discovery?

---

## Ideas to Explore

### Minimal Tool Syntax

Current verbose format:
```
<tool>ls</tool>
<arg>.</arg>
```

Possible alternatives:
```
# Code style (like Cloudflare)
shell.ls(".")

# Bash style  
$ ls .

# Function call style
ls(".")

# Markdown code block
```bash
ls .
```
```

### Basic Unix Commands as First-Class Tools

Focus eval on these core commands:
- `ls` / `ls -la` / `ls -a` - list files
- `cd` / `cd ..` / `cd ~` - change directory  
- `pwd` - print working directory
- `cat` - show file contents
- `grep` - search patterns
- `mkdir` / `touch` - create dirs/files
- `cp` / `mv` / `rm` - file operations

These are what users actually need 90% of the time.

---

## References

- [Qwen3 Function Calling Docs](https://qwen.readthedocs.io/en/stable/framework/function_call.html)
- [Natural Language Tools Paper](https://arxiv.org/abs/2401.12031) - +18% accuracy
- [Local Agent Bench](https://github.com/MikeVeerman/tool-calling-benchmark) - model rankings
- [r/LocalLLaMA](https://reddit.com/r/LocalLLaMA) - community findings
- [Cloudflare Code Mode](https://blog.cloudflare.com/code-mode-mcp/) - 99.9% token reduction
- [Qwen2.5-Coder](https://huggingface.co/Qwen/Qwen2.5-Coder-0.5B) - code-specialized models
