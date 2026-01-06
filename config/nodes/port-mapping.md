# Blockchain Node Port Mapping

## Ethereum (Erigon)
- HTTP RPC: 8545
- WebSocket: 8546  
- Auth RPC: 8551
- P2P: 30304
- Metrics: 6061
- Private API: 9091

## Optimism (Op-Geth)
- HTTP RPC: 8546 (non-standard, should be updated to avoid conflict)
- WebSocket: 8556
- Auth RPC: 8555  
- P2P: 30308
- Metrics: 6062

## Avalanche
- HTTP RPC: 9650
- P2P: 9651
- Staking: 9652

## Arbitrum (Docker)
- HTTP RPC: 8547
- WebSocket: 8557
- P2P: Custom

## Port Conflicts to Resolve
1. Optimism HTTP RPC on 8546 conflicts with Ethereum WebSocket
2. Ethereum P2P port 30304 showing "address already in use"

## Recommended Standardization
- Ethereum: 8545-8551, 30304
- Optimism: 8560-8565, 30308  
- Arbitrum: 8570-8575, 30309
- Base: 8580-8585, 30310
- Polygon: 8590-8595, 30311
- Avalanche: 9650-9655, 30312