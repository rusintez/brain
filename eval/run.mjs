#!/usr/bin/env node
/**
 * Brain Eval Suite Runner
 * Usage: node eval/run.mjs [--model 0.6b] [--case low-01] [--verbose]
 */

import { spawn } from 'child_process'
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const brainDir = dirname(__dirname)

// Parse args
const args = process.argv.slice(2)
let model = '0.6b'
let singleCase = null
let verbose = false

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--model' || args[i] === '-m') model = args[++i]
  else if (args[i] === '--case' || args[i] === '-c') singleCase = args[++i]
  else if (args[i] === '--verbose' || args[i] === '-v') verbose = true
}

// Load cases
const cases = JSON.parse(readFileSync(join(__dirname, 'cases.json'), 'utf8'))

// Filter cases
let testCases = cases.cases
if (singleCase) {
  testCases = testCases.filter(c => c.id === singleCase)
}

// Setup results
const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
const resultsDir = join(__dirname, 'results')
mkdirSync(resultsDir, { recursive: true })

console.log('========================================')
console.log('Brain Eval Suite')
console.log('========================================')
console.log(`Model: ${model}`)
console.log(`Cases: ${testCases.length}`)
console.log(`Verbose: ${verbose}`)
console.log('----------------------------------------')

// Run brain command
async function runBrain(prompt, maxTurns) {
  return new Promise((resolve) => {
    const args = ['-m', model, '--max-turns', String(maxTurns)]
    if (verbose) args.push('-v')
    args.push(prompt)
    
    const proc = spawn('brain', args, { 
      cwd: brainDir,
      timeout: 120000 
    })
    
    let stdout = ''
    let stderr = ''
    
    proc.stdout.on('data', (data) => stdout += data)
    proc.stderr.on('data', (data) => stderr += data)
    
    proc.on('close', (code) => {
      resolve({
        output: stdout + stderr,
        code,
        turns: (stderr.match(/├─/g) || []).length
      })
    })
    
    proc.on('error', (err) => {
      resolve({ output: err.message, code: 1, turns: 0 })
    })
    
    // Timeout after 120s
    setTimeout(() => {
      proc.kill()
      resolve({ output: 'TIMEOUT', code: 1, turns: 0 })
    }, 120000)
  })
}

// Run setup command
async function runSetup(cmd) {
  if (!cmd) return
  return new Promise((resolve) => {
    const proc = spawn('sh', ['-c', cmd], { cwd: brainDir })
    proc.on('close', resolve)
    proc.on('error', resolve)
  })
}

// Check results
function checkResult(output, expect, brainDir) {
  const issues = []
  
  // Check must_contain (case insensitive)
  for (const keyword of (expect.must_contain || [])) {
    if (!output.toLowerCase().includes(keyword.toLowerCase())) {
      issues.push(`missing: "${keyword}"`)
    }
  }
  
  // Check must_not_contain
  for (const keyword of (expect.must_not_contain || [])) {
    if (output.toLowerCase().includes(keyword.toLowerCase())) {
      issues.push(`should not contain: "${keyword}"`)
    }
  }
  
  // Check verify_file
  if (expect.verify_file) {
    const filePath = join(brainDir, expect.verify_file.path)
    if (!existsSync(filePath)) {
      issues.push(`file not created: ${expect.verify_file.path}`)
    } else if (expect.verify_file.contains) {
      const content = readFileSync(filePath, 'utf8')
      if (!content.includes(expect.verify_file.contains)) {
        issues.push(`file missing content: "${expect.verify_file.contains}"`)
      }
    }
  }
  
  return issues
}

// Main
async function main() {
  const results = []
  let passed = 0
  let failed = 0
  
  for (const tc of testCases) {
    console.log('')
    console.log(`[${tc.id}] (${tc.difficulty}) ${tc.category}`)
    console.log(`  Prompt: ${tc.prompt.slice(0, 60)}${tc.prompt.length > 60 ? '...' : ''}`)
    
    // Setup
    await runSetup(tc.setup)
    
    // Run
    const start = Date.now()
    const { output, turns } = await runBrain(tc.prompt, tc.expect.max_turns || 5)
    const duration = ((Date.now() - start) / 1000).toFixed(1)
    
    // Check
    const issues = checkResult(output, tc.expect, brainDir)
    const status = issues.length === 0 ? 'PASS' : 'FAIL'
    
    if (status === 'PASS') {
      passed++
      console.log(`  Result: ✓ PASS (${duration}s, ${turns} turns)`)
    } else {
      failed++
      console.log(`  Result: ✗ FAIL`)
      issues.forEach(i => console.log(`    - ${i}`))
    }
    
    results.push({
      id: tc.id,
      difficulty: tc.difficulty,
      category: tc.category,
      prompt: tc.prompt,
      status,
      duration: parseFloat(duration),
      turns,
      issues,
      output: verbose ? output : output.slice(0, 500)
    })
  }
  
  // Summary
  const total = passed + failed
  const passRate = total > 0 ? ((passed / total) * 100).toFixed(0) : 0
  
  console.log('')
  console.log('========================================')
  console.log(`Summary: ${passed}/${total} passed (${passRate}%)`)
  console.log('========================================')
  
  // By difficulty
  const byDifficulty = {}
  for (const r of results) {
    byDifficulty[r.difficulty] = byDifficulty[r.difficulty] || { passed: 0, total: 0 }
    byDifficulty[r.difficulty].total++
    if (r.status === 'PASS') byDifficulty[r.difficulty].passed++
  }
  
  for (const [diff, stats] of Object.entries(byDifficulty)) {
    const rate = ((stats.passed / stats.total) * 100).toFixed(0)
    console.log(`  ${diff}: ${stats.passed}/${stats.total} (${rate}%)`)
  }
  
  // Save results
  const report = {
    meta: {
      timestamp,
      model,
      version: cases.meta.version
    },
    summary: {
      total,
      passed,
      failed,
      passRate: `${passRate}%`,
      byDifficulty
    },
    results
  }
  
  const reportPath = join(resultsDir, `run_${timestamp}.json`)
  writeFileSync(reportPath, JSON.stringify(report, null, 2))
  console.log('')
  console.log(`Report saved: ${reportPath}`)
  
  // Also save latest
  writeFileSync(join(resultsDir, 'latest.json'), JSON.stringify(report, null, 2))
  
  return { passed, failed, results }
}

main().catch(console.error)
