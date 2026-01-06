#!/usr/bin/env python3
"""
MEV Operations Dashboard
Real-time monitoring for Erigon MEV infrastructure
"""

import subprocess
import json
import time
import requests
import psutil
from datetime import datetime
from typing import Dict, List, Optional
import sys

class MEVDashboard:
    def __init__(self):
        self.erigon_rpc = "http://127.0.0.1:8545"
        self.geth_rpc = "http://127.0.0.1:8547"  # Geth backup
        self.metrics = {}

    def get_system_info(self) -> Dict:
        """Get system resource information"""
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')

        return {
            'cpu_percent': cpu_percent,
            'memory_total': memory.total / 1024**3,  # GB
            'memory_used': memory.used / 1024**3,
            'memory_percent': memory.percent,
            'disk_total': disk.total / 1024**3,
            'disk_used': disk.used / 1024**3,
            'disk_percent': disk.percent,
            'timestamp': datetime.now().isoformat()
        }

    def get_erigon_status(self) -> Dict:
        """Get comprehensive Erigon status for MEV"""
        status = {
            'service_active': False,
            'rpc_responsive': False,
            'sync_progress': 0,
            'current_block': 0,
            'highest_block': 0,
            'peer_count': 0,
            'memory_mb': 0,
            'memory_percent': 0,
            'cpu_percent': 0,
            'txpool_pending': 0,
            'txpool_queued': 0,
            'gas_price': 0,
            'mev_ready': False
        }

        # Check service status
        try:
            result = subprocess.run(['systemctl', 'is-active', 'erigon'],
                                 capture_output=True, text=True, timeout=5)
            status['service_active'] = result.stdout.strip() == 'active'
        except:
            pass

        if status['service_active']:
            # Get sync status
            try:
                response = requests.post(self.erigon_rpc, json={
                    "jsonrpc": "2.0", "method": "eth_syncing", "params": [], "id": 1
                }, timeout=10)

                if response.status_code == 200:
                    data = response.json().get('result')
                    if data:
                        if data is False:
                            status['sync_progress'] = 100.0
                        else:
                            current = int(data.get('currentBlock', '0x0'), 16)
                            highest = int(data.get('highestBlock', '0x0'), 16)
                            status['current_block'] = current
                            status['highest_block'] = highest
                            if highest > 0:
                                status['sync_progress'] = (current / highest) * 100

                    status['rpc_responsive'] = True
            except:
                pass

        if status['rpc_responsive']:
            # Get peer count
            try:
                response = requests.post(self.erigon_rpc, json={
                    "jsonrpc": "2.0", "method": "net_peerCount", "params": [], "id": 1
                }, timeout=5)
                if response.status_code == 200:
                    status['peer_count'] = int(response.json().get('result', '0x0'), 16)
            except:
                pass

            # Get txpool status
            try:
                response = requests.post(self.erigon_rpc, json={
                    "jsonrpc": "2.0", "method": "txpool_status", "params": [], "id": 1
                }, timeout=5)
                if response.status_code == 200:
                    data = response.json().get('result', {})
                    status['txpool_pending'] = int(data.get('pending', '0x0'), 16)
                    status['txpool_queued'] = int(data.get('queued', '0x0'), 16)
            except:
                pass

            # Get gas price
            try:
                response = requests.post(self.erigon_rpc, json={
                    "jsonrpc": "2.0", "method": "eth_gasPrice", "params": [], "id": 1
                }, timeout=5)
                if response.status_code == 200:
                    status['gas_price'] = int(response.json().get('result', '0x0'), 16) / 1e9
            except:
                pass

        # Get resource usage
        try:
            for proc in psutil.process_iter(['name', 'memory_percent', 'cpu_percent']):
                if proc.info['name'] == 'erigon':
                    status['memory_percent'] = proc.memory_percent()
                    status['cpu_percent'] = proc.cpu_percent()
                    status['memory_mb'] = proc.memory_info().rss / 1024 / 1024
                    break
        except:
            pass

        # Determine MEV readiness
        status['mev_ready'] = (
            status['service_active'] and
            status['rpc_responsive'] and
            status['sync_progress'] >= 99.0 and
            status['peer_count'] >= 50
        )

        return status

    def get_geth_status(self) -> Dict:
        """Get Geth backup status"""
        status = {
            'service_active': False,
            'sync_progress': 0,
            'peer_count': 0,
            'memory_mb': 0,
            'rpc_responsive': False
        }

        # Check service status
        try:
            result = subprocess.run(['systemctl', 'is-active', 'geth'],
                                 capture_output=True, text=True, timeout=5)
            status['service_active'] = result.stdout.strip() == 'active'
        except:
            pass

        if status['service_active']:
            # Test RPC responsiveness
            try:
                response = requests.post(self.geth_rpc, json={
                    "jsonrpc": "2.0", "method": "eth_syncing", "params": [], "id": 1
                }, timeout=10)

                if response.status_code == 200:
                    data = response.json().get('result')
                    if data:
                        if data is False:
                            status['sync_progress'] = 100.0
                        else:
                            current = int(data.get('currentBlock', '0x0'), 16)
                            highest = int(data.get('highestBlock', '0x0'), 16)
                            if highest > 0:
                                status['sync_progress'] = (current / highest) * 100

                    status['rpc_responsive'] = True
            except:
                pass

            # Get peer count
            try:
                response = requests.post(self.geth_rpc, json={
                    "jsonrpc": "2.0", "method": "net_peerCount", "params": [], "id": 1
                }, timeout=5)
                if response.status_code == 200:
                    status['peer_count'] = int(response.json().get('result', '0x0'), 16)
            except:
                pass

        return status

    def get_ntp_status(self) -> Dict:
        """Get NTP synchronization status"""
        try:
            result = subprocess.run(['timedatectl', 'status'],
                                 capture_output=True, text=True, timeout=5)

            ntp_sync = 'NTP synchronized: yes' in result.stdout
            time_sync = 'System clock synchronized: yes' in result.stdout

            return {
                'ntp_synchronized': ntp_sync,
                'time_synchronized': time_sync,
                'details': result.stdout.split('\n')[:3]
            }
        except:
            return {'ntp_synchronized': False, 'time_synchronized': False}

    def calculate_mev_score(self, erigon_status: Dict, system_info: Dict) -> float:
        """Calculate MEV operations readiness score"""
        score = 0.0
        weights = {
            'sync_progress': 30,
            'peer_connectivity': 20,
            'rpc_performance': 20,
            'system_resources': 15,
            'txpool_activity': 10,
            'ntp_sync': 5
        }

        # Sync progress (30%)
        if erigon_status['sync_progress'] >= 99.5:
            score += weights['sync_progress']
        elif erigon_status['sync_progress'] >= 95.0:
            score += weights['sync_progress'] * 0.8
        elif erigon_status['sync_progress'] >= 90.0:
            score += weights['sync_progress'] * 0.6
        else:
            score += weights['sync_progress'] * 0.3

        # Peer connectivity (20%)
        if erigon_status['peer_count'] >= 100:
            score += weights['peer_connectivity']
        elif erigon_status['peer_count'] >= 50:
            score += weights['peer_connectivity'] * 0.8
        elif erigon_status['peer_count'] >= 25:
            score += weights['peer_connectivity'] * 0.6
        else:
            score += weights['peer_connectivity'] * 0.3

        # RPC performance (20%)
        if erigon_status['rpc_responsive']:
            if erigon_status['sync_progress'] == 100.0:
                score += weights['rpc_performance']
            else:
                score += weights['rpc_performance'] * 0.9
        else:
            score += 0

        # System resources (15%)
        if system_info['memory_percent'] <= 80 and system_info['cpu_percent'] <= 80:
            score += weights['system_resources']
        elif system_info['memory_percent'] <= 90 and system_info['cpu_percent'] <= 90:
            score += weights['system_resources'] * 0.7
        else:
            score += weights['system_resources'] * 0.4

        # TxPool activity (10%)
        if erigon_status['txpool_pending'] > 0:
            score += weights['txpool_activity']
        else:
            score += weights['txpool_activity'] * 0.5

        # NTP sync (5%)
        ntp_status = self.get_ntp_status()
        if ntp_status['ntp_synchronized']:
            score += weights['ntp_sync']
        else:
            score += 0

        return round(score, 2)

    def display_dashboard(self):
        """Display comprehensive MEV dashboard"""
        while True:
            # Clear screen
            print('\033[2J\033[H', end='')

            # Get all metrics
            system_info = self.get_system_info()
            erigon_status = self.get_erigon_status()
            geth_status = self.get_geth_status()
            ntp_status = self.get_ntp_status()
            mev_score = self.calculate_mev_score(erigon_status, system_info)

            # Header
            print("🚀 MEV OPERATIONS DASHBOARD")
            print("=" * 60)
            print(f"📅 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} | ⏱️  Refresh: 5s")
            print()

            # MEV Readiness Score
            score_color = "🟢" if mev_score >= 90 else "🟡" if mev_score >= 70 else "🔴"
            print(f"📊 MEV READINESS SCORE: {score_color} {mev_score}/100")
            print()

            # System Resources
            print("💻 SYSTEM RESOURCES")
            print("-" * 25)
            print(f"   CPU: {system_info['cpu_percent']:.1f}%")
            print(f"   Memory: {system_info['memory_used']:.1f}GB / {system_info['memory_total']:.1f}GB ({system_info['memory_percent']:.1f}%)")
            print(f"   Disk: {system_info['disk_used']:.1f}GB / {system_info['disk_total']:.1f}GB ({system_info['disk_percent']:.1f}%)")
            print()

            # Time Sync
            ntp_icon = "✅" if ntp_status['ntp_synchronized'] else "❌"
            print(f"🕐 TIME SYNC: {ntp_icon} NTP {'Synchronized' if ntp_status['ntp_synchronized'] else 'Not Synchronized'}")
            print()

            # Erigon Status
            erigon_icon = "🟢" if erigon_status['mev_ready'] else "🟡" if erigon_status['service_active'] else "🔴"
            print(f"🔷 ERIGON: {erigon_icon} {'MEV Ready' if erigon_status['mev_ready'] else 'Not Ready'}")
            print("-" * 30)
            print(f"   Service: {'🟢 Active' if erigon_status['service_active'] else '🔴 Stopped'}")
            print(f"   RPC: {'🟢 Responsive' if erigon_status['rpc_responsive'] else '🔴 Unresponsive'}")
            print(f"   Sync: {erigon_status['sync_progress']:.2f}% ({erigon_status['current_block']:,} / {erigon_status['highest_block']:,})")
            print(f"   Peers: {erigon_status['peer_count']}")
            print(f"   Memory: {erigon_status['memory_mb']:.0f}MB ({erigon_status['memory_percent']:.1f}%)")
            print(f"   TxPool: {erigon_status['txpool_pending']} pending, {erigon_status['txpool_queued']} queued")
            print(f"   Gas Price: {erigon_status['gas_price']:.2f} Gwei")
            print()

            # Geth Backup Status
            geth_icon = "🟢" if geth_status['rpc_responsive'] else "🟡" if geth_status['service_active'] else "🔴"
            print(f"🟢 GETH BACKUP: {geth_icon} {'Ready' if geth_status['rpc_responsive'] else 'Not Ready'}")
            print("-" * 25)
            print(f"   Service: {'🟢 Active' if geth_status['service_active'] else '🔴 Stopped'}")
            print(f"   RPC: {'🟢 Responsive' if geth_status['rpc_responsive'] else '🔴 Unresponsive'}")
            print(f"   Sync: {geth_status['sync_progress']:.2f}%")
            print(f"   Peers: {geth_status['peer_count']}")
            print()

            # MEV Operations Status
            print("🎯 MEV OPERATIONS STATUS")
            print("-" * 30)

            # Readiness checks
            checks = [
                ("Erigon Sync", erigon_status['sync_progress'] >= 99.0),
                ("P2P Connectivity", erigon_status['peer_count'] >= 50),
                ("RPC Endpoint", erigon_status['rpc_responsive']),
                ("Time Sync", ntp_status['ntp_synchronized']),
                ("TxPool Active", erigon_status['txpool_pending'] > 0),
                ("Memory OK", erigon_status['memory_percent'] <= 80)
            ]

            for check_name, check_pass in checks:
                icon = "✅" if check_pass else "❌"
                print(f"   {icon} {check_name}")

            print()

            # Quick Actions
            print("⚡ QUICK ACTIONS")
            print("-" * 20)
            print("   1. Erigon Manager: python3 erigon_manager.py --status")
            print("   2. Diagnostics: python3 erigon_diagnostics.py")
            print("   3. Sync Check: python3 quick_sync_check.py")
            print("   4. Exit: Ctrl+C")
            print()

            time.sleep(5)

def main():
    """Main dashboard function"""
    dashboard = MEVDashboard()
    try:
        dashboard.display_dashboard()
    except KeyboardInterrupt:
        print("\n👋 Dashboard stopped")

if __name__ == "__main__":
    main()