#!/usr/bin/env python3
"""
Erigon Issue Diagnosis and Fix Tool
Based on log analysis of critical issues
"""

import subprocess
import json
import time
import sys
from datetime import datetime
from pathlib import Path

def check_system_clock() -> dict:
    """Check system clock synchronization"""
    print("🕐 Checking system clock synchronization...")

    result = {
        'issue_detected': False,
        'details': {},
        'recommendations': []
    }

    try:
        # Check systemd time sync status
        systemd_sync = subprocess.run(
            ['timedatectl', 'status'],
            capture_output=True, text=True, timeout=10
        )

        if 'NTP synchronized: no' in systemd_sync.stdout:
            result['issue_detected'] = True
            result['details']['ntp_sync'] = False
            result['recommendations'].append("Enable NTP synchronization")

        # Check chrony status
        chrony_status = subprocess.run(
            ['chronyc', 'tracking'],
            capture_output=True, text=True, timeout=10
        )

        if chrony_status.returncode == 0:
            lines = chrony_status.stdout.split('\n')
            for line in lines:
                if 'Last offset' in line:
                    offset_str = line.split(':')[-1].strip()
                    if offset_str:
                        result['details']['last_offset'] = offset_str

    except Exception as e:
        print(f"Clock check error: {e}")
        result['issue_detected'] = True
        result['recommendations'].append("Install NTP client")

    return result

def fix_system_clock() -> bool:
    """Fix system clock synchronization"""
    print("🔧 Fixing system clock synchronization...")

    try:
        # Enable and start chrony
        subprocess.run(['systemctl', 'enable', 'chronyd'], check=True, timeout=30)
        subprocess.run(['systemctl', 'start', 'chronyd'], check=True, timeout=30)

        # Force time sync
        subprocess.run(['chronyc', 'burst'], timeout=30)
        subprocess.run(['chronyc', 'makestep'], timeout=30)

        print("✅ System clock sync fixed")
        return True

    except Exception as e:
        print(f"❌ Clock sync fix failed: {e}")
        return False

def check_erigon_memory() -> dict:
    """Check Erigon memory usage from logs"""
    print("💾 Analyzing Erigon memory usage...")

    result = {
        'high_usage': False,
        'rss_gb': 0,
        'recommendations': []
    }

    try:
        # Get recent memory stats from logs
        log_cmd = "sudo journalctl -u erigon --since '1 hour ago' --no-pager | grep 'Rss=' | tail -5"
        memory_logs = subprocess.run(
            log_cmd, shell=True, capture_output=True, text=True, timeout=15
        )

        if memory_logs.stdout.strip():
            for line in memory_logs.stdout.split('\n'):
                if 'Rss=' in line:
                    rss_part = line.split('Rss=')[1].split(' ')[0]
                    if 'GB' in rss_part:
                        rss_gb = float(rss_part.replace('GB', ''))
                        result['rss_gb'] = rss_gb

                        if rss_gb > 15:  # 15GB threshold
                            result['high_usage'] = True
                            result['recommendations'].append(f"Memory usage high: {rss_gb:.1f}GB")
                            result['recommendations'].append("Consider reducing cache or pruning")
                        break

        # Check process memory directly
        ps_cmd = "ps aux | grep erigon | grep -v grep"
        ps_output = subprocess.run(ps_cmd, shell=True, capture_output=True, text=True, timeout=10)

        if ps_output.stdout.strip():
            for line in ps_output.stdout.split('\n'):
                if 'erigon' in line:
                    parts = line.split()
                    if len(parts) > 5:
                        cpu = float(parts[2])
                        mem = float(parts[3])
                        rss_mb = mem / 1024

                        if rss_mb > 15000:  # 15GB threshold
                            result['high_usage'] = True
                            result['rss_gb'] = rss_mb / 1024
                            result['recommendations'].append(f"Process memory: {rss_mb:.0f}MB ({cpu}% CPU)")

    except Exception as e:
        print(f"Memory check error: {e}")
        result['recommendations'].append("Cannot access memory information")

    return result

def check_p2p_connectivity() -> dict:
    """Check P2P connectivity from logs"""
    print("🌐 Analyzing P2P connectivity...")

    result = {
        'low_peers': False,
        'peer_count': 0,
        'recommendations': []
    }

    try:
        # Get recent peer count from logs
        peer_cmd = "sudo journalctl -u erigon --since '1 hour ago' --no-pager | grep 'peers=' | tail -10"
        peer_logs = subprocess.run(
            peer_cmd, shell=True, capture_output=True, text=True, timeout=15
        )

        if peer_logs.stdout.strip():
            peer_counts = []
            for line in peer_logs.stdout.split('\n'):
                if 'peers=' in line:
                    peer_part = line.split('peers=')[1].strip()
                    try:
                        peer_count = int(peer_part)
                        peer_counts.append(peer_count)
                    except:
                        pass

            if peer_counts:
                avg_peers = sum(peer_counts) / len(peer_counts)
                result['peer_count'] = int(avg_peers)

                if avg_peers < 5:
                    result['low_peers'] = True
                    result['recommendations'].append(f"Low peer connectivity: {avg_peers:.1f} average")
                    result['recommendations'].append("Check firewall and DNS")
                    result['recommendations'].append("Verify bootnodes configuration")
                else:
                    print(f"✅ P2P connectivity: {avg_peers:.1f} peers average")

        # Check firewall status
        firewall_check = subprocess.run(
            ['ufw', 'status'], capture_output=True, text=True, timeout=10
        )

        if firewall_check.returncode != 0:
            result['recommendations'].append("Check firewall rules for port 30303")

    except Exception as e:
        print(f"P2P connectivity check error: {e}")
        result['recommendations'].append("Cannot access P2P information")

    return result

