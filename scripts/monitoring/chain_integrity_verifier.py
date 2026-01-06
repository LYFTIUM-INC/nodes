#!/usr/bin/env python3
"""
Chain Integrity Verification Module
Verifies blockchain integrity against external references and detects anomalies

Features:
- External block reference verification
- Block hash validation
- Reorganization detection
- State root validation
- Chain work verification
- Fork detection
"""

import requests
import hashlib
import json
import time
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List, Tuple
import logging
from dataclasses import dataclass

@dataclass
class ChainIntegrityResult:
    """Chain integrity verification result"""
    node_name: str
    is_valid: bool
    block_diff: int
    hash_matches: bool
    reorg_detected: bool
    reorg_depth: int = 0
    chain_work_valid: bool = True
    state_root_valid: bool = True
    issues: List[str] = None
    reference_block: int = 0
    local_block: int = 0
    confidence_score: float = 0.0

    def __post_init__(self):
        if self.issues is None:
            self.issues = []

class ChainIntegrityVerifier:
    """Advanced chain integrity verification system"""

    def __init__(self, config: Dict[str, Any] = None):
        self.config = config or {}
        self.logger = logging.getLogger(__name__)
        self.etherscan_api_key = self.config.get('etherscan_api_key', '')
        self.beaconchain_api_key = self.config.get('beaconchain_api_key', '')
        self.cache = {}
        self.cache_timeout = 300  # 5 minutes

    def verify_chain_integrity(self, node_name: str, rpc_url: str, network: str = "mainnet",
                             verification_level: str = "standard") -> ChainIntegrityResult:
        """Comprehensive chain integrity verification"""
        self.logger.info(f"Starting chain integrity verification for {node_name}")

        result = ChainIntegrityResult(
            node_name=node_name,
            is_valid=False,
            block_diff=0,
            hash_matches=False,
            reorg_detected=False
        )

        try:
            # Get reference block from external source
            reference_block = self.get_reference_block_number(network)
            result.reference_block = reference_block

            if reference_block == 0:
                result.issues.append("Failed to get reference block from external sources")
                return result

            # Get local block from node
            local_block = self.get_local_block_number(rpc_url)
            result.local_block = local_block

            if local_block == 0:
                result.issues.append("Failed to get local block from node")
                return result

            # Calculate block difference
            result.block_diff = reference_block - local_block

            # Validate based on block difference
            if result.block_diff <= 5:
                result.is_valid = True
                result.confidence_score = 100.0
            elif result.block_diff <= 20:
                result.is_valid = True
                result.confidence_score = 80.0
                result.issues.append(f"Node lagging by {result.block_diff} blocks")
            else:
                result.is_valid = False
                result.confidence_score = 0.0
                result.issues.append(f"Node significantly behind by {result.block_diff} blocks")

            # Additional verification based on level
            if verification_level in ['comprehensive', 'forensic']:
                self.perform_comprehensive_integrity_checks(result, rpc_url, local_block, reference_block, network)

            # Detect reorganizations
            if verification_level in ['comprehensive', 'forensic']:
                result.reorg_detected, result.reorg_depth = self.detect_reorganizations(rpc_url, local_block, network)

            return result

        except Exception as e:
            self.logger.error(f"Chain integrity verification failed for {node_name}: {e}")
            result.issues.append(f"Verification error: {str(e)}")
            return result

    def get_reference_block_number(self, network: str) -> int:
        """Get reference block number from external sources"""
        cache_key = f"reference_block_{network}"

        # Check cache first
        if cache_key in self.cache:
            cached_data = self.cache[cache_key]
            if time.time() - cached_data['timestamp'] < self.cache_timeout:
                return cached_data['block_number']

        # Try multiple sources
        sources = [
            self.get_etherscan_block,
            self.get_beaconchain_block,
            self.get_infura_block
        ]

        for source_func in sources:
            try:
                block_number = source_func(network)
                if block_number > 0:
                    # Cache the result
                    self.cache[cache_key] = {
                        'block_number': block_number,
                        'timestamp': time.time()
                    }
                    return block_number
            except Exception as e:
                self.logger.warning(f"Failed to get reference from {source_func.__name__}: {e}")
                continue

        return 0

    def get_etherscan_block(self, network: str) -> int:
        """Get block number from Etherscan API"""
        base_urls = {
            'mainnet': 'https://api.etherscan.io/api',
            'sepolia': 'https://api-sepolia.etherscan.io/api',
            'goerli': 'https://api-goerli.etherscan.io/api',
            'holesky': 'https://api-holesky.etherscan.io/api'
        }

        base_url = base_urls.get(network, base_urls['mainnet'])

        params = {
            'module': 'proxy',
            'action': 'eth_blockNumber',
            'apikey': self.etherscan_api_key or 'YourApiKey'
        }

        response = requests.get(base_url, params=params, timeout=10)
        if response.status_code == 200:
            data = response.json()
            if data.get('status') == '1':
                block_hex = data.get('result', '0x0')
                return int(block_hex, 16) if block_hex != '0x0' else 0

        return 0

    def get_beaconchain_block(self, network: str) -> int:
        """Get block number from Beaconcha.in API"""
        base_urls = {
            'mainnet': 'https://beaconcha.in/api/v1/block/head',
            'sepolia': 'https://sepolia.beaconcha.in/api/v1/block/head',
            'goerli': 'https://goerli.beaconcha.in/api/v1/block/head'
        }

        base_url = base_urls.get(network)
        if not base_url:
            return 0

        try:
            response = requests.get(base_url, timeout=10)
            if response.status_code == 200:
                data = response.json()
                return data.get('data', {}).get('exec_block_number', 0)
        except Exception:
            pass

        return 0

    def get_infura_block(self, network: str) -> int:
        """Get block number from Infura (placeholder - requires API key)"""
        # This would require an Infura API key
        return 0

    def get_local_block_number(self, rpc_url: str) -> int:
        """Get current block number from local node"""
        try:
            response = requests.post(
                rpc_url,
                json={"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1},
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                block_hex = data.get('result', '0x0')
                return int(block_hex, 16) if block_hex != '0x0' else 0
        except Exception as e:
            self.logger.error(f"Failed to get local block number: {e}")

        return 0

    def perform_comprehensive_integrity_checks(self, result: ChainIntegrityResult, rpc_url: str,
                                            local_block: int, reference_block: int, network: str):
        """Perform comprehensive integrity checks"""
        # Verify block hash
        local_hash = self.get_block_hash(rpc_url, local_block)
        reference_hash = self.get_reference_block_hash(network, local_block)

        if local_hash and reference_hash:
            result.hash_matches = local_hash == reference_hash
            if not result.hash_matches:
                result.issues.append(f"Block hash mismatch at block {local_block}")
                result.confidence_score -= 20.0

        # Verify chain work
        result.chain_work_valid = self.verify_chain_work(rpc_url, local_block)
        if not result.chain_work_valid:
            result.issues.append("Chain work verification failed")
            result.confidence_score -= 15.0

        # Validate state root for recent blocks
        if local_block > 0:
            result.state_root_valid = self.validate_state_root(rpc_url, local_block)
            if not result.state_root_valid:
                result.issues.append("State root validation failed")
                result.confidence_score -= 10.0

    def get_block_hash(self, rpc_url: str, block_number: int) -> Optional[str]:
        """Get block hash for specific block number"""
        try:
            response = requests.post(
                rpc_url,
                json={
                    "jsonrpc":"2.0",
                    "method":"eth_getBlockByNumber",
                    "params":[hex(block_number), False],
                    "id":2
                },
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                block_data = data.get('result', {})
                return block_data.get('hash', '')
        except Exception as e:
            self.logger.error(f"Failed to get block hash: {e}")

        return None

    def get_reference_block_hash(self, network: str, block_number: int) -> Optional[str]:
        """Get reference block hash from external source"""
        cache_key = f"block_hash_{network}_{block_number}"

        if cache_key in self.cache:
            cached_data = self.cache[cache_key]
            if time.time() - cached_data['timestamp'] < self.cache_timeout:
                return cached_data['hash']

        try:
            base_url = {
                'mainnet': 'https://api.etherscan.io/api',
                'sepolia': 'https://api-sepolia.etherscan.io/api',
                'goerli': 'https://api-goerli.etherscan.io/api'
            }.get(network, 'https://api.etherscan.io/api')

            params = {
                'module': 'proxy',
                'action': 'eth_getBlockByNumber',
                'tag': hex(block_number),
                'boolean': 'false',
                'apikey': self.etherscan_api_key or 'YourApiKey'
            }

            response = requests.get(base_url, params=params, timeout=10)
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == '1':
                    result_data = data.get('result', {})
                    block_hash = result_data.get('hash', '')

                    if block_hash:
                        self.cache[cache_key] = {
                            'hash': block_hash,
                            'timestamp': time.time()
                        }
                        return block_hash
        except Exception as e:
            self.logger.error(f"Failed to get reference block hash: {e}")

        return None

    def verify_chain_work(self, rpc_url: str, block_number: int) -> bool:
        """Verify chain work (simplified verification)"""
        try:
            # Get block details to verify structure
            response = requests.post(
                rpc_url,
                json={
                    "jsonrpc":"2.0",
                    "method":"eth_getBlockByNumber",
                    "params":[hex(block_number), True],
                    "id":3
                },
                timeout=15
            )

            if response.status_code == 200:
                data = response.json()
                block_data = data.get('result', {})

                # Basic structure validation
                required_fields = ['hash', 'parentHash', 'number', 'timestamp', 'transactions']
                return all(field in block_data for field in required_fields)
        except Exception as e:
            self.logger.error(f"Chain work verification failed: {e}")

        return False

    def validate_state_root(self, rpc_url: str, block_number: int) -> bool:
        """Validate state root (basic validation)"""
        try:
            response = requests.post(
                rpc_url,
                json={
                    "jsonrpc":"2.0",
                    "method":"eth_getBlockByNumber",
                    "params":[hex(block_number), True],
                    "id":4
                },
                timeout=15
            )

            if response.status_code == 200:
                data = response.json()
                block_data = data.get('result', {})
                state_root = block_data.get('stateRoot', '')

                # Basic validation - state root should be a valid 32-byte hash
                return state_root.startswith('0x') and len(state_root) == 66
        except Exception as e:
            self.logger.error(f"State root validation failed: {e}")

        return False

    def detect_reorganizations(self, rpc_url: str, current_block: int, network: str) -> Tuple[bool, int]:
        """Detect recent reorganizations"""
        reorg_depth = 0
        max_check_depth = 10

        for i in range(1, min(max_check_depth, current_block)):
            check_block = current_block - i

            try:
                # Get local hash
                local_hash = self.get_block_hash(rpc_url, check_block)
                if not local_hash:
                    continue

                # Get reference hash
                reference_hash = self.get_reference_block_hash(network, check_block)
                if not reference_hash:
                    continue

                # Compare hashes
                if local_hash != reference_hash:
                    reorg_depth = i
                    break
            except Exception:
                continue

        return reorg_depth > 0, reorg_depth

    def verify_multiple_nodes(self, nodes: List[Dict[str, Any]], network: str = "mainnet",
                            verification_level: str = "standard") -> List[ChainIntegrityResult]:
        """Verify chain integrity for multiple nodes"""
        results = []

        for node in nodes:
            result = self.verify_chain_integrity(
                node_name=node['name'],
                rpc_url=node['rpc_url'],
                network=network,
                verification_level=verification_level
            )
            results.append(result)

        return results

    def generate_integrity_report(self, results: List[ChainIntegrityResult]) -> Dict[str, Any]:
        """Generate comprehensive integrity report"""
        total_nodes = len(results)
        valid_nodes = sum(1 for r in results if r.is_valid)
        reorg_detected = any(r.reorg_detected for r in results)
        avg_confidence = sum(r.confidence_score for r in results) / total_nodes if total_nodes > 0 else 0

        report = {
            'timestamp': datetime.now().isoformat(),
            'summary': {
                'total_nodes': total_nodes,
                'valid_nodes': valid_nodes,
                'invalid_nodes': total_nodes - valid_nodes,
                'validity_percentage': (valid_nodes / total_nodes * 100) if total_nodes > 0 else 0,
                'reorganizations_detected': reorg_detected,
                'average_confidence_score': avg_confidence
            },
            'nodes': [],
            'issues': [],
            'recommendations': []
        }

        for result in results:
            node_data = {
                'name': result.node_name,
                'is_valid': result.is_valid,
                'confidence_score': result.confidence_score,
                'block_difference': result.block_diff,
                'local_block': result.local_block,
                'reference_block': result.reference_block,
                'hash_matches': result.hash_matches,
                'reorg_detected': result.reorg_detected,
                'reorg_depth': result.reorg_depth,
                'issues': result.issues
            }
            report['nodes'].append(node_data)
            report['issues'].extend(result.issues)

        # Generate recommendations
        if reorg_detected:
            report['recommendations'].append("Reorganizations detected - monitor network stability")

        if avg_confidence < 80:
            report['recommendations'].append("Low confidence scores - investigate node synchronization")

        invalid_nodes = [r for r in results if not r.is_valid]
        if invalid_nodes:
            report['recommendations'].append(f"{len(invalid_nodes)} node(s) failed integrity verification")

        return report

def main():
    """Example usage"""
    logging.basicConfig(level=logging.INFO)

    verifier = ChainIntegrityVerifier()

    # Example node configurations
    nodes = [
        {
            'name': 'Erigon',
            'rpc_url': 'http://127.0.0.1:8545'
        },
        {
            'name': 'Geth',
            'rpc_url': 'http://127.0.0.1:8549'
        }
    ]

    # Verify integrity
    results = verifier.verify_multiple_nodes(nodes, verification_level='comprehensive')

    # Generate report
    report = verifier.generate_integrity_report(results)

    print("Chain Integrity Report:")
    print(json.dumps(report, indent=2))

if __name__ == "__main__":
    main()