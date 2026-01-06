#!/bin/bash
# MEV Profit Tracking and Performance Analysis
# Monitors arbitrage opportunities and execution success

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFIT_LOG="${SCRIPT_DIR}/mev-profit.log"
METRICS_LOG="${SCRIPT_DIR}/mev-metrics.log"
CONFIG_FILE="${SCRIPT_DIR}/.env"

# Default configuration
MIN_PROFIT_THRESHOLD=${MIN_PROFIT_THRESHOLD:-0.01}  # ETH
GAS_PRICE_LIMIT=${GAS_PRICE_LIMIT:-50}              # gwei
MAX_SLIPPAGE=${MAX_SLIPPAGE:-0.5}                   # %

# Load configuration if exists
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log_profit() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp,$1" >> "$PROFIT_LOG"
}

log_metrics() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp,$1" >> "$METRICS_LOG"
}

# Function to get current gas price
get_gas_price() {
    local gas_price_wei=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}' \
        http://localhost:8545 2>/dev/null | jq -r '.result // "0x0"')
    
    if [ "$gas_price_wei" != "0x0" ] && [ "$gas_price_wei" != "null" ]; then
        # Convert from wei to gwei using integer arithmetic
        local wei_value=$(printf "%d" "$gas_price_wei" 2>/dev/null || echo "0")
        if [ "$wei_value" -gt 0 ]; then
            local gwei_value=$((wei_value / 1000000000))
            echo "$gwei_value"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# Function to check MEV-Boost status
check_mev_boost_status() {
    local status_response=$(curl -s --max-time 5 http://localhost:18550/eth/v1/builder/status 2>/dev/null || echo "")
    
    if [ -n "$status_response" ]; then
        echo "connected"
    else
        echo "disconnected"
    fi
}

# Function to get block number
get_latest_block() {
    local block_hex=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 2>/dev/null | jq -r '.result // "0x0"')
    
    if [ "$block_hex" != "0x0" ] && [ "$block_hex" != "null" ]; then
        printf "%d" "$block_hex"
    else
        echo "0"
    fi
}

# Function to simulate arbitrage opportunity
simulate_arbitrage() {
    local token_pair=$1
    local exchange1_price=$2
    local exchange2_price=$3
    local amount=$4
    
    # Calculate potential profit (simplified)
    local price_diff=$(echo "scale=6; $exchange2_price - $exchange1_price" | bc -l)
    local profit=$(echo "scale=6; $price_diff * $amount" | bc -l)
    local profit_percentage=$(echo "scale=2; ($profit / ($exchange1_price * $amount)) * 100" | bc -l)
    
    echo "$profit,$profit_percentage"
}

# Function to check transaction pool status
check_txpool_status() {
    local txpool_data=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}' \
        http://localhost:8545 2>/dev/null | jq -r '.result // {}')
    
    if [ "$txpool_data" != "{}" ]; then
        local pending=$(echo "$txpool_data" | jq -r '.pending // "0"')
        local queued=$(echo "$txpool_data" | jq -r '.queued // "0"')
        echo "$pending,$queued"
    else
        echo "0,0"
    fi
}

# Function to monitor DEX prices (mock data for demonstration)
get_dex_prices() {
    # In production, this would connect to actual DEX APIs
    # For now, simulate with mock data
    
    local eth_price_uniswap=$(echo "scale=2; 2000 + $(date +%S) * 0.1" | bc -l)
    local eth_price_sushiswap=$(echo "scale=2; 2000 + $(date +%S) * 0.12" | bc -l)
    local eth_price_1inch=$(echo "scale=2; 2000 + $(date +%S) * 0.08" | bc -l)
    
    echo "WETH/USDC:$eth_price_uniswap:$eth_price_sushiswap:$eth_price_1inch"
}

# Function to calculate MEV opportunity score
calculate_mev_score() {
    local gas_price=$1
    local profit=$2
    local tx_count=$3
    
    # MEV Score = (Profit / Gas Cost) * Transaction Density Factor
    local gas_cost=$(echo "scale=6; $gas_price * 21000 / 1000000000" | bc -l)  # ETH
    local score=0
    
    if (( $(echo "$gas_cost > 0" | bc -l) )); then
        local profit_ratio=$(echo "scale=2; $profit / $gas_cost" | bc -l)
        local density_factor=$(echo "scale=2; 1 + ($tx_count / 1000)" | bc -l)
        score=$(echo "scale=2; $profit_ratio * $density_factor" | bc -l)
    fi
    
    echo "$score"
}

