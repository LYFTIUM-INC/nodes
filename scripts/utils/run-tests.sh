#!/bin/bash

# Enhanced MEV Infrastructure Testing Framework
# Industry-leading testing suite with comprehensive coverage

set -euo pipefail

# Configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
LOGS_DIR="$TEST_DIR/logs"
REPORTS_DIR="$TEST_DIR/reports"
FIXTURES_DIR="$TEST_DIR/fixtures"

# Performance thresholds
MAX_RESPONSE_TIME_MS=25
MAX_MEMORY_USAGE_PERCENT=80
MIN_COVERAGE_PERCENT=95
MIN_SUCCESS_RATE=98

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create required directories
mkdir -p "$LOGS_DIR" "$REPORTS_DIR"

# Test counters
total_tests=0
passed_tests=0
failed_tests=0
skipped_tests=0
start_time=$(date +%s)

# Logging functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGS_DIR/test-run.log"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOGS_DIR/test-results.log"
}

log_error() {
    echo -e "${RED}❌ $*${NC}" | tee -a "$LOGS_DIR/test-results.log"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOGS_DIR/test-results.log"
}

log_info() {
    echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOGS_DIR/test-results.log"
}

# Enhanced test execution
run_python_tests() {
    local test_type="$1"
    local test_dir="$TEST_DIR/$test_type"
    
    if [ ! -d "$test_dir" ]; then
        log_warning "$test_type tests directory not found"
        return 0
    fi
    
    log "🐍 Running Python $test_type tests..."
    
    # Check if pytest is available
    if ! command -v pytest >/dev/null 2>&1; then
        log_error "pytest not available, installing..."
        pip install pytest pytest-cov pytest-asyncio pytest-benchmark || {
            log_error "Failed to install pytest"
            return 1
        }
    fi
    
    # Set Python path
    export PYTHONPATH="$PROJECT_ROOT:$PYTHONPATH"
    
    # Run tests with coverage and benchmarking
    local pytest_args=(
        "$test_dir"
        "-v"
        "--tb=short"
        "--cov=$PROJECT_ROOT/mev"
        "--cov-report=html:$REPORTS_DIR/coverage-$test_type"
        "--cov-report=xml:$REPORTS_DIR/coverage-$test_type.xml"
        "--benchmark-skip"
        "--junitxml=$REPORTS_DIR/junit-$test_type.xml"
    )
    
    # Add markers based on test type
    case "$test_type" in
        "unit")
            pytest_args+=("-m" "not integration and not slow and not chaos")
            ;;
        "integration")
            pytest_args+=("-m" "integration")
            ;;
        "performance")
            pytest_args+=("-m" "performance")
            pytest_args=(${pytest_args[@]/--benchmark-skip/--benchmark-autosave})
            ;;
        "security")
            pytest_args+=("-m" "security")
            ;;
        "chaos")
            pytest_args+=("-m" "chaos")
            ;;
    esac
    
    local test_start=$(date +%s)
    
    if pytest "${pytest_args[@]}" 2>&1 | tee "$LOGS_DIR/$test_type-tests.log"; then
        local test_duration=$(($(date +%s) - test_start))
        log_success "$test_type tests passed (${test_duration}s)"
        ((passed_tests++))
        return 0
    else
        local test_duration=$(($(date +%s) - test_start))
        log_error "$test_type tests failed (${test_duration}s)"
        ((failed_tests++))
        return 1
    fi
}

# System health checks
check_system_health() {
    log "🏥 Checking system health..."
    
    local health_issues=0
    
    # Check available memory
    if command -v free >/dev/null; then
        local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
        local mem_usage_int=$(echo "$mem_usage" | cut -d'.' -f1)
        
        if [ "$mem_usage_int" -gt $MAX_MEMORY_USAGE_PERCENT ]; then
            log_warning "High memory usage: ${mem_usage}%"
            ((health_issues++))
        else
            log_info "Memory usage: ${mem_usage}%"
        fi
    fi
    
    # Check disk space
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        log_warning "High disk usage: ${disk_usage}%"
        ((health_issues++))
    else
        log_info "Disk usage: ${disk_usage}%"
    fi
    
    # Check load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    local load_ratio=$(echo "scale=2; $load_avg / $cpu_cores" | bc -l)
    
    if (( $(echo "$load_ratio > 2.0" | bc -l) )); then
        log_warning "High system load: $load_avg (ratio: $load_ratio)"
        ((health_issues++))
    else
        log_info "System load: $load_avg (ratio: $load_ratio)"
    fi
    
    return $health_issues
}

