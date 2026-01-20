# Backend Integration Guide

This guide explains how to integrate with the Goblin Copy-Trading smart contracts from your backend service.

---

## Table of Contents

1. [Setup](#setup)
2. [Contract Addresses](#contract-addresses)
3. [ABI Files](#abi-files)
4. [Integration Examples](#integration-examples)
   - [ethers.js (Node.js)](#ethersjs-nodejs)
   - [viem (TypeScript)](#viem-typescript)
   - [web3.py (Python)](#web3py-python)
5. [Common Operations](#common-operations)
6. [Event Listening](#event-listening)
7. [Error Handling](#error-handling)

---

## Setup

### Prerequisites

- Node.js 18+ or Python 3.9+
- RPC endpoint for Polygon mainnet (Alchemy, Infura, QuickNode, etc.)
- Private key for transaction signing (executor wallet)

### Install Dependencies

**Node.js (ethers.js)**
```bash
npm install ethers
```

**Node.js (viem)**
```bash
npm install viem
```

**Python**
```bash
pip install web3
```

---

## Contract Addresses

```javascript
const CONTRACTS = {
  // Goblin Contracts
  CopyVault: "0xEa6ce4437B49e48b0350324c7435c9b9d0A84061",
  PositionManager: "0x766dB1CC757c12ef47749EE90E7770E071396463",
  Timelock: "0x35C49FE68AEA69EBaAF4ff75066D40adf1F0e9c6",
  AccessController: "0x8704c006F2734be577780FE0209A3CeD7493CEC2",

  // Polymarket Contracts
  USDC: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
  CTF: "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045",
  Exchange: "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E",
};

const POLYGON_RPC = "https://polygon-mainnet.g.alchemy.com/v2/YOUR_API_KEY";
const CHAIN_ID = 137;
```

---

## ABI Files

ABI files are located in the `abi/` directory:

```
abi/
├── CopyVault.json
├── PositionManager.json
├── Timelock.json
└── AccessController.json
```

Load ABIs in your code:

```javascript
// Node.js
const CopyVaultABI = require('./abi/CopyVault.json');
const PositionManagerABI = require('./abi/PositionManager.json');
```

```python
# Python
import json

with open('abi/CopyVault.json') as f:
    copy_vault_abi = json.load(f)
```

---

## Integration Examples

### ethers.js (Node.js)

```javascript
const { ethers } = require('ethers');
const CopyVaultABI = require('./abi/CopyVault.json');
const PositionManagerABI = require('./abi/PositionManager.json');

// Setup provider and signer
const provider = new ethers.JsonRpcProvider(POLYGON_RPC);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

// Initialize contracts
const copyVault = new ethers.Contract(
  CONTRACTS.CopyVault,
  CopyVaultABI,
  wallet
);

const positionManager = new ethers.Contract(
  CONTRACTS.PositionManager,
  PositionManagerABI,
  wallet
);

// Example: Read vault state
async function getVaultState() {
  const totalAssets = await copyVault.totalAssets();
  const totalSupply = await copyVault.totalSupply();
  const paused = await copyVault.paused();

  return {
    totalAssets: ethers.formatUnits(totalAssets, 6), // USDC has 6 decimals
    totalSupply: ethers.formatUnits(totalSupply, 6),
    paused,
  };
}

// Example: Deposit USDC
async function deposit(amount, receiver) {
  const usdc = new ethers.Contract(
    CONTRACTS.USDC,
    ['function approve(address,uint256) returns (bool)'],
    wallet
  );

  // Approve vault to spend USDC
  const approveTx = await usdc.approve(CONTRACTS.CopyVault, amount);
  await approveTx.wait();

  // Deposit
  const depositTx = await copyVault.deposit(amount, receiver);
  const receipt = await depositTx.wait();

  return receipt;
}

// Example: Get user's share balance
async function getUserShares(userAddress) {
  const shares = await copyVault.balanceOf(userAddress);
  const assets = await copyVault.convertToAssets(shares);

  return {
    shares: ethers.formatUnits(shares, 6),
    assetsValue: ethers.formatUnits(assets, 6),
  };
}
```

### viem (TypeScript)

```typescript
import { createPublicClient, createWalletClient, http, parseUnits, formatUnits } from 'viem';
import { polygon } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';
import CopyVaultABI from './abi/CopyVault.json';
import PositionManagerABI from './abi/PositionManager.json';

const CONTRACTS = {
  CopyVault: '0xEa6ce4437B49e48b0350324c7435c9b9d0A84061' as const,
  PositionManager: '0x766dB1CC757c12ef47749EE90E7770E071396463' as const,
  USDC: '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359' as const,
};

// Setup clients
const publicClient = createPublicClient({
  chain: polygon,
  transport: http(process.env.POLYGON_RPC),
});

const account = privateKeyToAccount(`0x${process.env.PRIVATE_KEY}`);

const walletClient = createWalletClient({
  account,
  chain: polygon,
  transport: http(process.env.POLYGON_RPC),
});

// Read vault state
async function getVaultState() {
  const [totalAssets, totalSupply, paused] = await Promise.all([
    publicClient.readContract({
      address: CONTRACTS.CopyVault,
      abi: CopyVaultABI,
      functionName: 'totalAssets',
    }),
    publicClient.readContract({
      address: CONTRACTS.CopyVault,
      abi: CopyVaultABI,
      functionName: 'totalSupply',
    }),
    publicClient.readContract({
      address: CONTRACTS.CopyVault,
      abi: CopyVaultABI,
      functionName: 'paused',
    }),
  ]);

  return {
    totalAssets: formatUnits(totalAssets as bigint, 6),
    totalSupply: formatUnits(totalSupply as bigint, 6),
    paused,
  };
}

// Deposit USDC
async function deposit(amountUsdc: string, receiver: string) {
  const amount = parseUnits(amountUsdc, 6);

  // Approve
  const approveHash = await walletClient.writeContract({
    address: CONTRACTS.USDC,
    abi: [{ name: 'approve', type: 'function', inputs: [{ type: 'address' }, { type: 'uint256' }], outputs: [{ type: 'bool' }] }],
    functionName: 'approve',
    args: [CONTRACTS.CopyVault, amount],
  });
  await publicClient.waitForTransactionReceipt({ hash: approveHash });

  // Deposit
  const depositHash = await walletClient.writeContract({
    address: CONTRACTS.CopyVault,
    abi: CopyVaultABI,
    functionName: 'deposit',
    args: [amount, receiver as `0x${string}`],
  });

  return publicClient.waitForTransactionReceipt({ hash: depositHash });
}
```

### web3.py (Python)

```python
from web3 import Web3
import json
import os

# Setup
w3 = Web3(Web3.HTTPProvider(os.environ['POLYGON_RPC']))
private_key = os.environ['PRIVATE_KEY']
account = w3.eth.account.from_key(private_key)

CONTRACTS = {
    'CopyVault': '0xEa6ce4437B49e48b0350324c7435c9b9d0A84061',
    'PositionManager': '0x766dB1CC757c12ef47749EE90E7770E071396463',
    'USDC': '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
}

# Load ABIs
with open('abi/CopyVault.json') as f:
    copy_vault_abi = json.load(f)

with open('abi/PositionManager.json') as f:
    position_manager_abi = json.load(f)

# Initialize contracts
copy_vault = w3.eth.contract(
    address=CONTRACTS['CopyVault'],
    abi=copy_vault_abi
)

position_manager = w3.eth.contract(
    address=CONTRACTS['PositionManager'],
    abi=position_manager_abi
)

# Read vault state
def get_vault_state():
    total_assets = copy_vault.functions.totalAssets().call()
    total_supply = copy_vault.functions.totalSupply().call()
    paused = copy_vault.functions.paused().call()

    return {
        'total_assets': total_assets / 1e6,  # USDC has 6 decimals
        'total_supply': total_supply / 1e6,
        'paused': paused,
    }

# Deposit USDC
def deposit(amount_usdc: float, receiver: str):
    amount = int(amount_usdc * 1e6)

    # Build and send approve transaction
    usdc_abi = [{"name": "approve", "type": "function", "inputs": [{"type": "address"}, {"type": "uint256"}], "outputs": [{"type": "bool"}]}]
    usdc = w3.eth.contract(address=CONTRACTS['USDC'], abi=usdc_abi)

    approve_tx = usdc.functions.approve(
        CONTRACTS['CopyVault'],
        amount
    ).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 100000,
        'gasPrice': w3.eth.gas_price,
    })

    signed_approve = w3.eth.account.sign_transaction(approve_tx, private_key)
    approve_hash = w3.eth.send_raw_transaction(signed_approve.rawTransaction)
    w3.eth.wait_for_transaction_receipt(approve_hash)

    # Build and send deposit transaction
    deposit_tx = copy_vault.functions.deposit(
        amount,
        receiver
    ).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 300000,
        'gasPrice': w3.eth.gas_price,
    })

    signed_deposit = w3.eth.account.sign_transaction(deposit_tx, private_key)
    deposit_hash = w3.eth.send_raw_transaction(signed_deposit.rawTransaction)
    receipt = w3.eth.wait_for_transaction_receipt(deposit_hash)

    return receipt

# Get user shares
def get_user_shares(user_address: str):
    shares = copy_vault.functions.balanceOf(user_address).call()
    assets = copy_vault.functions.convertToAssets(shares).call()

    return {
        'shares': shares / 1e6,
        'assets_value': assets / 1e6,
    }
```

---

## Common Operations

### CopyVault Operations

| Operation | Function | Description |
|-----------|----------|-------------|
| Deposit | `deposit(assets, receiver)` | Deposit USDC, receive shares |
| Withdraw | `withdraw(assets, receiver, owner)` | Withdraw specific USDC amount |
| Redeem | `redeem(shares, receiver, owner)` | Redeem shares for USDC |
| Check Balance | `balanceOf(address)` | Get share balance |
| Preview Deposit | `previewDeposit(assets)` | Preview shares for deposit |
| Preview Withdraw | `previewWithdraw(assets)` | Preview shares needed for withdrawal |
| Total Assets | `totalAssets()` | Get total USDC in vault |
| Max Deposit | `maxDeposit(receiver)` | Get max deposit for user |
| Check Paused | `paused()` | Check if vault is paused |

### PositionManager Operations

| Operation | Function | Description |
|-----------|----------|-------------|
| Open Position | `openPosition(conditionId, tokenId, amount, minTokens, isYes)` | Open Polymarket position |
| Close Position | `closePosition(conditionId, tokenAmount, minUsdc)` | Close position |
| Redeem Position | `redeemPosition(conditionId)` | Redeem after market resolution |
| Get Position | `getPosition(conditionId)` | Get position details |
| Get All Positions | `getActivePositions()` | Get all active positions |
| Total Value | `totalPositionValue()` | Get total position value |

---

## Event Listening

### ethers.js Event Listener

```javascript
// Listen for deposits
copyVault.on('Deposit', (sender, owner, assets, shares, event) => {
  console.log('Deposit:', {
    sender,
    owner,
    assets: ethers.formatUnits(assets, 6),
    shares: ethers.formatUnits(shares, 6),
    txHash: event.log.transactionHash,
  });
});

// Listen for withdrawals
copyVault.on('Withdraw', (sender, receiver, owner, assets, shares, event) => {
  console.log('Withdrawal:', {
    sender,
    receiver,
    owner,
    assets: ethers.formatUnits(assets, 6),
    shares: ethers.formatUnits(shares, 6),
  });
});

// Listen for position events
positionManager.on('PositionOpened', (conditionId, tokenId, amount, cost, event) => {
  console.log('Position Opened:', {
    conditionId,
    tokenId: tokenId.toString(),
    amount: amount.toString(),
    cost: ethers.formatUnits(cost, 6),
  });
});
```

### Query Historical Events

```javascript
async function getDepositHistory(fromBlock, toBlock) {
  const filter = copyVault.filters.Deposit();
  const events = await copyVault.queryFilter(filter, fromBlock, toBlock);

  return events.map(event => ({
    sender: event.args.sender,
    owner: event.args.owner,
    assets: ethers.formatUnits(event.args.assets, 6),
    shares: ethers.formatUnits(event.args.shares, 6),
    blockNumber: event.blockNumber,
    txHash: event.transactionHash,
  }));
}
```

---

## Error Handling

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `BelowMinimumDeposit` | Deposit amount < $10 | Increase deposit amount |
| `ExceedsVaultCap` | Vault at max capacity | Wait for withdrawals |
| `ExceedsUserCap` | User at max deposit ($100k) | User has reached limit |
| `InsufficientLiquidity` | Not enough idle USDC | Wait for positions to close |
| `EnforcedPause` | Vault is paused | Withdrawals still work |

### Error Handling Example

```javascript
async function safeDeposit(amount, receiver) {
  try {
    // Check if deposit is possible
    const maxDeposit = await copyVault.maxDeposit(receiver);
    if (amount > maxDeposit) {
      throw new Error(`Amount exceeds max deposit: ${ethers.formatUnits(maxDeposit, 6)} USDC`);
    }

    const receipt = await deposit(amount, receiver);
    return { success: true, receipt };

  } catch (error) {
    // Parse custom errors
    if (error.message.includes('BelowMinimumDeposit')) {
      return { success: false, error: 'Deposit below minimum ($10)' };
    }
    if (error.message.includes('ExceedsVaultCap')) {
      return { success: false, error: 'Vault is at capacity' };
    }
    if (error.message.includes('ExceedsUserCap')) {
      return { success: false, error: 'User deposit limit reached' };
    }
    if (error.message.includes('EnforcedPause')) {
      return { success: false, error: 'Vault is paused' };
    }

    return { success: false, error: error.message };
  }
}
```

---

## Rate Limiting & Best Practices

1. **Use WebSocket connections** for event listening instead of polling
2. **Batch read calls** using multicall when possible
3. **Cache frequently accessed data** (total assets, paused state)
4. **Implement retry logic** for failed transactions
5. **Monitor gas prices** and set appropriate gas limits
6. **Use nonce management** for sequential transactions

```javascript
// Example: Batch reads with multicall
const { Contract } = require('ethers');

async function batchGetVaultData() {
  const multicall = new Contract(
    '0xcA11bde05977b3631167028862bE2a173976CA11', // Polygon Multicall3
    ['function aggregate3(tuple(address target, bool allowFailure, bytes callData)[] calls) view returns (tuple(bool success, bytes returnData)[])'],
    provider
  );

  const calls = [
    {
      target: CONTRACTS.CopyVault,
      allowFailure: false,
      callData: copyVault.interface.encodeFunctionData('totalAssets'),
    },
    {
      target: CONTRACTS.CopyVault,
      allowFailure: false,
      callData: copyVault.interface.encodeFunctionData('totalSupply'),
    },
    {
      target: CONTRACTS.CopyVault,
      allowFailure: false,
      callData: copyVault.interface.encodeFunctionData('paused'),
    },
  ];

  const results = await multicall.aggregate3(calls);
  // Decode results...
}
```

---

## Support

- **Contract Source Code**: [Polygonscan](https://polygonscan.com/address/0xEa6ce4437B49e48b0350324c7435c9b9d0A84061#code)
- **Deployment Details**: See `DEPLOYMENT.md`
