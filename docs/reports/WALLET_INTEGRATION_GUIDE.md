# MEV LABS Dashboard - Wallet Integration Guide

## Overview
The MEV LABS dashboard now supports both **MetaMask** and **Safe Wallet** integrations, providing users with flexible options for connecting their wallets and executing MEV operations.

## Supported Wallets

### 1. MetaMask
- **Type**: Browser extension wallet
- **Use Case**: Individual users, quick transactions
- **Features**:
  - Instant connection and transaction signing
  - Direct ETH balance display
  - Real-time account change detection
  - Chain switching support

### 2. Safe Wallet (formerly Gnosis Safe)
- **Type**: Multi-signature smart contract wallet
- **Use Case**: Organizations, teams, high-value transactions
- **Features**:
  - Multi-signature security
  - Governance and approval workflows
  - Enhanced security for large MEV operations
  - Integration with Safe App ecosystem

## How to Connect

### MetaMask Connection
1. Click the "Connect Wallet" button in the dashboard header
2. Select "MetaMask" from the dropdown
3. Approve the connection request in MetaMask popup
4. Your wallet will be connected and balance displayed

### Safe Wallet Connection
1. **Method 1: Through Safe App**
   - Open https://app.safe.global/
   - Navigate to "Apps" section
   - Add custom app with your MEV LABS dashboard URL
   - Launch the app from within Safe interface
   - Wallet will auto-connect when loaded in Safe context

2. **Method 2: Direct Access**
   - Click "Connect Wallet" button
   - Select "Safe Wallet" from dropdown
   - Follow instructions to open in Safe App environment

## Transaction Execution

### MetaMask Transactions
- Immediate transaction signing
- Direct blockchain execution
- Real-time transaction hash provided
- Standard gas fee estimation

### Safe Transactions
- Multi-signature approval process
- Safe transaction hash generated
- Requires approval from configured Safe owners
- Enhanced security for large MEV operations

## Features by Wallet Type

| Feature | MetaMask | Safe Wallet |
|---------|----------|-------------|
| Instant Connection | ✅ | ✅ (in Safe App) |
| Auto-Connect | ✅ | ✅ (in Safe App) |
| Balance Display | ✅ | ✅ |
| Transaction Signing | ✅ | ✅ (multi-sig) |
| MEV Execution | ✅ | ✅ |
| Auto-Trading | ✅ | ⚠️ (requires approval) |

## Development Notes

### Safe App Integration
- Uses Safe Apps SDK v8.1.0
- Requires Safe App context for full functionality
- Fallback handling for non-Safe environments
- Proper error handling and user guidance

### MetaMask Integration
- Standard Web3 provider integration
- Event listeners for account/chain changes
- Graceful fallback for missing extension

### Security Features
- Environment detection (Safe App vs standalone)
- Proper error handling and user feedback
- Secure transaction data handling
- Auto-disconnect on account changes

## Troubleshooting

### Safe Wallet Issues
- **"Safe connection failed"**: Ensure you're running the app within Safe App environment
- **Connection timeout**: Check Safe App connectivity and try again
- **Balance not showing**: Safe RPC might be slow, balance will update

### MetaMask Issues
- **"MetaMask not detected"**: Install MetaMask browser extension
- **Connection rejected**: Accept the connection request in MetaMask
- **Wrong network**: Switch to the correct network in MetaMask

## API Integration
Both wallet types integrate with the MEV LABS API Gateway for authenticated operations and maintain session state across wallet connections.

## Future Enhancements
- WalletConnect integration for mobile wallets
- Additional hardware wallet support
- Advanced Safe transaction batching
- Cross-chain wallet support