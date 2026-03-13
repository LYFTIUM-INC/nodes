#!/usr/bin/env python3
"""
Blockchain Circuit Breaker Implementation
Handles automatic failover to backup endpoints
"""

import time
import json
import yaml
import requests
import threading
from enum import Enum
from dataclasses import dataclass
from typing import Dict, List, Optional
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class CircuitState(Enum):
    CLOSED = "closed"      # Normal operation
    OPEN = "open"          # Failing, use backup
    HALF_OPEN = "half_open" # Testing if recovered

@dataclass
class Endpoint:
    url: str
    weight: int
    timeout: int = 10
    health_check: str = ""

@dataclass
class CircuitBreakerConfig:
    failure_threshold: int = 5
    recovery_timeout: int = 30
    half_open_requests: int = 3
    health_check_interval: int = 10
    timeout: int = 5
    unhealthy_threshold: int = 3

class CircuitBreaker:
    def __init__(self, name: str, primary: Endpoint, backups: List[Endpoint], config: CircuitBreakerConfig):
        self.name = name
        self.primary = primary
        self.backups = backups
        self.config = config
        
        self.state = CircuitState.CLOSED
        self.failure_count = 0
        self.last_failure_time = 0
        self.half_open_count = 0
        self.current_endpoint = primary
        
        self.lock = threading.Lock()
        
    def call(self, path: str = "", method: str = "GET", data: dict = None, headers: dict = None) -> Optional[dict]:
        """Make a call through the circuit breaker"""
        with self.lock:
            if self.state == CircuitState.OPEN:
                if time.time() - self.last_failure_time > self.config.recovery_timeout:
                    self.state = CircuitState.HALF_OPEN
                    self.half_open_count = 0
                    logger.info(f"Circuit breaker {self.name} transitioning to HALF_OPEN")
                else:
                    # Use backup endpoint
                    return self._call_backup(path, method, data, headers)
            
            # Try primary endpoint
            try:
                response = self._make_request(self.primary, path, method, data, headers)
                self._on_success()
                return response
            except Exception as e:
                logger.warning(f"Primary endpoint {self.name} failed: {e}")
                self._on_failure()
                
                if self.state == CircuitState.OPEN:
                    return self._call_backup(path, method, data, headers)
                    
        return None
    
    def _make_request(self, endpoint: Endpoint, path: str, method: str, data: dict, headers: dict) -> dict:
        """Make HTTP request to endpoint"""
        url = f"{endpoint.url.rstrip('/')}/{path.lstrip('/')}" if path else endpoint.url
        
        kwargs = {
            'timeout': endpoint.timeout,
            'headers': headers or {}
        }
        
        if method.upper() == 'POST' and data:
            kwargs['json'] = data
            kwargs['headers']['Content-Type'] = 'application/json'
            
        response = requests.request(method, url, **kwargs)
        response.raise_for_status()
        
        try:
            return response.json()
        except:
            return {"status": "ok", "text": response.text}
    
    def _call_backup(self, path: str, method: str, data: dict, headers: dict) -> Optional[dict]:
        """Try backup endpoints in order of weight"""
        sorted_backups = sorted(self.backups, key=lambda x: x.weight, reverse=True)
        
        for backup in sorted_backups:
            try:
                logger.info(f"Trying backup endpoint: {backup.url}")
                response = self._make_request(backup, path, method, data, headers)
                self.current_endpoint = backup
                return response
            except Exception as e:
                logger.warning(f"Backup endpoint {backup.url} failed: {e}")
                continue
                
        logger.error(f"All endpoints failed for {self.name}")
        return None
    
    def _on_success(self):
        """Handle successful request"""
        if self.state == CircuitState.HALF_OPEN:
            self.half_open_count += 1
            if self.half_open_count >= self.config.half_open_requests:
                self.state = CircuitState.CLOSED
                self.failure_count = 0
                logger.info(f"Circuit breaker {self.name} recovered to CLOSED")
        elif self.state == CircuitState.CLOSED:
            self.failure_count = 0
            
        self.current_endpoint = self.primary
    
    def _on_failure(self):
        """Handle failed request"""
        self.failure_count += 1
        self.last_failure_time = time.time()
        
        if self.failure_count >= self.config.failure_threshold:
            if self.state != CircuitState.OPEN:
                self.state = CircuitState.OPEN
                logger.warning(f"Circuit breaker {self.name} opened due to failures")
    
    def health_check(self) -> bool:
        """Check if primary endpoint is healthy"""
        try:
            health_path = self.primary.health_check or ""
            response = self._make_request(self.primary, health_path, "GET", None, None)
            return True
        except:
            return False
    
    def get_status(self) -> dict:
        """Get circuit breaker status"""
        return {
            "name": self.name,
            "state": self.state.value,
            "failure_count": self.failure_count,
            "current_endpoint": self.current_endpoint.url,
            "primary_healthy": self.health_check(),
            "last_failure": self.last_failure_time
        }

class FailoverManager:
    def __init__(self, config_path: str = "/data/blockchain/nodes/failover/failover-config.yaml"):
        self.config_path = config_path
        self.circuit_breakers: Dict[str, CircuitBreaker] = {}
        self.load_config()
        self.start_health_monitoring()
        
    def load_config(self):
        """Load failover configuration"""
        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)
                
            cb_config = CircuitBreakerConfig(**config['circuit_breaker'])
            
            for name, endpoint_config in config['endpoints'].items():
                primary = Endpoint(**endpoint_config['primary'])
                backups = [Endpoint(**backup) for backup in endpoint_config['backups']]
                
                self.circuit_breakers[name] = CircuitBreaker(name, primary, backups, cb_config)
                
            logger.info(f"Loaded {len(self.circuit_breakers)} circuit breakers")
            
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            raise
    
    def start_health_monitoring(self):
        """Start background health monitoring"""
        def monitor():
            while True:
                for cb in self.circuit_breakers.values():
                    if cb.state == CircuitState.OPEN:
                        if cb.health_check():
                            logger.info(f"Primary endpoint {cb.name} appears healthy, transitioning to HALF_OPEN")
                            cb.state = CircuitState.HALF_OPEN
                            cb.half_open_count = 0
                            
                time.sleep(30)  # Check every 30 seconds
                
        thread = threading.Thread(target=monitor, daemon=True)
        thread.start()
    
    def get_endpoint(self, blockchain: str) -> Optional[CircuitBreaker]:
        """Get circuit breaker for blockchain"""
        return self.circuit_breakers.get(blockchain)
    
    def get_all_status(self) -> dict:
        """Get status of all circuit breakers"""
        return {name: cb.get_status() for name, cb in self.circuit_breakers.items()}
    
    def rpc_call(self, blockchain: str, method: str, params: list = None, rpc_id: int = 1) -> Optional[dict]:
        """Make RPC call with automatic failover"""
        cb = self.get_endpoint(blockchain)
        if not cb:
            logger.error(f"No circuit breaker found for {blockchain}")
            return None
            
        rpc_data = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or [],
            "id": rpc_id
        }
        
        return cb.call(method="POST", data=rpc_data)

# Example usage and testing
if __name__ == "__main__":
    failover = FailoverManager()
    
    # Test Ethereum call
    result = failover.rpc_call("ethereum", "eth_blockNumber")
    print(f"Ethereum block number: {result}")
    
    # Test Solana health
    solana_cb = failover.get_endpoint("solana")
    if solana_cb:
        health = solana_cb.call("health", "GET")
        print(f"Solana health: {health}")
    
    # Print all status
    status = failover.get_all_status()
    print(json.dumps(status, indent=2))