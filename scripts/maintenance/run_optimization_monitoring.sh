#!/bin/bash
#
# Geth Optimization Monitoring Suite
# Comprehensive monitoring after performance optimizations
#
# Author: Claude Code MEV Specialist
# Version: 1.0.0
#

set -euo pipefail

# Run both monitoring scripts in parallel
./monitor_optimized_sync.sh &
./performance_metrics.sh &
wait