def check_rpc_service() -> dict:
    """Check RPC service health"""
    print("🔍 Checking RPC service...")

    result = {
        'unresponsive': True,
        'service_active': False,
        'port_bound': False,
        'recommendations': []
    }

    try:
        # Check service status
        service_status = subprocess.run(
            ['systemctl', 'is-active', 'erigon'],
            capture_output=True, text=True, timeout=10
        )
        result['service_active'] = service_status.stdout.strip() == 'active'

        # Check port binding
        port_check = subprocess.run(
            ['netstat', '-tlnp'], capture_output=True, text=True, timeout=10
        )
        result['port_bound'] = ':8545' in port_check.stdout

        # Test basic HTTP connection
        try:
            import requests
            response = requests.get('http://127.0.0.1:8545', timeout=5)
            result['unresponsive'] = False
        except:
            result['unresponsive'] = True

        # Generate recommendations
        if not result['service_active']:
            result['recommendations'].append("Start Erigon service")
        elif not result['port_bound']:
            result['recommendations'].append("Check if port 8545 is bound")
        elif result['unresponsive']:
            result['recommendations'].append("RPC service unresponsive - may need restart")

        if result['service_active'] and not result['unresponsive']:
            print("✅ RPC service healthy")

    except Exception as e:
        print(f"RPC check error: {e}")
        result['recommendations'].append("Cannot verify RPC service")

    return result

def generate_erigon_config_optimizations() -> str:
    """Generate optimized Erigon configuration"""
    config = f"""# Erigon Optimized Configuration
# Generated: {datetime.now().isoformat()}

# Reduced memory usage
[Database]
CacheSize=2147483648  # 2GB reduced from 4GB
DatabaseURL="file:/data/blockchain/ethereum/erigon.db"
Pruning=true
PruneDistance=10000

# RPC with lower timeout
[RPC]
HTTPHost="0.0.0.0"
HTTPPort=8545
HTTPTimeout=30s
HTTPModules="eth,net,web3,debug"
HTTPVirtualHosts=["*"]

# Network optimization
[Network]
NoDiscoveryV4=false
DiscoveryV5Name="erigon"
ListenAddr=":30303"
MaxPeers=50
BootstrapNodes=[
    "enode://c8bdfec1b4e51c2d0a7f0a4e5a7a6b7c9b3c6f5e4d3c2b1a0987654321fedcba9@1.2.3.4:30303"
]
"""

    return config

def main():
    """Main diagnostic and fix routine"""
    print("🧠 ERIGON COMPREHENSIVE DIAGNOSTICS")
    print("=" * 50)
    print(f"📅 Analysis: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    issues_found = []
    fixes_applied = []

    # Run all diagnostics
    clock_issue = check_system_clock()
    memory_issue = check_erigon_memory()
    p2p_issue = check_p2p_connectivity()
    rpc_issue = check_rpc_service()

    print("\n🔍 DIAGNOSTIC SUMMARY")
    print("-" * 30)

    # Report findings
    if clock_issue['issue_detected']:
        issues_found.append("System clock synchronization")
        print(f"❌ System Clock: Issues detected")
        for rec in clock_issue['recommendations']:
            print(f"   - {rec}")
    else:
        print("✅ System Clock: Synchronized")

    if memory_issue['high_usage']:
        issues_found.append("High memory usage")
        print(f"❌ Memory: High usage ({memory_issue['rss_gb']:.1f}GB)")
        for rec in memory_issue['recommendations']:
            print(f"   - {rec}")
    else:
        print("✅ Memory: Acceptable usage")

    if p2p_issue['low_peers']:
        issues_found.append("Low P2P connectivity")
        print(f"❌ P2P: Low connectivity ({p2p_issue['peer_count']} peers)")
        for rec in p2p_issue['recommendations']:
            print(f"   - {rec}")
    else:
        print("✅ P2P: Good connectivity")

    if rpc_issue['unresponsive']:
        issues_found.append("RPC service issues")
        print("❌ RPC: Unresponsive")
        for rec in rpc_issue['recommendations']:
            print(f"   - {rec}")
    else:
        print("✅ RPC: Responsive")

    # Apply fixes
    if issues_found:
        print(f"\n🔧 APPLYING FIXES")
        print("-" * 30)

        if clock_issue['issue_detected']:
            print("🕐 Fixing system clock...")
            if fix_system_clock():
                fixes_applied.append("System clock synchronized")

        if memory_issue['high_usage']:
            print("💾 Optimizing memory configuration...")
            config = generate_erigon_config_optimizations()
            config_path = "/tmp/erigon-optimized.toml"
            with open(config_path, 'w') as f:
                f.write(config)
            print(f"✅ Optimized config saved to {config_path}")
            fixes_applied.append("Memory optimization configuration generated")

        if rpc_issue['unresponsive']:
            print("🔄 Restarting RPC service...")
            try:
                subprocess.run(['systemctl', 'restart', 'erigon'], timeout=60)
                fixes_applied.append("Erigon service restarted")
                print("✅ Service restart completed")
            except Exception as e:
                print(f"❌ Service restart failed: {e}")

    print(f"\n📊 RESULTS")
    print("-" * 30)
    print(f"Issues detected: {len(issues_found)}")
    print(f"Fixes applied: {len(fixes_applied)}")

    if fixes_applied:
        print("\n🔄 RECOMMENDATIONS:")
        print("-" * 30)
        print("1. Wait 5 minutes for services to stabilize")
        print("2. Check status: python3 quick_sync_check.py")
        print("3. Monitor memory usage: htop")
        print("4. Verify P2P connectivity improves")

    return {
        'issues': issues_found,
        'fixes': fixes_applied,
        'timestamp': datetime.now().isoformat()
    }

if __name__ == "__main__":
    main()