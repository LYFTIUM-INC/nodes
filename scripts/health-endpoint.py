#!/usr/bin/env python3
"""
MEV Infrastructure Health Endpoint
Serves health status on port 8580
"""

import json
import subprocess
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
import requests
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class HealthHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress default HTTP logging
        pass
    
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            health_data = self.get_health_status()
            self.wfile.write(json.dumps(health_data, indent=2).encode())
        
        elif self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            
            html = """
            <!DOCTYPE html>
            <html>
            <head><title>MEV Infrastructure Health</title></head>
            <body>
                <h1>MEV Infrastructure Health Monitor</h1>
                <p><a href="/health">Health Status JSON</a></p>
            </body>
            </html>
            """
            self.wfile.write(html.encode())
        
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found')
    
    def get_health_status(self):
        """Get comprehensive health status"""
        health = {
            "timestamp": int(time.time()),
            "status": "healthy",
            "services": {},
            "system": {},
            "issues": []
        }
        
        # Check services
        services = [
            "erigon.service",
            "mev-boost.service", 
            "lighthouse-beacon.service",
            "polygon.service",
            "optimism.service",
            "base.service"
        ]
        
        for service in services:
            try:
                result = subprocess.run(
                    ['systemctl', 'is-active', service],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                health["services"][service] = {
                    "status": result.stdout.strip(),
                    "active": result.stdout.strip() == "active"
                }
                
                if not health["services"][service]["active"]:
                    health["issues"].append(f"Service {service} is not active")
                    
            except Exception as e:
                health["services"][service] = {
                    "status": "error",
                    "active": False,
                    "error": str(e)
                }
                health["issues"].append(f"Failed to check {service}: {str(e)}")
        
        # Check system resources
        try:
            # Disk space
            result = subprocess.run(
                ['df', '/data/blockchain'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                if len(lines) > 1:
                    fields = lines[1].split()
                    if len(fields) >= 5:
                        usage_percent = int(fields[4].replace('%', ''))
                        health["system"]["disk_usage_percent"] = usage_percent
                        
                        if usage_percent > 90:
                            health["issues"].append(f"Disk usage critical: {usage_percent}%")
                        elif usage_percent > 85:
                            health["issues"].append(f"Disk usage high: {usage_percent}%")
            
            # Memory
            result = subprocess.run(
                ['free', '-m'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                if len(lines) > 1:
                    fields = lines[1].split()
                    if len(fields) >= 3:
                        total_mb = int(fields[1])
                        used_mb = int(fields[2])
                        usage_percent = int((used_mb / total_mb) * 100)
                        health["system"]["memory_usage_percent"] = usage_percent
                        health["system"]["memory_used_mb"] = used_mb
                        health["system"]["memory_total_mb"] = total_mb
                        
                        if usage_percent > 85:
                            health["issues"].append(f"Memory usage high: {usage_percent}%")
        
        except Exception as e:
            health["issues"].append(f"System check error: {str(e)}")
        
        # Check MEV-Boost
        try:
            response = requests.get('http://127.0.0.1:18551/eth/v1/builder/status', timeout=5)
            if response.status_code == 200:
                health["services"]["mev-boost-endpoint"] = {
                    "status": "responding",
                    "active": True
                }
            else:
                health["services"]["mev-boost-endpoint"] = {
                    "status": f"http_{response.status_code}",
                    "active": False
                }
                health["issues"].append(f"MEV-Boost returned status {response.status_code}")
        except Exception as e:
            health["services"]["mev-boost-endpoint"] = {
                "status": "error",
                "active": False,
                "error": str(e)
            }
            health["issues"].append(f"MEV-Boost endpoint error: {str(e)}")
        
        # Check Erigon sync
        try:
            response = requests.post(
                'http://127.0.0.1:8545',
                json={"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1},
                timeout=5
            )
            if response.status_code == 200:
                data = response.json()
                if data.get('result') == False:
                    health["services"]["erigon-sync"] = {
                        "status": "synced",
                        "active": True
                    }
                else:
                    health["services"]["erigon-sync"] = {
                        "status": "syncing",
                        "active": True,
                        "sync_info": data.get('result', {})
                    }
                    health["issues"].append("Erigon still syncing")
        except Exception as e:
            health["services"]["erigon-sync"] = {
                "status": "error", 
                "active": False,
                "error": str(e)
            }
            health["issues"].append(f"Erigon sync check error: {str(e)}")
        
        # Set overall status
        if health["issues"]:
            health["status"] = "degraded" if len(health["issues"]) < 3 else "unhealthy"
        
        return health

def run_server():
    """Run the health endpoint server"""
    server_address = ('127.0.0.1', 8580)
    httpd = HTTPServer(server_address, HealthHandler)
    
    logger.info(f"Health endpoint server starting on http://127.0.0.1:8580")
    logger.info("Available endpoints: /health, /")
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Server error: {e}")
    finally:
        httpd.server_close()

if __name__ == '__main__':
    run_server()