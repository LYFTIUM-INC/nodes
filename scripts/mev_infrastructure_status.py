#!/usr/bin/env python3
"""
MEV Foundation Infrastructure Status and Validation Script
Day 1 Status Report for MEV-Boost, RBuilder, and Bundle Router
"""

import asyncio
import aiohttp
import json
import time
import subprocess
import requests
from typing import Dict, List, Optional
from dataclasses import dataclass
from datetime import datetime

@dataclass
class MEVFoundationStatus:
    timestamp: datetime
    mev_boost_status: Dict
    rbuilder_status: Dict
    bundle_router_status: Dict
    monitoring_status: Dict
    connectivity_tests: Dict
    overall_health_score: float

class MEVFoundationValidator:
    def __init__(self):
        self.endpoints = {
            "mev_boost": "http://localhost:18550",
            "rbuilder": "http://localhost:18560", 
            "bundle_router": "http://localhost:18570",
            "prometheus": "http://localhost:19090",
            "grafana": "http://localhost:3000"
        }
        self.session = None

    async def __aenter__(self):
        self.session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=15))
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    def check_docker_containers(self) -> Dict:
        """Check MEV foundation Docker containers"""
        try:
            result = subprocess.run(
                ["docker", "ps", "--format", "json"],
                capture_output=True,
                text=True,
                timeout=10
            )
            containers = json.loads(result.stdout)
            
            mev_containers = []
            for container in containers:
                if any(name in container.get("Names", [""]) for name in ["mev-boost", "rbuilder", "bundle-router", "prometheus", "grafana"]):
                    mev_containers.append({
                        "name": container["Names"][0].replace("/", ""),
                        "status": container["Status"],
                        "ports": container["Ports"],
                        "created": container["CreatedAt"],
                        "image": container["Image"]
                    })
            
            return {
                "total_containers": len(mev_containers),
                "containers": mev_containers,
                "healthy": len([c for c in mev_containers if "Up" in c["status"]])
            }
        except Exception as e:
            return {"error": str(e), "total_containers": 0, "containers": [], "healthy": 0}

    async def test_endpoint_health(self, name: str, url: str) -> Dict:
        """Test endpoint health and response time"""
        try:
            start_time = time.time()
            async with self.session.get(url, timeout=10) as response:
                response_time = (time.time() - start_time) * 1000
                return {
                    "name": name,
                    "url": url,
                    "healthy": response.status == 200,
                    "status_code": response.status,
                    "response_time_ms": response_time,
                    "timestamp": datetime.now().isoformat()
                }
        except Exception as e:
            return {
                "name": name,
                "url": url,
                "healthy": False,
                "error": str(e),
                "response_time_ms": 0,
                "timestamp": datetime.now().isoformat()
            }

    async def test_mev_boost_api(self) -> Dict:
        """Test MEV-Boost Builder API"""
        try:
            # Test status endpoint
            async with self.session.get(f"{self.endpoints['mev_boost']}/status", timeout=10) as response:
                return {
                    "name": "MEV-Boost",
                    "builder_api_healthy": response.status == 200,
                    "status_code": response.status,
                    "response": await response.text() if response.status == 200 else None
                }
        except Exception as e:
            return {
                "name": "MEV-Boost",
                "builder_api_healthy": False,
                "error": str(e)
            }

    async def test_ethereum_connectivity(self) -> Dict:
        """Test connectivity to Ethereum node"""
        try:
            payload = {
                "jsonrpc": "2.0",
                "id": int(time.time() * 1000),
                "method": "eth_blockNumber",
                "params": []
            }
            
            async with self.session.post("http://localhost:8545", json=payload, timeout=10) as response:
                result = await response.json()
                return {
                    "ethereum_rpc_healthy": response.status == 200,
                    "block_number": int(result.get("result", "0x0"), 16),
                    "response_time_ms": 0
                }
        except Exception as e:
            return {
                "ethereum_rpc_healthy": False,
                "error": str(e),
                "block_number": 0
            }

    async def calculate_infrastructure_score(self, status: MEVFoundationStatus) -> float:
        """Calculate overall infrastructure health score"""
        scores = {
            "containers_running": 20,
            "mev_boost_healthy": 25,
            "rbuilder_healthy": 20,
            "bundle_router_healthy": 15,
            "monitoring_healthy": 10,
            "ethereum_connected": 10
        }
        
        score = 0
        
        # Container health
        if status.connectivity_tests.get("healthy", 0) > 0:
            score += scores["containers_running"]
        
        # MEV-Boost health
        if status.mev_boost_status.get("builder_api_healthy", False):
            score += scores["mev_boost_healthy"]
        
        # Ethereum connectivity
        if status.connectivity_tests.get("ethereum_rpc_healthy", False):
            score += scores["ethereum_connected"]
        
        return min(score, 100)

    async def generate_status_report(self) -> MEVFoundationStatus:
        """Generate comprehensive MEV foundation status report"""
        print("🚀 MEV Foundation Infrastructure Status Report")
        print("=" * 50)
        
        status = MEVFoundationStatus(
            timestamp=datetime.now(),
            mev_boost_status={},
            rbuilder_status={},
            bundle_router_status={},
            monitoring_status={},
            connectivity_tests={},
            overall_health_score=0
        )
        
        # Check Docker containers
        print("\n📦 Container Status:")
        container_status = self.check_docker_containers()
        status.connectivity_tests["containers"] = container_status
        
        if container_status.get("error"):
            print(f"❌ Error checking containers: {container_status['error']}")
        else:
            print(f"📊 Total MEV containers: {container_status['total_containers']}")
            print(f"✅ Healthy containers: {container_status['healthy']}")
            
            for container in container_status.get("containers", []):
                status_icon = "✅" if "Up" in container["status"] else "❌"
                print(f"   {status_icon} {container['name']} ({container['status']})")
        
        # Test connectivity
        print("\n🔗 Connectivity Tests:")
        connectivity_results = {}
        
        # Test Ethereum RPC
        eth_result = await self.test_ethereum_connectivity()
        connectivity_results["ethereum_rpc"] = eth_result
        status.connectivity_tests["ethereum_rpc_healthy"] = eth_result.get("ethereum_rpc_healthy", False)
        
        eth_icon = "✅" if eth_result.get("ethereum_rpc_healthy") else "❌"
        print(f"   {eth_icon} Ethereum RPC: {'Connected' if eth_result.get('ethereum_rpc_healthy') else 'Disconnected'}")
        if eth_result.get("ethereum_rpc_healthy"):
            print(f"      Current block: {eth_result.get('block_number', 'Unknown')}")
        
        # Test MEV endpoints
        for name, url in self.endpoints.items():
            if name in ["mev_boost", "rbuilder", "bundle_router"]:
                result = await self.test_endpoint_health(name, url)
                connectivity_results[name] = result
                
                icon = "✅" if result["healthy"] else "❌"
                print(f"   {icon} {name.replace('_', ' ').title()}: {result.get('response_time_ms', 0):.0f}ms")
        
        # Test MEV-Boost API
        print("\n🔨 MEV-Boost API:")
        mev_boost_result = await self.test_mev_boost_api()
        status.mev_boost_status = mev_boost_result
        
        boost_icon = "✅" if mev_boost_result.get("builder_api_healthy") else "❌"
        print(f"   {boost_icon} Builder API: {'Operational' if mev_boost_result.get('builder_api_healthy') else 'Down'}")
        
        # Calculate overall score
        status.overall_health_score = await self.calculate_infrastructure_score(status)
        
        # Summary
        print(f"\n📊 Overall Health Score: {status.overall_health_score}/100")
        
        if status.overall_health_score >= 80:
            print("🎉 MEV Foundation infrastructure is in EXCELLENT condition")
        elif status.overall_health_score >= 60:
            print("⚠️  MEV Foundation infrastructure needs attention")
        else:
            print("❌ MEV Foundation infrastructure requires immediate attention")
        
        # Recommendations
        print("\n💡 Recommendations:")
        recommendations = []
        
        if not status.connectivity_tests.get("ethereum_rpc_healthy", False):
            recommendations.append("🔧 Start or configure Ethereum RPC client")
        
        if not status.mev_boost_status.get("builder_api_healthy", False):
            recommendations.append("🔨 Configure and start MEV-Boost with valid relay URLs")
        
        if container_status.get("healthy", 0) < 3:
            recommendations.append("🚀 Deploy remaining MEV foundation components")
        
        if status.overall_health_score < 50:
            recommendations.append("🚨 Critical infrastructure issues detected")
        
        if recommendations:
            for rec in recommendations:
                print(f"   {rec}")
        else:
            print("   ✅ All systems operational")
        
        return status

    def save_status_report(self, status: MEVFoundationStatus) -> str:
        """Save status report to file"""
        report_data = {
            "timestamp": status.timestamp.isoformat(),
            "infrastructure_type": "MEV Foundation",
            "components": {
                "mev_boost": status.mev_boost_status,
                "rbuilder": status.rbuilder_status,
                "bundle_router": status.bundle_router_status,
                "monitoring": status.monitoring_status
            },
            "connectivity_tests": status.connectivity_tests,
            "overall_health_score": status.overall_health_score,
            "generated_by": "MEV Foundation Validator v1.0"
        }
        
        report_file = f"/data/blockchain/reports/mev_foundation_status_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        import os
        os.makedirs("/data/blockchain/reports", exist_ok=True)
        
        with open(report_file, 'w') as f:
            json.dump(report_data, f, indent=2)
        
        return report_file

async def main():
    """Main validation execution"""
    validator = MEVFoundationValidator()
    
    try:
        async with validator as v:
            status = await v.generate_status_report()
            report_file = v.save_status_report(status)
            
            print(f"\n📄 Status report saved to: {report_file}")
            return status.overall_health_score >= 60
            
    except Exception as e:
        print(f"❌ Validation failed: {e}")
        return False

if __name__ == "__main__":
    import sys
    sys.exit(0 if asyncio.run(main()) else 1)