#!/bin/bash
# Test Ollama API directly with the same prompt format used by SortAI
# This helps debug timeout issues

# Configuration
OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
MODEL="${MODEL:-llama3.2}"
TIMEOUT="${TIMEOUT:-300}"  # 5 minutes timeout

echo "🔍 Testing Ollama at: $OLLAMA_HOST"
echo "🤖 Model: $MODEL"
echo "⏱️  Timeout: ${TIMEOUT}s"
echo ""

# First, check if Ollama is running
echo "1️⃣ Checking Ollama availability..."
if ! curl -s --connect-timeout 5 "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
    echo "❌ Ollama is not running at $OLLAMA_HOST"
    echo "   Start Ollama with: ollama serve"
    exit 1
fi
echo "✅ Ollama is running"
echo ""

# Check if model is available
echo "2️⃣ Checking if model '$MODEL' is available..."
MODELS=$(curl -s "$OLLAMA_HOST/api/tags" | grep -o "\"name\":\"[^\"]*\"" | grep -o ":\"[^\"]*\"" | tr -d ':\"')
if ! echo "$MODELS" | grep -q "^${MODEL}"; then
    echo "⚠️  Model '$MODEL' not found. Available models:"
    echo "$MODELS" | head -10
    echo ""
    echo "   Pull the model with: ollama pull $MODEL"
fi
echo "✅ Model check complete"
echo ""

# Create the JSON payload (same format as SortAI uses)
PROMPT='You are a file organization expert. Analyze these filenames and create a hierarchical category taxonomy.

TASK: Create a logical folder structure to organize these files based on their names.

RULES:
1. Create categories that are meaningful and practical
2. Use "/" to separate hierarchy levels (e.g., "Work / Projects / 2024")
3. Maximum depth: 5 levels
4. Minimum 2 files per category (group small categories together)
5. Infer content type from filename patterns, extensions, dates, etc.
6. Common top-level categories: Documents, Media, Projects, Personal, Work, Archives
7. Be specific but not overly granular
8. Consider date patterns (2024, Jan, Q1) for time-based organization

FILENAMES TO ANALYZE:
1. card_magic_of_lepaul.pdf
2. 547bf3e9502cf.mp4
3. beyond_reloaded.pdf
4. BEND by Menny Lindenfeld - Explanation.mp4
5. hooked_on_cards.pdf
6. Michael Ammar ETMCM Index.rtf
7. subliminal_influence.pdf
8. tweezers-436.mp4
9. magicians_dream.pdf
10. Reboxed-PlayAll.mp4

Return ONLY valid JSON in this format:
{
    "categories": [
        {
            "path": "Category / Subcategory",
            "description": "Brief description of what goes here",
            "confidence": 0.85,
            "files": ["filename1.ext", "filename2.ext"]
        }
    ],
    "uncategorized": ["hard_to_categorize.file"],
    "reasoning": "Brief explanation of the taxonomy structure"
}'

# Escape the prompt for JSON
ESCAPED_PROMPT=$(echo "$PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

# Build the request body
REQUEST_BODY=$(cat <<EOF
{
    "model": "$MODEL",
    "prompt": $ESCAPED_PROMPT,
    "stream": false,
    "format": "json",
    "options": {
        "temperature": 0.1,
        "num_predict": 4096
    }
}
EOF
)

echo "3️⃣ Sending request to Ollama (this may take a while)..."
echo "   Request size: $(echo "$REQUEST_BODY" | wc -c) bytes"
echo ""

START_TIME=$(date +%s)

# Make the request with timing
RESPONSE=$(curl -s --max-time $TIMEOUT \
    -X POST "$OLLAMA_HOST/api/generate" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY" \
    -w "\n---CURL_TIME---%{time_total}s")

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Extract timing info
CURL_TIME=$(echo "$RESPONSE" | grep "---CURL_TIME---" | sed 's/---CURL_TIME---//')
RESPONSE_BODY=$(echo "$RESPONSE" | grep -v "---CURL_TIME---")

echo ""
echo "========== OLLAMA RESPONSE =========="
echo "$RESPONSE_BODY" | python3 -c "import json,sys; data=json.load(sys.stdin); print(json.dumps(json.loads(data.get('response','{}')), indent=2))" 2>/dev/null || echo "$RESPONSE_BODY"
echo "====================================="
echo ""
echo "⏱️  Total time: ${DURATION}s (curl reported: $CURL_TIME)"

# Check for errors
if echo "$RESPONSE_BODY" | grep -q '"error"'; then
    echo "❌ Ollama returned an error!"
    echo "$RESPONSE_BODY" | python3 -c "import json,sys; data=json.load(sys.stdin); print('Error:', data.get('error','Unknown'))"
fi

