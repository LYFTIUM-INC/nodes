#!/bin/bash
#
# Blockchain Sync Verification Command Wrapper
# Implements the /infrastructure:verify_blockchain_sync command functionality
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
NODE_TYPE="all"
NETWORK="mainnet"
VERIFICATION_LEVEL="standard"
ALERT_THRESHOLD="moderate"
OUTPUT_FORMAT="table"
DURATION=10
COMPARE_NODES=true
EXPORT_FILE=""
CONFIG_FILE="/data/blockchain/nodes/sync_verifier.conf"

# Function to display help
show_help() {
    cat << EOF
${CYAN}Blockchain Sync Verification System${NC}

${GREEN}USAGE:${NC}
    $0 [OPTIONS]

${GREEN}OPTIONS:${NC}
    --node-type TYPE          Node type (geth, erigon, nethermind, besu, all) [default: all]
    --network NETWORK         Network (mainnet, sepolia, holesky, all) [default: mainnet]
    --verification-level LEVEL Verification depth (basic, standard, comprehensive, forensic) [default: standard]
    --alert-threshold THRESHOLD Alert sensitivity (conservative, moderate, aggressive) [default: moderate]
    --output-format FORMAT    Output format (json, yaml, table, dashboard) [default: table]
    --duration MINUTES        Monitoring duration in minutes [default: 10]
    --compare-nodes           Compare nodes for consistency [default: true]
    --export FILE             Export results to file
    --config FILE             Configuration file path [default: /data/blockchain/nodes/sync_verifier.conf]
    --quick-check            Perform quick sync status check
    --monitor-integrity       Monitor blockchain integrity
    --analyze-performance     Analyze performance metrics
    --generate-report        Generate comprehensive report
    --help, -h               Show this help message

${GREEN}EXAMPLES:${NC}
    # Basic verification
    $0 --node-type all --network mainnet --verification-level standard

    # Comprehensive analysis with alerts
    $0 --node-type all --network mainnet --duration 60 --alert-threshold moderate

    # Forensic-level verification with node comparison
    $0 --node-type all --network mainnet --compare-nodes --verification-level forensic

    # Specific client verification
    $0 --node-type geth --network mainnet --verification-level comprehensive

    # Real-time integrity monitoring
    $0 --monitor-integrity --network mainnet --duration 30

    # Generate comprehensive report
    $0 --generate-report --networks mainnet sepolia --verification-level comprehensive

    # Quick status check
    $0 --quick-check --network mainnet

${GREEN}VERIFICATION LEVELS:${NC}
    basic        - Basic sync status check
    standard     - Standard verification with peer analysis
    comprehensive- Full verification with performance metrics
    forensic     - Deep analysis with reorganization detection

${GREEN}ALERT THRESHOLDS:${NC}
    conservative - Very sensitive alerts
    moderate     - Balanced alerting
    aggressive   - Only critical alerts

${GREEN}OUTPUT FORMATS:${NC}
    table        - Human-readable table format
    json         - Machine-readable JSON
    yaml         - YAML format
    dashboard    - Real-time dashboard view

EOF
}

# Function to display header
display_header() {
    echo -e "${PURPLE}================================================${NC}"
    echo -e "${PURPLE}🔍 BLOCKCHAIN SYNC VERIFICATION SYSTEM${NC}"
    echo -e "${PURPLE}================================================${NC}"
    echo -e "${BLUE}Node Type: ${NODE_TYPE}${NC}"
    echo -e "${BLUE}Network: ${NETWORK}${NC}"
    echo -e "${BLUE}Verification Level: ${VERIFICATION_LEVEL}${NC}"
    echo -e "${BLUE}Alert Threshold: ${ALERT_THRESHOLD}${NC}"
    echo -e "${BLUE}Output Format: ${OUTPUT_FORMAT}${NC}"
    echo -e "${BLUE}Timestamp: $(date -Iseconds)${NC}"
    echo -e "${PURPLE}================================================${NC}"
}

# Function to check Python dependencies
check_dependencies() {
    local missing_deps=()

    if ! python3 -c "import aiohttp" 2>/dev/null; then
        missing_deps+=("aiohttp")
    fi

    if ! python3 -c "import psutil" 2>/dev/null; then
        missing_deps+=("psutil")
    fi

    if ! python3 -c "import yaml" 2>/dev/null; then
        missing_deps+=("pyyaml")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Missing Python dependencies: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}   Installing with pip...${NC}"
        pip3 install "${missing_deps[@]}" 2>/dev/null || {
            echo -e "${RED}❌ Failed to install dependencies${NC}"
            echo -e "${YELLOW}   Please run: pip3 install ${missing_deps[*]}${NC}"
            exit 1
        }
    fi
}

# Function to run the verification
run_verification() {
    local cmd_args=(
        "--node-type" "$NODE_TYPE"
        "--network" "$NETWORK"
        "--verification-level" "$VERIFICATION_LEVEL"
        "--alert-threshold" "$ALERT_THRESHOLD"
        "--output-format" "$OUTPUT_FORMAT"
        "--duration" "$DURATION"
        "--config" "$CONFIG_FILE"
    )

    if [ "$COMPARE_NODES" = true ]; then
        cmd_args+=("--compare-nodes")
    fi

    if [ -n "$EXPORT_FILE" ]; then
        cmd_args+=("--export" "$EXPORT_FILE")
    fi

    cd /data/blockchain/nodes
    python3 blockchain_sync_command.py "${cmd_args[@]}"
}