# Main monitoring function
monitor_mev_opportunities() {
    echo -e "${BLUE}=== MEV Profit Tracker Started ===${NC}"
    echo "Monitoring arbitrage opportunities..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        # Get current metrics
        local gas_price=$(get_gas_price)
        local latest_block=$(get_latest_block)
        local mev_boost_status=$(check_mev_boost_status)
        local txpool_info=$(check_txpool_status)
        
        IFS=',' read -r pending_tx queued_tx <<< "$txpool_info"
        
        # Get DEX prices
        local dex_data=$(get_dex_prices)
        IFS=':' read -r pair uniswap_price sushiswap_price oneinch_price <<< "$dex_data"
        
        # Simulate arbitrage opportunities
        local arb_uni_sushi=$(simulate_arbitrage "WETH/USDC" "$uniswap_price" "$sushiswap_price" "1.0")
        local arb_uni_1inch=$(simulate_arbitrage "WETH/USDC" "$uniswap_price" "$oneinch_price" "1.0")
        
        IFS=',' read -r profit1 profit_pct1 <<< "$arb_uni_sushi"
        IFS=',' read -r profit2 profit_pct2 <<< "$arb_uni_1inch"
        
        # Calculate MEV scores
        local mev_score1=$(calculate_mev_score "$gas_price" "$profit1" "$pending_tx")
        local mev_score2=$(calculate_mev_score "$gas_price" "$profit2" "$pending_tx")
        
        # Display current status
        clear
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}                           MEV PROFIT TRACKER v1.0                             ${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        
        # Network Status
        echo -e "${YELLOW}▶ NETWORK STATUS${NC}"
        echo "────────────────────────────────────────────────────────────────────────────────"
        echo -e "Latest Block: #$latest_block"
        echo -e "Gas Price: ${gas_price} gwei"
        echo -e "Pending Transactions: $pending_tx"
        echo -e "Queued Transactions: $queued_tx"
        echo -e "MEV-Boost: $mev_boost_status"
        echo ""
        
        # DEX Prices
        echo -e "${YELLOW}▶ DEX PRICES${NC}"
        echo "────────────────────────────────────────────────────────────────────────────────"
        printf "%-15s %-12s %-12s %-12s\n" "Pair" "Uniswap" "SushiSwap" "1inch"
        echo "────────────────────────────────────────────────────────────────────────────────"
        printf "%-15s $%-11.2f $%-11.2f $%-11.2f\n" "WETH/USDC" "$uniswap_price" "$sushiswap_price" "$oneinch_price"
        echo ""
        
        # Arbitrage Opportunities
        echo -e "${YELLOW}▶ ARBITRAGE OPPORTUNITIES${NC}"
        echo "────────────────────────────────────────────────────────────────────────────────"
        printf "%-20s %-12s %-12s %-12s %-10s\n" "Opportunity" "Profit (ETH)" "Profit %" "MEV Score" "Status"
        echo "────────────────────────────────────────────────────────────────────────────────"
        
        # Color code based on profitability
        local status1="No Trade"
        local color1="$NC"
        if (( $(echo "$profit1 > $MIN_PROFIT_THRESHOLD" | bc -l) )) && (( $(echo "$gas_price < $GAS_PRICE_LIMIT" | bc -l) )); then
            status1="TRADE"
            color1="$GREEN"
        fi
        
        local status2="No Trade"
        local color2="$NC"
        if (( $(echo "$profit2 > $MIN_PROFIT_THRESHOLD" | bc -l) )) && (( $(echo "$gas_price < $GAS_PRICE_LIMIT" | bc -l) )); then
            status2="TRADE"
            color2="$GREEN"
        fi
        
        printf "%-20s ${color1}%-12.6f %-12.2f %-12.2f %-10s${NC}\n" "Uni→Sushi" "$profit1" "$profit_pct1" "$mev_score1" "$status1"
        printf "%-20s ${color2}%-12.6f %-12.2f %-12.2f %-10s${NC}\n" "Uni→1inch" "$profit2" "$profit_pct2" "$mev_score2" "$status2"
        
        echo ""
        
        # 24h Statistics (mock for now)
        echo -e "${YELLOW}▶ 24H STATISTICS${NC}"
        echo "────────────────────────────────────────────────────────────────────────────────"
        echo -e "Total Profit: ${GREEN}0.125 ETH${NC}"
        echo -e "Successful Trades: ${GREEN}12${NC} / 45 attempted (26.7%)"
        echo -e "Average Gas Used: 185,000"
        echo -e "Best Trade: ${GREEN}+0.045 ETH${NC} (UNI→SUSHI)"
        echo ""
        
        # Recommendations
        echo -e "${YELLOW}▶ RECOMMENDATIONS${NC}"
        echo "────────────────────────────────────────────────────────────────────────────────"
        
        if (( $(echo "$gas_price > $GAS_PRICE_LIMIT" | bc -l) )); then
            echo -e "${RED}●${NC} Gas price too high (${gas_price} gwei) - wait for lower fees"
        fi
        
        if [ "$mev_boost_status" = "disconnected" ]; then
            echo -e "${RED}●${NC} MEV-Boost disconnected - reconnect to maximize opportunities"
        fi
        
        if [ "$pending_tx" -gt "1000" ]; then
            echo -e "${YELLOW}●${NC} High network congestion - consider higher gas prices"
        fi
        
        if (( $(echo "$profit1 > $MIN_PROFIT_THRESHOLD" | bc -l) )) || (( $(echo "$profit2 > $MIN_PROFIT_THRESHOLD" | bc -l) )); then
            echo -e "${GREEN}●${NC} Profitable opportunities available - ready to execute"
        else
            echo -e "${BLUE}●${NC} No profitable opportunities at current gas prices"
        fi
        
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
        echo "Next update in 10 seconds... | Logs: $PROFIT_LOG"
        
        # Log metrics
        log_metrics "gas_price,$gas_price,block,$latest_block,pending_tx,$pending_tx,mev_boost,$mev_boost_status"
        log_metrics "arbitrage,uni_sushi,$profit1,$profit_pct1,$mev_score1"
        log_metrics "arbitrage,uni_1inch,$profit2,$profit_pct2,$mev_score2"
        
        # Log profitable opportunities
        if (( $(echo "$profit1 > $MIN_PROFIT_THRESHOLD" | bc -l) )); then
            log_profit "OPPORTUNITY,UNI→SUSHI,$profit1,$profit_pct1,$gas_price,$mev_score1"
        fi
        
        if (( $(echo "$profit2 > $MIN_PROFIT_THRESHOLD" | bc -l) )); then
            log_profit "OPPORTUNITY,UNI→1INCH,$profit2,$profit_pct2,$gas_price,$mev_score2"
        fi
        
        sleep 10
    done
}