# Service availability checks
check_service_availability() {
    log "🔍 Checking service availability..."
    
    local services=(
        "http://localhost:8545/health"    # Ethereum RPC
        "http://localhost:8000/health"    # MEV Backend
        "http://localhost:3000/health"    # Monitoring Dashboard
    )
    
    local service_issues=0
    
    for service in "${services[@]}"; do
        local service_name=$(echo "$service" | sed 's|http://localhost:[0-9]*/||')
        
        if curl -sf "$service" >/dev/null 2>&1; then
            log_info "$service_name: Available"
        else
            log_warning "$service_name: Unavailable ($service)"
            ((service_issues++))
        fi
    done
    
    return $service_issues
}

# Performance benchmarking
run_performance_benchmarks() {
    log "⚡ Running performance benchmarks..."
    
    local benchmark_results="$REPORTS_DIR/benchmark-results.json"
    
    # RPC latency test
    log "Testing RPC latency..."
    local rpc_times=()
    
    for i in {1..10}; do
        local start_time=$(date +%s.%N)
        
        if curl -sf -X POST -H "Content-Type: application/json" \
           --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
           http://localhost:8545 >/dev/null 2>&1; then
            local end_time=$(date +%s.%N)
            local duration=$(echo "($end_time - $start_time) * 1000" | bc -l)
            local duration_int=$(echo "$duration" | cut -d'.' -f1)
            rpc_times+=("$duration_int")
        fi
    done
    
    if [ ${#rpc_times[@]} -gt 0 ]; then
        local avg_latency=$(printf '%s\n' "${rpc_times[@]}" | awk '{sum+=$1} END {print sum/NR}')
        local max_latency=$(printf '%s\n' "${rpc_times[@]}" | sort -n | tail -1)
        
        log_info "RPC Average latency: ${avg_latency}ms"
        log_info "RPC Max latency: ${max_latency}ms"
        
        if (( $(echo "$avg_latency > $MAX_RESPONSE_TIME_MS" | bc -l) )); then
            log_error "RPC latency too high: ${avg_latency}ms (max: ${MAX_RESPONSE_TIME_MS}ms)"
            return 1
        else
            log_success "RPC latency acceptable: ${avg_latency}ms"
        fi
    else
        log_error "Failed to measure RPC latency"
        return 1
    fi
    
    # API throughput test
    log "Testing API throughput..."
    local concurrent_requests=50
    local total_time=0
    local successful_requests=0
    
    for i in $(seq 1 $concurrent_requests); do
        {
            local start_time=$(date +%s.%N)
            if curl -sf http://localhost:8000/api/mev/opportunities >/dev/null 2>&1; then
                local end_time=$(date +%s.%N)
                local duration=$(echo "$end_time - $start_time" | bc -l)
                echo "$duration" >> /tmp/api_times.tmp
                echo "success" >> /tmp/api_results.tmp
            else
                echo "failure" >> /tmp/api_results.tmp
            fi
        } &
    done
    
    wait
    
    if [ -f /tmp/api_times.tmp ]; then
        local avg_api_time=$(awk '{sum+=$1; count++} END {print sum/count}' /tmp/api_times.tmp)
        local success_count=$(grep -c "success" /tmp/api_results.tmp 2>/dev/null || echo 0)
        local total_count=$(wc -l < /tmp/api_results.tmp)
        local success_rate=$(echo "scale=2; $success_count * 100 / $total_count" | bc -l)
        
        log_info "API Success rate: ${success_rate}%"
        log_info "API Average response time: ${avg_api_time}s"
        
        rm -f /tmp/api_times.tmp /tmp/api_results.tmp
        
        if (( $(echo "$success_rate < $MIN_SUCCESS_RATE" | bc -l) )); then
            log_error "API success rate too low: ${success_rate}% (min: ${MIN_SUCCESS_RATE}%)"
            return 1
        else
            log_success "API performance acceptable"
        fi
    else
        log_error "Failed to measure API performance"
        return 1
    fi
    
    return 0
}

# Enhanced test suites
run_unit_tests() {
    log "🧪 Running unit tests..."
    ((total_tests++))
    
    if run_python_tests "unit"; then
        # Additional language-specific unit tests
        
        # OCaml tests
        if [ -d "$PROJECT_ROOT/mev/ocaml" ] && command -v dune >/dev/null 2>&1; then
            log "Running OCaml unit tests..."
            if (cd "$PROJECT_ROOT/mev/ocaml" && dune runtest --display quiet); then
                log_success "OCaml unit tests passed"
            else
                log_error "OCaml unit tests failed"
                ((failed_tests++))
                return 1
            fi
        fi
        
        # JavaScript/Node.js tests
        if [ -f "$PROJECT_ROOT/monitoring/package.json" ]; then
            log "Running JavaScript unit tests..."
            if (cd "$PROJECT_ROOT/monitoring" && npm test 2>/dev/null); then
                log_success "JavaScript unit tests passed"
            else
                log_error "JavaScript unit tests failed"
                ((failed_tests++))
                return 1
            fi
        fi
        
        return 0
    else
        return 1
    fi
}

run_integration_tests() {
    log "🔗 Running integration tests..."
    ((total_tests++))
    
    # Check service availability first
    if ! check_service_availability; then
        log_warning "Some services unavailable, integration tests may fail"
    fi
    
    run_python_tests "integration"
}

run_performance_tests() {
    log "📊 Running performance tests..."
    ((total_tests++))
    
    # System health check
    if ! check_system_health; then
        log_warning "System health issues detected"
    fi
    
    # Performance benchmarks
    if run_performance_benchmarks; then
        # Detailed performance tests
        run_python_tests "performance"
    else
        log_error "Performance benchmarks failed"
        return 1
    fi
}

run_security_tests() {
    log "🛡️  Running security tests..."
    ((total_tests++))
    
    # Static security analysis
    if command -v bandit >/dev/null 2>&1; then
        log "Running Bandit security scan..."
        if bandit -r "$PROJECT_ROOT/mev/" -f json -o "$REPORTS_DIR/bandit-report.json" 2>/dev/null; then
            log_success "Bandit security scan completed"
        else
            log_warning "Bandit security scan found issues"
        fi
    fi
    
    # Dependency vulnerability check
    if command -v safety >/dev/null 2>&1; then
        log "Running Safety dependency scan..."
        if safety check --json --output "$REPORTS_DIR/safety-report.json" 2>/dev/null; then
            log_success "Safety dependency scan passed"
        else
            log_warning "Safety dependency scan found vulnerabilities"
        fi
    fi
    
    run_python_tests "security"
}

run_chaos_tests() {
    log "🌪️  Running chaos engineering tests..."
    ((total_tests++))
    
    log_warning "Chaos tests may cause temporary service disruptions"
    
    run_python_tests "chaos"
}

run_e2e_tests() {
    log "🌐 Running end-to-end tests..."
    ((total_tests++))
    
    # Full system workflow tests
    if [ -f "$TEST_DIR/e2e/test-full-workflow.sh" ]; then
        if "$TEST_DIR/e2e/test-full-workflow.sh"; then
            log_success "E2E workflow tests passed"
        else
            log_error "E2E workflow tests failed"
            ((failed_tests++))
            return 1
        fi
    fi
    
    # UI tests with Playwright (if available)
    if [ -f "$PROJECT_ROOT/monitoring/package.json" ] && grep -q playwright "$PROJECT_ROOT/monitoring/package.json"; then
        log "Running UI end-to-end tests..."
        if (cd "$PROJECT_ROOT/monitoring" && npx playwright test 2>/dev/null); then
            log_success "UI E2E tests passed"
        else
            log_error "UI E2E tests failed"
            ((failed_tests++))
            return 1
        fi
    fi
    
    ((passed_tests++))
    return 0
}

# Enhanced report generation
generate_comprehensive_report() {
    local report_file="$REPORTS_DIR/comprehensive-test-report-$(date +%Y%m%d-%H%M%S).html"
    local success_rate=0
    local duration=$(($(date +%s) - start_time))
    
    if [ $total_tests -gt 0 ]; then
        success_rate=$(echo "scale=1; $passed_tests * 100 / $total_tests" | bc -l)
    fi
    
    # Determine overall status
    local overall_status="FAILED"
    local status_color="#dc3545"
    local status_icon="❌"
    
    if [ $failed_tests -eq 0 ] && (( $(echo "$success_rate >= 95" | bc -l) )); then
        overall_status="PASSED"
        status_color="#28a745"
        status_icon="✅"
    elif [ $failed_tests -eq 0 ]; then
        overall_status="PASSED_WITH_WARNINGS"
        status_color="#ffc107"
        status_icon="⚠️"
    fi
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>MEV Infrastructure Test Report</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f8f9fa; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; border-radius: 12px; margin-bottom: 30px; text-align: center; }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header p { font-size: 1.2em; opacity: 0.9; }
        .status-banner { background: ${status_color}; color: white; padding: 20px; border-radius: 8px; margin-bottom: 30px; text-align: center; font-size: 1.5em; font-weight: bold; }
        .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .metric-card { background: white; padding: 25px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; }
        .metric-value { font-size: 2.5em; font-weight: bold; margin-bottom: 5px; }
        .metric-label { color: #666; font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; }
        .pass { color: #28a745; }
        .fail { color: #dc3545; }
        .warn { color: #ffc107; }
        .section { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 30px; }
        .section h2 { color: #333; margin-bottom: 20px; padding-bottom: 10px; border-bottom: 2px solid #eee; }
        .test-results { display: grid; gap: 15px; }
        .test-result { padding: 15px; border-radius: 6px; border-left: 4px solid #ddd; }
        .test-result.pass { border-left-color: #28a745; background: #f8fff9; }
        .test-result.fail { border-left-color: #dc3545; background: #fff8f8; }
        .test-result.warn { border-left-color: #ffc107; background: #fffbf0; }
        .progress-bar { width: 100%; height: 20px; background: #e9ecef; border-radius: 10px; overflow: hidden; }
        .progress-fill { height: 100%; background: linear-gradient(90deg, #28a745, #20c997); transition: width 0.3s ease; }
        .code-block { background: #f8f9fa; border: 1px solid #e9ecef; border-radius: 4px; padding: 15px; font-family: 'Monaco', 'Menlo', monospace; font-size: 0.9em; overflow-x: auto; }
        .badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-size: 0.8em; font-weight: bold; text-transform: uppercase; }
        .badge.success { background: #28a745; color: white; }
        .badge.warning { background: #ffc107; color: #212529; }
        .badge.danger { background: #dc3545; color: white; }
        .recommendations { background: #e7f3ff; border: 1px solid #b3d7ff; border-radius: 6px; padding: 20px; }
        .recommendations h3 { color: #0056b3; margin-bottom: 15px; }
        .recommendations ul { list-style: none; }
        .recommendations li { margin: 8px 0; padding-left: 20px; position: relative; }
        .recommendations li:before { content: "•"; color: #0056b3; font-weight: bold; position: absolute; left: 0; }
        @media (max-width: 768px) { .metrics-grid { grid-template-columns: repeat(2, 1fr); } .container { padding: 10px; } }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 MEV Infrastructure Test Report</h1>
            <p>Comprehensive testing results for blockchain MEV infrastructure</p>
            <p>Generated: $(date '+%Y-%m-%d %H:%M:%S UTC')</p>
        </div>
        
        <div class="status-banner">
            ${status_icon} Overall Status: ${overall_status}
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-value">$total_tests</div>
                <div class="metric-label">Total Tests</div>
            </div>
            <div class="metric-card">
                <div class="metric-value pass">$passed_tests</div>
                <div class="metric-label">Passed</div>
            </div>
            <div class="metric-card">
                <div class="metric-value fail">$failed_tests</div>
                <div class="metric-label">Failed</div>
            </div>
            <div class="metric-card">
                <div class="metric-value warn">$skipped_tests</div>
                <div class="metric-label">Skipped</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">${success_rate}%</div>
                <div class="metric-label">Success Rate</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">${duration}s</div>
                <div class="metric-label">Duration</div>
            </div>
        </div>
        
        <div class="section">
            <h2>📊 Test Progress</h2>
            <div class="progress-bar">
                <div class="progress-fill" style="width: ${success_rate}%"></div>
            </div>
            <p style="margin-top: 10px; text-align: center; color: #666;">
                Success Rate: ${success_rate}% (Target: ≥95%)
            </p>
        </div>
        
        <div class="section">
            <h2>🔍 Test Results Summary</h2>
            <div class="test-results">
EOF

    # Add test results
    if [ -f "$LOGS_DIR/test-results.log" ]; then
        while IFS= read -r line; do
            local class="warn"
            if [[ "$line" == *"✅"* ]]; then
                class="pass"
            elif [[ "$line" == *"❌"* ]]; then
                class="fail"
            fi
            
            echo "                <div class=\"test-result $class\">$line</div>" >> "$report_file"
        done < "$LOGS_DIR/test-results.log"
    fi
    
    cat >> "$report_file" << EOF
            </div>
        </div>
        
        <div class="section">
            <h2>🎯 Quality Metrics</h2>
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px;">
                <div>
                    <h4>Performance Targets</h4>
                    <ul style="list-style: none; padding: 0;">
                        <li>📡 RPC Latency: &lt;${MAX_RESPONSE_TIME_MS}ms</li>
                        <li>🧠 Memory Usage: &lt;${MAX_MEMORY_USAGE_PERCENT}%</li>
                        <li>📈 Success Rate: ≥${MIN_SUCCESS_RATE}%</li>
                        <li>🎯 Code Coverage: ≥${MIN_COVERAGE_PERCENT}%</li>
                    </ul>
                </div>
                <div>
                    <h4>Security Checks</h4>
                    <ul style="list-style: none; padding: 0;">
                        <li>🔒 Authentication bypass tests</li>
                        <li>💉 Injection attack prevention</li>
                        <li>🛡️ Security headers validation</li>
                        <li>🚦 Rate limiting verification</li>
                    </ul>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>📋 System Information</h2>
            <div class="code-block">
$(uname -a)
$(free -h | head -2)
$(df -h / | tail -1)
Load Average: $(uptime | awk -F'load average:' '{print $2}')
            </div>
        </div>
        
        <div class="section">
            <h2>🔗 Additional Reports</h2>
            <ul>
EOF

    # Add links to additional reports
    for report in "$REPORTS_DIR"/*.xml "$REPORTS_DIR"/*.json "$REPORTS_DIR"/coverage-*; do
        if [ -f "$report" ]; then
            local filename=$(basename "$report")
            echo "                <li><a href=\"$filename\">$filename</a></li>" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF
            </ul>
        </div>
        
        <div class="recommendations">
            <h3>💡 Recommendations</h3>
            <ul>
EOF

    # Generate recommendations based on results
    if [ $failed_tests -gt 0 ]; then
        echo "                <li>🔴 Address failed tests before deployment</li>" >> "$report_file"
    fi
    
    if (( $(echo "$success_rate < 95" | bc -l) )); then
        echo "                <li>📈 Improve test coverage to achieve 95%+ success rate</li>" >> "$report_file"
    fi
    
    if [ $skipped_tests -gt 0 ]; then
        echo "                <li>⚠️ Review and enable skipped tests</li>" >> "$report_file"
    fi
    
    echo "                <li>📊 Monitor system performance metrics continuously</li>" >> "$report_file"
    echo "                <li>🔄 Run comprehensive tests before each deployment</li>" >> "$report_file"
    echo "                <li>📝 Update test cases as new features are added</li>" >> "$report_file"
    
    cat >> "$report_file" << EOF
            </ul>
        </div>
        
        <div style="text-align: center; margin-top: 40px; padding: 20px; color: #666; border-top: 1px solid #eee;">
            <p>MEV Infrastructure Testing Framework v2.0</p>
            <p>Revenue Protection: Preventing \$1000+/minute in lost MEV opportunities</p>
        </div>
    </div>
</body>
</html>
EOF
    
    log "📊 Comprehensive test report generated: $report_file"
}

# Main execution with enhanced orchestration
main() {
    log "🚀 Starting MEV Infrastructure Testing Suite v2.0"
    log "🎯 Target: 99.99% uptime, <25ms latency, 95%+ coverage"
    log ""
    
    # Clean previous logs
    rm -f "$LOGS_DIR"/*.log
    
    # Initial system health check
    if ! check_system_health; then
        log_warning "System health issues detected - tests may be affected"
    fi
    
    # Run test suites based on arguments
    local test_suite="${1:-all}"
    local exit_code=0
    
    case "$test_suite" in
        "unit")
            run_unit_tests || exit_code=1
            ;;
        "integration")
            run_integration_tests || exit_code=1
            ;;
        "performance")
            run_performance_tests || exit_code=1
            ;;
        "security")
            run_security_tests || exit_code=1
            ;;
        "chaos")
            run_chaos_tests || exit_code=1
            ;;
        "e2e")
            run_e2e_tests || exit_code=1
            ;;
        "all"|"comprehensive")
            run_unit_tests || exit_code=1
            run_integration_tests || exit_code=1
            run_performance_tests || exit_code=1
            run_security_tests || exit_code=1
            run_e2e_tests || exit_code=1
            ;;
        "full")
            run_unit_tests || exit_code=1
            run_integration_tests || exit_code=1
            run_performance_tests || exit_code=1
            run_security_tests || exit_code=1
            run_chaos_tests || exit_code=1
            run_e2e_tests || exit_code=1
            ;;
        "quick")
            run_unit_tests || exit_code=1
            run_performance_benchmarks || exit_code=1
            ;;
        "--help"|"-h")
            echo "MEV Infrastructure Testing Framework"
            echo ""
            echo "Usage: $0 [test_suite]"
            echo ""
            echo "Test Suites:"
            echo "  unit         - Unit tests only"
            echo "  integration  - Integration tests"
            echo "  performance  - Performance and benchmarking tests"
            echo "  security     - Security and vulnerability tests"
            echo "  chaos        - Chaos engineering tests"
            echo "  e2e          - End-to-end workflow tests"
            echo "  all          - All tests except chaos (default)"
            echo "  full         - All tests including chaos"
            echo "  quick        - Fast unit tests and basic benchmarks"
            echo ""
            echo "Options:"
            echo "  --help, -h   - Show this help message"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown test suite: $test_suite"
            echo "Use '$0 --help' for available options"
            exit 1
            ;;
    esac
    
    # Generate comprehensive report
    generate_comprehensive_report
    
    # Final summary
    local duration=$(($(date +%s) - start_time))
    local success_rate=0
    
    if [ $total_tests -gt 0 ]; then
        success_rate=$(echo "scale=1; $passed_tests * 100 / $total_tests" | bc -l)
    fi
    
    log ""
    log "📊 Final Test Summary:"
    log "   Test Suite: $test_suite"
    log "   Total Tests: $total_tests"
    log "   Passed: $passed_tests"
    log "   Failed: $failed_tests"
    log "   Skipped: $skipped_tests"
    log "   Success Rate: ${success_rate}%"
    log "   Duration: ${duration}s"
    log ""
    
    if [ $exit_code -eq 0 ] && [ $failed_tests -eq 0 ]; then
        log_success "All tests passed! System ready for production"
        log_success "Revenue protection active - MEV infrastructure validated"
    else
        log_error "$failed_tests test(s) failed - system not ready for production"
        log_error "Potential revenue loss risk - address failures before deployment"
    fi
    
    exit $exit_code
}

# Execute main function with all arguments
main "$@"