# Function to run specialized commands
run_specialized_command() {
    local command_type="$1"
    local cmd_args=(
        "--config" "$CONFIG_FILE"
        "--network" "$NETWORK"
        "--duration" "$DURATION"
        "--verification-level" "$VERIFICATION_LEVEL"
        "--alert-threshold" "$ALERT_THRESHOLD"
        "--output-format" "$OUTPUT_FORMAT"
    )

    case "$command_type" in
        "quick-check")
            cd /data/blockchain/nodes
            python3 blockchain_sync_quick_check.py --network "$NETWORK" --output-format "$OUTPUT_FORMAT"
            ;;
        "monitor-integrity")
            display_header
            cd /data/blockchain/nodes
            python3 blockchain_sync_command.py --monitor-integrity --network "$NETWORK" --duration "$DURATION"
            ;;
        "analyze-performance")
            display_header
            cd /data/blockchain/nodes
            python3 blockchain_sync_command.py --analyze-performance --network "$NETWORK" --duration "$DURATION"
            ;;
        "generate-report")
            local networks=("$NETWORK")
            if [ "$NETWORK" = "all" ]; then
                networks=("mainnet" "sepolia" "holesky")
            fi

            echo -e "${CYAN}📊 Generating Comprehensive Verification Report...${NC}"
            cd /data/blockchain/nodes
            python3 generate_verification_report.py \
                --networks "${networks[@]}" \
                --verification-level "$VERIFICATION_LEVEL" \
                --output-format "$OUTPUT_FORMAT" \
                ${EXPORT_FILE:+--output "$EXPORT_FILE"}
            ;;
    esac
}

# Parse command line arguments
SPECIALIZED_COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --node-type)
            NODE_TYPE="$2"
            shift 2
            ;;
        --network)
            NETWORK="$2"
            shift 2
            ;;
        --verification-level)
            VERIFICATION_LEVEL="$2"
            shift 2
            ;;
        --alert-threshold)
            ALERT_THRESHOLD="$2"
            shift 2
            ;;
        --output-format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --compare-nodes)
            COMPARE_NODES=true
            shift
            ;;
        --no-compare-nodes)
            COMPARE_NODES=false
            shift
            ;;
        --export)
            EXPORT_FILE="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --quick-check)
            SPECIALIZED_COMMAND="quick-check"
            shift
            ;;
        --monitor-integrity)
            SPECIALIZED_COMMAND="monitor-integrity"
            shift
            ;;
        --analyze-performance)
            SPECIALIZED_COMMAND="analyze-performance"
            shift
            ;;
        --generate-report)
            SPECIALIZED_COMMAND="generate-report"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Validate inputs
case $NODE_TYPE in
    geth|erigon|nethermind|besu|all) ;;
    *)
        echo -e "${RED}❌ Invalid node type: $NODE_TYPE${NC}"
        echo "Valid options: geth, erigon, nethermind, besu, all"
        exit 1
        ;;
esac

case $NETWORK in
    mainnet|sepolia|holesky|all) ;;
    *)
        echo -e "${RED}❌ Invalid network: $NETWORK${NC}"
        echo "Valid options: mainnet, sepolia, holesky, all"
        exit 1
        ;;
esac

case $VERIFICATION_LEVEL in
    basic|standard|comprehensive|forensic) ;;
    *)
        echo -e "${RED}❌ Invalid verification level: $VERIFICATION_LEVEL${NC}"
        echo "Valid options: basic, standard, comprehensive, forensic"
        exit 1
        ;;
esac

case $ALERT_THRESHOLD in
    conservative|moderate|aggressive) ;;
    *)
        echo -e "${RED}❌ Invalid alert threshold: $ALERT_THRESHOLD${NC}"
        echo "Valid options: conservative, moderate, aggressive"
        exit 1
        ;;
esac

case $OUTPUT_FORMAT in
    json|yaml|table|dashboard) ;;
    *)
        echo -e "${RED}❌ Invalid output format: $OUTPUT_FORMAT${NC}"
        echo "Valid options: json, yaml, table, dashboard"
        exit 1
        ;;
esac

# Validate duration
if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 1 ]; then
    echo -e "${RED}❌ Duration must be a positive integer (minutes)${NC}"
    exit 1
fi

# Check dependencies
check_dependencies

# Run the appropriate command
if [ -n "$SPECIALIZED_COMMAND" ]; then
    run_specialized_command "$SPECIALIZED_COMMAND"
else
    display_header
    run_verification
fi

exit_code=$?

# Display completion message
if [ $exit_code -eq 0 ]; then
    echo -e "\n${GREEN}✅ Verification completed successfully${NC}"
else
    echo -e "\n${YELLOW}⚠️  Verification completed with issues (exit code: $exit_code)${NC}"
fi

exit $exit_code