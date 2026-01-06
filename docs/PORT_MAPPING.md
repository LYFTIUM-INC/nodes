# Blockchain Node Port Mapping Documentation

## Overview
This document maintains the official port mapping for all blockchain nodes in our infrastructure.

## Port Assignments

### Layer 1 Nodes

#### Ethereum (Erigon)
- **HTTP RPC**: 8545
- **WebSocket**: 8547 (Note: Not 8546 as commonly expected)
- **Auth RPC**: 8551
- **Metrics**: 6062
- **P2P**: 30309
- **Private API**: 9091

### Layer 2 Nodes

#### Arbitrum
- **HTTP RPC**: 8590
- **WebSocket**: 8591
- **P2P**: 30307

#### Optimism
- **Execution Layer (op-geth)**:
  - HTTP RPC: 8546
  - WebSocket: 8556
  - Auth RPC: 8555
  - Metrics: 6063
  - P2P: 30308

- **Consensus Layer (op-node)**:
  - RPC: 8569 (Changed from 8549 due to conflicts)
  - Metrics: 7301
  - pprof: 6071

#### Base
- **Execution Layer (op-geth)**:
  - HTTP RPC: 8548
  - WebSocket: 8558
  - Auth RPC: 8562
  - Metrics: 6061
  - P2P: 30306

- **Consensus Layer (op-node)**:
  - RPC: 8550
  - Metrics: 7302
  - pprof: 6072

### MEV Infrastructure
- **MEV Relay**: 9080
- **MEV Boost**: 18550

## Port Conflict Resolution History
- 2025-07-13: Changed Optimism OP-Node from 8549 to 8569 (port conflict)
- 2025-07-13: Clarified Erigon WS on 8547, not 8546

## Network Security
All ports are bound to localhost (127.0.0.1) except where external access is required.

## Last Updated
2025-07-13 by Blockchain Infrastructure Team