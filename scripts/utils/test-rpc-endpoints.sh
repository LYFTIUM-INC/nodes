#!/bin/bash

# Integration test: RPC endpoints functionality
# Tests all blockchain RPC endpoints for proper responses

set -e

TEST_NAME="RPC Endpoints Integration Test"
FAILED_ENDPOINTS=()

echo "🔗 $TEST_NAME"
echo "======================================"

# Test endpoints configuration
declare -A RPC_ENDPOINTS=(
    ["Ethereum"]="http://localhost:8545"
    ["Optimism"]="http://localhost:8547"
    ["Base"]="http://localhost:8548"
    ["Arbitrum"]="http://localhost:8590"
)

# Test methods to verify
TEST_METHODS=(
    "eth_blockNumber"
    "eth_chainId"
    "net_version"
    "web3_clientVersion"
)

# Function to test RPC endpoint
test_rpc_endpoint() {
    local name="$1"
    local endpoint="$2"
    local method="$3"
    
    echo -n "  Testing $name ($method)... "
    
    local response=$(curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[],\"id\":1}" \
        "$endpoint" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo "❌ Connection failed"
        return 1
    fi
    
    if echo "$response" | grep -q '"error"'; then
        echo "❌ RPC error: $(echo "$response" | jq -r '.error.message' 2>/dev/null || echo "Unknown error")"
        return 1
    fi
    
    if echo "$response" | grep -q '"result"'; then
        local result=$(echo "$response" | jq -r '.result' 2>/dev/null || echo "Invalid JSON")
        echo "✅ $result"
        return 0
    else
        echo "❌ No result in response"
        return 1
    fi
}

# Function to test endpoint health
test_endpoint_health() {
    local name="$1"
    local endpoint="$2"
    
    echo "📊 Testing $name health..."
    
    local passed=0
    local total=${#TEST_METHODS[@]}
    
    for method in "${TEST_METHODS[@]}"; do
        if test_rpc_endpoint "$name" "$endpoint" "$method"; then
            ((passed++))
        fi
    done
    
    echo "  Health: $passed/$total methods working"
    
    if [ $passed -eq $total ]; then
        echo "  ✅ $name is fully operational"
        return 0
    elif [ $passed -gt 0 ]; then
        echo "  ⚠️  $name is partially operational"
        return 1
    else
        echo "  ❌ $name is not operational"
        return 2
    fi
}

# Function to test sync status
test_sync_status() {
    local name="$1"
    local endpoint="$2"
    
    echo -n "  Sync status... "
    
    local response=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        "$endpoint" 2>/dev/null)
    
    if echo "$response" | grep -q '"result":false'; then
        echo "✅ Fully synced"
        return 0
    elif echo "$response" | grep -q '"result":{'; then
        echo "⚠️  Still syncing"
        return 1
    else
        echo "❌ Sync status unknown"
        return 2
    fi
}

# Function to test block progression
test_block_progression() {
    local name="$1"
    local endpoint="$2"
    
    echo -n "  Block progression... "
    
    # Get initial block number
    local block1=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$endpoint" 2>/dev/null | jq -r '.result' 2>/dev/null)
    
    if [ "$block1" = "null" ] || [ -z "$block1" ]; then
        echo "❌ Cannot get block number"
        return 1
    fi
    
    # Wait a bit and get new block number
    sleep 2
    
    local block2=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$endpoint" 2>/dev/null | jq -r '.result' 2>/dev/null)
    
    if [ "$block2" = "null" ] || [ -z "$block2" ]; then
        echo "❌ Cannot get second block number"
        return 1
    fi
    
    # Convert hex to decimal for comparison
    local block1_dec=$((block1))\n    local block2_dec=$((block2))\n    \n    if [ $block2_dec -gt $block1_dec ]; then\n        echo \"✅ Blocks progressing ($block1_dec → $block2_dec)\"\n        return 0\n    elif [ $block2_dec -eq $block1_dec ]; then\n        echo \"⚠️  Blocks not progressing (stuck at $block1_dec)\"\n        return 1\n    else\n        echo \"❌ Block number decreased ($block1_dec → $block2_dec)\"\n        return 2\n    fi\n}\n\n# Run comprehensive tests for each endpoint\necho \"\\n🔍 Starting comprehensive RPC tests...\"\necho \"\"\n\ntotal_endpoints=${#RPC_ENDPOINTS[@]}\npassed_endpoints=0\nfailed_endpoints=0\n\nfor chain in \"${!RPC_ENDPOINTS[@]}\"; do\n    endpoint=\"${RPC_ENDPOINTS[$chain]}\"\n    echo \"\\n🔗 Testing $chain ($endpoint)\"\n    echo \"$(printf '%.0s-' {1..50})\"\n    \n    # Test basic health\n    if test_endpoint_health \"$chain\" \"$endpoint\"; then\n        endpoint_status=\"healthy\"\n    else\n        endpoint_status=\"unhealthy\"\n        FAILED_ENDPOINTS+=(\"$chain\")\n    fi\n    \n    # Test sync status\n    test_sync_status \"$chain\" \"$endpoint\"\n    \n    # Test block progression (only if healthy)\n    if [ \"$endpoint_status\" = \"healthy\" ]; then\n        test_block_progression \"$chain\" \"$endpoint\"\n    fi\n    \n    if [ \"$endpoint_status\" = \"healthy\" ]; then\n        ((passed_endpoints++))\n        echo \"  ✅ $chain: PASS\"\n    else\n        ((failed_endpoints++))\n        echo \"  ❌ $chain: FAIL\"\n    fi\ndone\n\n# Performance test\necho \"\\n⚡ Performance Testing\"\necho \"$(printf '%.0s-' {1..50})\"\n\nfor chain in \"${!RPC_ENDPOINTS[@]}\"; do\n    endpoint=\"${RPC_ENDPOINTS[$chain]}\"\n    echo -n \"  $chain response time... \"\n    \n    start_time=$(date +%s.%N)\n    response=$(curl -s -X POST -H \"Content-Type: application/json\" \\\n        --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \\\n        \"$endpoint\" 2>/dev/null)\n    end_time=$(date +%s.%N)\n    \n    if echo \"$response\" | grep -q '\"result\"'; then\n        duration=$(echo \"$end_time - $start_time\" | bc -l)\n        duration_ms=$(echo \"$duration * 1000\" | bc -l | cut -d'.' -f1)\n        \n        if [ \"$duration_ms\" -lt 500 ]; then\n            echo \"✅ ${duration_ms}ms (excellent)\"\n        elif [ \"$duration_ms\" -lt 1000 ]; then\n            echo \"✅ ${duration_ms}ms (good)\"\n        elif [ \"$duration_ms\" -lt 2000 ]; then\n            echo \"⚠️  ${duration_ms}ms (slow)\"\n        else\n            echo \"❌ ${duration_ms}ms (too slow)\"\n        fi\n    else\n        echo \"❌ No response\"\n    fi\ndone\n\n# Final summary\necho \"\\n📊 Test Summary\"\necho \"$(printf '%.0s=' {1..50})\"\necho \"Total endpoints: $total_endpoints\"\necho \"Passed: $passed_endpoints\"\necho \"Failed: $failed_endpoints\"\n\nif [ $failed_endpoints -eq 0 ]; then\n    echo \"\\n✅ All RPC endpoints are working correctly!\"\n    exit 0\nelse\n    echo \"\\n❌ Failed endpoints: ${FAILED_ENDPOINTS[*]}\"\n    echo \"\\n💡 Check the following:\"\n    echo \"   - Service status: systemctl status [service-name]\"\n    echo \"   - Port availability: netstat -tlnp | grep [port]\"\n    echo \"   - Service logs: journalctl -u [service-name] --no-pager\"\n    exit 1\nfi