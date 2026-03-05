#!/bin/bash
# Brain Eval Suite Runner
# Usage: ./eval/run.sh [--model 0.6b] [--case low-01] [--verbose]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRAIN_DIR="$(dirname "$SCRIPT_DIR")"
CASES_FILE="$SCRIPT_DIR/cases.json"
RESULTS_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$RESULTS_DIR/run_$TIMESTAMP.json"

MODEL="0.6b"
SINGLE_CASE=""
VERBOSE=""

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --model) MODEL="$2"; shift 2 ;;
    --case) SINGLE_CASE="$2"; shift 2 ;;
    --verbose|-v) VERBOSE="-v"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

mkdir -p "$RESULTS_DIR"

echo "========================================"
echo "Brain Eval Suite"
echo "========================================"
echo "Model: $MODEL"
echo "Timestamp: $TIMESTAMP"
echo "Results: $RESULT_FILE"
echo "----------------------------------------"

# Initialize results
cat > "$RESULT_FILE" << EOF
{
  "meta": {
    "timestamp": "$TIMESTAMP",
    "model": "$MODEL",
    "brain_version": "$(brain --help 2>&1 | head -1 || echo 'unknown')"
  },
  "results": [
EOF

cd "$BRAIN_DIR"

# Get case count
if [[ -n "$SINGLE_CASE" ]]; then
  CASES=$(jq -c ".cases[] | select(.id == \"$SINGLE_CASE\")" "$CASES_FILE")
else
  CASES=$(jq -c '.cases[]' "$CASES_FILE")
fi

TOTAL=0
PASSED=0
FAILED=0
FIRST=true

echo "$CASES" | while read -r case_json; do
  TOTAL=$((TOTAL + 1))
  
  id=$(echo "$case_json" | jq -r '.id')
  difficulty=$(echo "$case_json" | jq -r '.difficulty')
  category=$(echo "$case_json" | jq -r '.category')
  prompt=$(echo "$case_json" | jq -r '.prompt')
  setup=$(echo "$case_json" | jq -r '.setup // empty')
  max_turns=$(echo "$case_json" | jq -r '.expect.max_turns // 5')
  must_contain=$(echo "$case_json" | jq -r '.expect.must_contain // []')
  
  echo ""
  echo "[$id] ($difficulty) $category"
  echo "  Prompt: $prompt"
  
  # Run setup if specified
  if [[ -n "$setup" ]]; then
    eval "$setup" 2>/dev/null || true
  fi
  
  # Run brain and capture output
  START_TIME=$(date +%s.%N)
  OUTPUT=$(timeout 120 brain -m "$MODEL" --max-turns "$max_turns" $VERBOSE "$prompt" 2>&1) || true
  END_TIME=$(date +%s.%N)
  DURATION=$(echo "$END_TIME - $START_TIME" | bc)
  
  # Count turns (tool calls)
  TURNS=$(echo "$OUTPUT" | grep -c "├─" || echo "0")
  
  # Check must_contain
  PASS=true
  MISSING=""
  for keyword in $(echo "$must_contain" | jq -r '.[]'); do
    if ! echo "$OUTPUT" | grep -qi "$keyword"; then
      PASS=false
      MISSING="$MISSING $keyword"
    fi
  done
  
  # Check verify_file if specified
  verify_file=$(echo "$case_json" | jq -r '.expect.verify_file.path // empty')
  if [[ -n "$verify_file" ]]; then
    if [[ -f "$verify_file" ]]; then
      verify_contains=$(echo "$case_json" | jq -r '.expect.verify_file.contains // empty')
      if [[ -n "$verify_contains" ]]; then
        if ! grep -q "$verify_contains" "$verify_file"; then
          PASS=false
          MISSING="$MISSING [file content mismatch]"
        fi
      fi
    else
      PASS=false
      MISSING="$MISSING [file not created]"
    fi
  fi
  
  if $PASS; then
    PASSED=$((PASSED + 1))
    STATUS="PASS"
    echo "  Result: ✓ PASS (${DURATION}s, $TURNS turns)"
  else
    FAILED=$((FAILED + 1))
    STATUS="FAIL"
    echo "  Result: ✗ FAIL - missing:$MISSING"
  fi
  
  # Append to results (escape output for JSON)
  OUTPUT_ESCAPED=$(echo "$OUTPUT" | jq -Rs '.')
  
  if ! $FIRST; then
    echo "," >> "$RESULT_FILE"
  fi
  FIRST=false
  
  cat >> "$RESULT_FILE" << EOF
    {
      "id": "$id",
      "difficulty": "$difficulty",
      "category": "$category",
      "status": "$STATUS",
      "duration": $DURATION,
      "turns": $TURNS,
      "missing": "$MISSING",
      "output": $OUTPUT_ESCAPED
    }
EOF
done

# Close JSON
cat >> "$RESULT_FILE" << EOF

  ],
  "summary": {
    "total": $TOTAL,
    "passed": $PASSED,
    "failed": $FAILED,
    "pass_rate": "$(echo "scale=1; $PASSED * 100 / $TOTAL" | bc)%"
  }
}
EOF

echo ""
echo "========================================"
echo "Summary: $PASSED/$TOTAL passed ($(echo "scale=0; $PASSED * 100 / $TOTAL" | bc)%)"
echo "Results saved to: $RESULT_FILE"
echo "========================================"