# Function to show profit summary
show_profit_summary() {
    echo -e "${BLUE}=== MEV Profit Summary ===${NC}"
    
    if [ -f "$PROFIT_LOG" ]; then
        local total_opportunities=$(grep "OPPORTUNITY" "$PROFIT_LOG" | wc -l)
        local total_profit=$(grep "OPPORTUNITY" "$PROFIT_LOG" | awk -F',' '{sum += $3} END {printf "%.6f", sum}')
        local avg_profit=$(echo "scale=6; $total_profit / $total_opportunities" | bc -l 2>/dev/null || echo "0")
        
        echo "Total Opportunities: $total_opportunities"
        echo "Total Profit: $total_profit ETH"
        echo "Average Profit: $avg_profit ETH"
        echo ""
        echo "Recent opportunities:"
        tail -10 "$PROFIT_LOG"
    else
        echo "No profit data available yet"
    fi
}

# Main script logic
case "${1:-monitor}" in
    "monitor")
        monitor_mev_opportunities
        ;;
    "summary")
        show_profit_summary
        ;;
    "test")
        echo "Testing MEV tracking components..."
        echo "Gas Price: $(get_gas_price) gwei"
        echo "Latest Block: $(get_latest_block)"
        echo "MEV-Boost Status: $(check_mev_boost_status)"
        echo "Transaction Pool: $(check_txpool_status)"
        ;;
    *)
        echo "Usage: $0 {monitor|summary|test}"
        echo "  monitor  - Start real-time MEV monitoring"
        echo "  summary  - Show profit summary"
        echo "  test     - Test connectivity"
        exit 1
        ;;
esac