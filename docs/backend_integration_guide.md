# Backend Integration Guide

## Smart Contract Integration for Goblin Market Copy-Trading

This guide provides everything a backend engineer needs to integrate with the Goblin Market smart contracts.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Contract Addresses](#2-contract-addresses)
3. [Contract ABIs](#3-contract-abis)
4. [Authentication & Roles](#4-authentication--roles)
5. [CopyVault Integration](#5-copyvault-integration)
6. [PositionManager Integration](#6-positionmanager-integration)
7. [Event Listening](#7-event-listening)
8. [Error Handling](#8-error-handling)
9. [Transaction Patterns](#9-transaction-patterns)
10. [Code Examples](#10-code-examples)
11. [Security Considerations](#11-security-considerations)
12. [FAQ - Common Questions](#12-faq---common-questions)

---

## 1. Overview

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     BACKEND SERVICES                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   Leader     │    │    Trade     │    │   Position   │       │
│  │   Monitor    │───▶│   Executor   │───▶│   Tracker    │       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
│         │                   │                   │                │
│         │                   ▼                   │                │
│         │          ┌──────────────┐             │                │
│         │          │  Key Mgmt    │             │                │
│         │          │  (KMS/HSM)   │             │                │
│         │          └──────────────┘             │                │
│         │                   │                   │                │
└─────────┼───────────────────┼───────────────────┼────────────────┘
          │                   │                   │
          ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SMART CONTRACTS (Polygon)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐         ┌──────────────┐                      │
│  │  CopyVault   │◀───────▶│  Position    │                      │
│  │  (ERC-4626)  │         │  Manager     │                      │
│  └──────────────┘         └──────────────┘                      │
│         │                        │                               │
│         │                        ▼                               │
│         │                 ┌──────────────┐                      │
│         │                 │  Polymarket  │                      │
│         │                 │  CTF/CLOB    │                      │
│         │                 └──────────────┘                      │
│         ▼                                                        │
│  ┌──────────────┐         ┌──────────────┐                      │
│  │  Timelock    │◀───────▶│   Access     │                      │
│  │              │         │  Controller  │                      │
│  └──────────────┘         └──────────────┘                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Responsibilities

| Service          | Smart Contract             | Interaction                                  |
| ---------------- | -------------------------- | -------------------------------------------- |
| Leader Monitor   | -                          | Watches Polymarket for leader trades         |
| Trade Executor   | CopyVault, PositionManager | Allocates funds, opens/closes positions      |
| Position Tracker | PositionManager            | Monitors position values, handles redemption |
| User API         | CopyVault                  | User deposits, withdrawals, share balances   |

---

## 2. Contract Addresses

### Polygon Mainnet (Production)

```typescript
// To be filled after deployment
const CONTRACTS = {
  COPY_VAULT: "0x...",
  POSITION_MANAGER: "0x...",
  ACCESS_CONTROLLER: "0x...",
  TIMELOCK: "0x...",
  // External contracts
  USDC: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
  POLYMARKET_CTF: "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045",
  POLYMARKET_EXCHANGE: "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E",
};
```

### Polygon Amoy Testnet

```typescript
const CONTRACTS_TESTNET = {
  COPY_VAULT: "0x...",
  POSITION_MANAGER: "0x...",
  ACCESS_CONTROLLER: "0x...",
  TIMELOCK: "0x...",
  USDC: "0x...", // Mock USDC
};
```

---

## 3. Contract ABIs

ABIs are generated during compilation and located in:

```
artifacts/contracts/core/CopyVault.sol/CopyVault.json
artifacts/contracts/core/PositionManager.sol/PositionManager.json
artifacts/contracts/access/AccessController.sol/AccessController.json
artifacts/contracts/access/Timelock.sol/Timelock.json
```

### TypeScript Types

TypeChain generates TypeScript bindings:

```typescript
import { CopyVault } from "../typechain-types/contracts/core/CopyVault";
import { PositionManager } from "../typechain-types/contracts/core/PositionManager";
```

---

## 4. Authentication & Roles

### Role Hierarchy

```
DEFAULT_ADMIN_ROLE (Multisig)
    │
    ├── ADMIN_ROLE
    │   ├── Can: Set parameters, fees, unpause, manage roles
    │   └── Requires: Multisig approval
    │
    ├── EXECUTOR_ROLE (Backend Service)
    │   ├── Can: Allocate funds for trades, open/close positions
    │   └── Granted via: Timelock (48h delay)
    │
    ├── GUARDIAN_ROLE (Security Team)
    │   ├── Can: Pause contracts
    │   └── Cannot: Steal funds, unpause
    │
    └── STRATEGIST_ROLE (Trading Team)
        ├── Can: Add/remove leaders
        └── Cannot: Execute trades
```

### Role Bytes32 Values

```typescript
const ROLES = {
  DEFAULT_ADMIN_ROLE:
    "0x0000000000000000000000000000000000000000000000000000000000000000",
  ADMIN_ROLE: ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE")),
  EXECUTOR_ROLE: ethers.keccak256(ethers.toUtf8Bytes("EXECUTOR_ROLE")),
  GUARDIAN_ROLE: ethers.keccak256(ethers.toUtf8Bytes("GUARDIAN_ROLE")),
  STRATEGIST_ROLE: ethers.keccak256(ethers.toUtf8Bytes("STRATEGIST_ROLE")),
};
```

### Backend Service Setup

Your backend service needs `EXECUTOR_ROLE` on both `CopyVault` and `PositionManager`:

```typescript
// Check if service has executor role
const hasRole = await copyVault.hasRole(ROLES.EXECUTOR_ROLE, serviceAddress);
```

---

## 5. CopyVault Integration

### Key Functions for Backend

#### 5.1 Allocate Funds for Trade

Called by the Trade Executor when mirroring a leader's trade.

```solidity
function allocateForTrade(uint256 amount) external onlyRole(EXECUTOR_ROLE)
```

**Parameters:**

- `amount`: USDC amount to allocate (6 decimals)

**Constraints:**

- Must have `EXECUTOR_ROLE`
- Cannot exceed `totalIdleAssets`
- Cannot exceed `maxTradeSizeBps` of total assets
- Vault must not be paused

**Example:**

```typescript
async function allocateFundsForTrade(
  amount: bigint
): Promise<ContractTransactionResponse> {
  // Validate amount against limits
  const maxTradeSize = await copyVault.maxTradeSizeBps();
  const totalAssets = await copyVault.totalAssets();
  const maxAllowed = (totalAssets * maxTradeSize) / 10000n;

  if (amount > maxAllowed) {
    throw new Error(`Amount ${amount} exceeds max trade size ${maxAllowed}`);
  }

  const idleAssets = await copyVault.totalIdleAssets();
  if (amount > idleAssets) {
    throw new Error(`Insufficient idle assets: ${idleAssets}`);
  }

  return copyVault.allocateForTrade(amount);
}
```

#### 5.2 Return Funds from Position

Called when a position is closed or redeemed.

```solidity
function returnFromPosition(uint256 amount) external onlyRole(EXECUTOR_ROLE)
```

**Parameters:**

- `amount`: USDC amount being returned

**Note:** This is called automatically by PositionManager after closing/redeeming positions.

#### 5.3 Read Vault State

```typescript
// Total assets under management (idle + positions)
const totalAssets = await copyVault.totalAssets();

// Idle assets available for trading
const idleAssets = await copyVault.totalIdleAssets();

// Share price (assets per share)
const sharePrice = totalAssets / (await copyVault.totalSupply());

// Check if paused
const isPaused = await copyVault.paused();

// Get all approved leaders
const leaders = await copyVault.getLeaders();

// Check specific leader
const isApproved = await copyVault.isApprovedLeader(leaderAddress);
```

#### 5.4 User-Facing Functions (for API)

```typescript
// Preview deposit (get expected shares)
const expectedShares = await copyVault.previewDeposit(depositAmount);

// Preview withdrawal (get expected assets)
const expectedAssets = await copyVault.previewRedeem(shareAmount);

// User's share balance
const shares = await copyVault.balanceOf(userAddress);

// User's asset value
const value = await copyVault.previewRedeem(shares);

// Max deposit allowed for user
const maxDeposit = await copyVault.maxDeposit(userAddress);

// Max withdrawal allowed (limited by liquidity)
const maxWithdraw = await copyVault.maxWithdraw(userAddress);
```

---

## 6. PositionManager Integration

### Key Functions for Backend

#### 6.1 Open Position

Called when mirroring a leader's buy trade.

```solidity
function openPosition(
    bytes32 conditionId,    // Polymarket market ID
    uint256 tokenId,        // YES (1) or NO (2) token
    uint256 amount,         // USDC amount to spend
    uint256 minTokens,      // Minimum tokens (slippage protection)
    bool isYes              // true for YES, false for NO
) external onlyRole(EXECUTOR_ROLE) returns (uint256 tokensReceived)
```

**Example:**

```typescript
interface TradeSignal {
  conditionId: string; // Polymarket condition ID (hex)
  tokenId: bigint; // 1 for YES, 2 for NO
  amount: bigint; // USDC amount
  isYes: boolean;
}

async function openPosition(signal: TradeSignal): Promise<bigint> {
  // Calculate min tokens with slippage tolerance (e.g., 2%)
  const currentPrice = await getPolymarketPrice(
    signal.conditionId,
    signal.tokenId
  );
  const expectedTokens = (signal.amount * 1000000n) / currentPrice;
  const minTokens = (expectedTokens * 98n) / 100n; // 2% slippage

  const tx = await positionManager.openPosition(
    signal.conditionId,
    signal.tokenId,
    signal.amount,
    minTokens,
    signal.isYes
  );

  const receipt = await tx.wait();

  // Parse PositionOpened event for actual tokens received
  const event = receipt.logs.find(
    (log) =>
      log.topics[0] ===
      positionManager.interface.getEvent("PositionOpened").topicHash
  );

  const decoded = positionManager.interface.decodeEventLog(
    "PositionOpened",
    event.data,
    event.topics
  );

  return decoded.tokensReceived;
}
```

#### 6.2 Close Position

Called when mirroring a leader's sell trade.

```solidity
function closePosition(
    bytes32 conditionId,    // Polymarket market ID
    uint256 tokenAmount,    // Tokens to sell
    uint256 minUsdc         // Minimum USDC (slippage protection)
) external onlyRole(EXECUTOR_ROLE) returns (uint256 usdcReceived)
```

**Example:**

```typescript
async function closePosition(
  conditionId: string,
  tokenAmount: bigint,
  slippageBps: number = 200 // 2% default
): Promise<bigint> {
  const position = await positionManager.getPosition(conditionId);

  if (position.amount < tokenAmount) {
    throw new Error("Insufficient position size");
  }

  // Calculate min USDC with slippage
  const currentPrice = await getPolymarketPrice(conditionId, position.tokenId);
  const expectedUsdc = (tokenAmount * currentPrice) / 1000000n;
  const minUsdc = (expectedUsdc * BigInt(10000 - slippageBps)) / 10000n;

  const tx = await positionManager.closePosition(
    conditionId,
    tokenAmount,
    minUsdc
  );

  const receipt = await tx.wait();

  // Parse PositionClosed event
  const event = receipt.logs.find(
    (log) =>
      log.topics[0] ===
      positionManager.interface.getEvent("PositionClosed").topicHash
  );

  const decoded = positionManager.interface.decodeEventLog(
    "PositionClosed",
    event.data,
    event.topics
  );

  return decoded.usdcReceived;
}
```

#### 6.3 Redeem Position (After Market Resolution)

```solidity
function redeemPosition(
    bytes32 conditionId
) external onlyRole(EXECUTOR_ROLE) returns (uint256 usdcReceived)
```

**Example:**

```typescript
async function redeemResolvedPosition(conditionId: string): Promise<bigint> {
  // Check if market is resolved on Polymarket first
  const isResolved = await checkPolymarketResolution(conditionId);

  if (!isResolved) {
    throw new Error("Market not yet resolved");
  }

  const tx = await positionManager.redeemPosition(conditionId);
  const receipt = await tx.wait();

  // Parse PositionRedeemed event
  const event = receipt.logs.find(
    (log) =>
      log.topics[0] ===
      positionManager.interface.getEvent("PositionRedeemed").topicHash
  );

  const decoded = positionManager.interface.decodeEventLog(
    "PositionRedeemed",
    event.data,
    event.topics
  );

  console.log(
    `Redeemed ${decoded.tokensRedeemed} tokens for ${decoded.usdcReceived} USDC`
  );

  return decoded.usdcReceived;
}
```

#### 6.4 Read Position State

```typescript
// Get single position
const position = await positionManager.getPosition(conditionId);
// Returns: { conditionId, tokenId, amount, avgEntryPrice, costBasis, openedAt, isYes }

// Get all active positions
const positions = await positionManager.getActivePositions();

// Get position count
const count = await positionManager.activePositionCount();

// Get position value
const value = await positionManager.getPositionValue(conditionId);

// Get total position value
const totalValue = await positionManager.totalPositionValue();
```

---

## 7. Event Listening

### CopyVault Events

```typescript
// Deposit event - user deposited funds
copyVault.on("Deposit", (sender, owner, assets, shares) => {
  console.log(
    `Deposit: ${owner} deposited ${assets} USDC, received ${shares} shares`
  );
});

// Withdraw event - user withdrew funds
copyVault.on("Withdraw", (sender, receiver, owner, assets, shares) => {
  console.log(
    `Withdraw: ${owner} withdrew ${assets} USDC, burned ${shares} shares`
  );
});

// TradeAllocated event - funds allocated for trading
copyVault.on("TradeAllocated", (amount) => {
  console.log(`Trade allocated: ${amount} USDC`);
});

// PositionReturned event - funds returned from position
copyVault.on("PositionReturned", (amount) => {
  console.log(`Position returned: ${amount} USDC`);
});

// Leader events
copyVault.on("LeaderAdded", (leader) => {
  console.log(`Leader added: ${leader}`);
});

copyVault.on("LeaderRemoved", (leader) => {
  console.log(`Leader removed: ${leader}`);
});

// Pause events
copyVault.on("Paused", (account) => {
  console.log(`Vault paused by: ${account}`);
  // CRITICAL: Stop all trading operations
});

copyVault.on("Unpaused", (account) => {
  console.log(`Vault unpaused by: ${account}`);
  // Resume trading operations
});
```

### PositionManager Events

```typescript
// Position opened
positionManager.on(
  "PositionOpened",
  (conditionId, tokenId, tokensReceived, usdcSpent) => {
    console.log(
      `Position opened on ${conditionId}: ${tokensReceived} tokens for ${usdcSpent} USDC`
    );
    // Update position database
  }
);

// Position closed
positionManager.on(
  "PositionClosed",
  (conditionId, tokensSold, usdcReceived) => {
    console.log(
      `Position closed on ${conditionId}: sold ${tokensSold} tokens for ${usdcReceived} USDC`
    );
    // Update position database
  }
);

// Position redeemed (after market resolution)
positionManager.on(
  "PositionRedeemed",
  (conditionId, tokensRedeemed, usdcReceived) => {
    console.log(
      `Position redeemed on ${conditionId}: ${tokensRedeemed} tokens → ${usdcReceived} USDC`
    );
    // Update position database, calculate P&L
  }
);
```

### Event Subscription Service

```typescript
import { ethers } from "ethers";

class EventSubscriptionService {
  private provider: ethers.Provider;
  private copyVault: CopyVault;
  private positionManager: PositionManager;

  constructor(config: Config) {
    this.provider = new ethers.WebSocketProvider(config.wsRpcUrl);
    this.copyVault = CopyVault__factory.connect(
      config.copyVaultAddress,
      this.provider
    );
    this.positionManager = PositionManager__factory.connect(
      config.positionManagerAddress,
      this.provider
    );
  }

  async start(): Promise<void> {
    // Subscribe to all relevant events
    this.subscribeToVaultEvents();
    this.subscribeToPositionEvents();

    // Handle reconnection
    this.provider.on("error", this.handleProviderError.bind(this));
  }

  private subscribeToVaultEvents(): void {
    this.copyVault.on("Paused", this.handlePause.bind(this));
    this.copyVault.on("Unpaused", this.handleUnpause.bind(this));
    this.copyVault.on("TradeAllocated", this.handleTradeAllocated.bind(this));
    this.copyVault.on("Deposit", this.handleDeposit.bind(this));
    this.copyVault.on("Withdraw", this.handleWithdraw.bind(this));
  }

  private subscribeToPositionEvents(): void {
    this.positionManager.on(
      "PositionOpened",
      this.handlePositionOpened.bind(this)
    );
    this.positionManager.on(
      "PositionClosed",
      this.handlePositionClosed.bind(this)
    );
    this.positionManager.on(
      "PositionRedeemed",
      this.handlePositionRedeemed.bind(this)
    );
  }

  private async handlePause(account: string): Promise<void> {
    console.error("CRITICAL: Vault paused!");
    // Emit to monitoring system
    // Stop trade executor
    await this.alertService.sendCritical({
      type: "VAULT_PAUSED",
      pausedBy: account,
      timestamp: Date.now(),
    });
  }

  private handleProviderError(error: Error): void {
    console.error("Provider error:", error);
    // Implement reconnection logic
    setTimeout(() => this.reconnect(), 5000);
  }
}
```

---

## 8. Error Handling

### Custom Errors

The contracts use custom errors for gas efficiency. Handle them appropriately:

```typescript
// CopyVault errors
const VAULT_ERRORS = {
  BelowMinimumDeposit: "Deposit amount below minimum",
  ExceedsVaultCap: "Would exceed vault deposit cap",
  ExceedsUserCap: "Would exceed per-user deposit cap",
  InsufficientLiquidity: "Not enough idle assets for withdrawal",
  ExceedsMaxTradeSize: "Trade size exceeds maximum allowed",
  InsufficientIdleAssets: "Not enough idle assets for trade",
  LeaderAlreadyApproved: "Leader already in approved list",
  LeaderNotApproved: "Leader not in approved list",
  FeeExceedsMaximum: "Fee percentage too high",
  ZeroAddress: "Cannot use zero address",
  ZeroAmount: "Amount cannot be zero",
};

// PositionManager errors
const POSITION_ERRORS = {
  MaxPositionsReached: "Already at maximum concurrent positions",
  ExceedsPositionSizeLimit: "Position size exceeds limit",
  ExceedsExposureLimit: "Would exceed total exposure limit",
  PositionNotFound: "No position for this condition ID",
  InsufficientPosition: "Not enough tokens in position",
  SlippageExceeded: "Slippage tolerance exceeded",
  ZeroAddress: "Cannot use zero address",
  ZeroAmount: "Amount cannot be zero",
  OnlyVault: "Only vault can call this function",
};
```

### Error Handling Example

```typescript
import { ethers } from "ethers";

async function executeTradeWithErrorHandling(
  signal: TradeSignal
): Promise<void> {
  try {
    const tx = await positionManager.openPosition(
      signal.conditionId,
      signal.tokenId,
      signal.amount,
      signal.minTokens,
      signal.isYes
    );

    await tx.wait();
  } catch (error: any) {
    // Parse custom error
    if (error.code === "CALL_EXCEPTION") {
      const errorData = error.data;

      // Decode custom error
      try {
        const decodedError = positionManager.interface.parseError(errorData);

        switch (decodedError?.name) {
          case "MaxPositionsReached":
            console.error("Max positions reached - cannot open new position");
            // Potentially close oldest position first
            break;

          case "SlippageExceeded":
            console.error("Slippage exceeded - price moved too much");
            // Retry with higher slippage or skip
            break;

          case "InsufficientIdleAssets":
            console.error("Not enough idle assets in vault");
            // Wait for withdrawals or position closures
            break;

          default:
            console.error("Contract error:", decodedError?.name);
        }
      } catch {
        console.error("Unknown contract error:", errorData);
      }
    } else {
      // Network or other error
      console.error("Transaction error:", error.message);
    }

    // Log to monitoring
    await this.alertService.sendError({
      type: "TRADE_EXECUTION_FAILED",
      signal,
      error: error.message,
    });
  }
}
```

---

## 9. Transaction Patterns

### Gas Estimation

```typescript
async function estimateGasWithBuffer(
  contract: ethers.Contract,
  method: string,
  args: any[],
  bufferPercent: number = 20
): Promise<bigint> {
  const estimated = await contract[method].estimateGas(...args);
  return estimated + (estimated * BigInt(bufferPercent)) / 100n;
}

// Usage
const gasLimit = await estimateGasWithBuffer(positionManager, "openPosition", [
  conditionId,
  tokenId,
  amount,
  minTokens,
  isYes,
]);

const tx = await positionManager.openPosition(
  conditionId,
  tokenId,
  amount,
  minTokens,
  isYes,
  { gasLimit }
);
```

### Transaction Retry Logic

```typescript
async function executeWithRetry<T>(
  fn: () => Promise<T>,
  maxRetries: number = 3,
  delayMs: number = 1000
): Promise<T> {
  let lastError: Error | undefined;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error: any) {
      lastError = error;

      // Don't retry on certain errors
      if (error.code === "CALL_EXCEPTION") {
        throw error; // Contract reverted - don't retry
      }

      if (error.code === "NONCE_EXPIRED") {
        // Nonce issue - wait and retry
        console.log(`Nonce expired, retrying... (attempt ${attempt})`);
      }

      if (attempt < maxRetries) {
        await new Promise((resolve) => setTimeout(resolve, delayMs * attempt));
      }
    }
  }

  throw lastError;
}
```

### Nonce Management

```typescript
class NonceManager {
  private nonce: number | null = null;
  private mutex = new Mutex();

  constructor(private signer: ethers.Signer) {}

  async getNextNonce(): Promise<number> {
    return this.mutex.runExclusive(async () => {
      if (this.nonce === null) {
        this.nonce = await this.signer.getNonce();
      } else {
        this.nonce++;
      }
      return this.nonce;
    });
  }

  async resetNonce(): Promise<void> {
    return this.mutex.runExclusive(async () => {
      this.nonce = null;
    });
  }
}
```

---

## 10. Code Examples

### Complete Trade Executor Service

```typescript
import { ethers } from "ethers";
import { CopyVault, PositionManager } from "../typechain-types";

interface TradeSignal {
  leaderAddress: string;
  conditionId: string;
  tokenId: bigint;
  side: "BUY" | "SELL";
  amount: bigint;
  price: string;
}

interface ExecutionResult {
  success: boolean;
  txHash?: string;
  tokensTraded?: bigint;
  error?: string;
}

export class TradeExecutorService {
  private copyVault: CopyVault;
  private positionManager: PositionManager;
  private signer: ethers.Signer;

  constructor(
    copyVaultAddress: string,
    positionManagerAddress: string,
    signer: ethers.Signer
  ) {
    this.signer = signer;
    this.copyVault = CopyVault__factory.connect(copyVaultAddress, signer);
    this.positionManager = PositionManager__factory.connect(
      positionManagerAddress,
      signer
    );
  }

  async executeTrade(signal: TradeSignal): Promise<ExecutionResult> {
    console.log(`Executing ${signal.side} trade on ${signal.conditionId}`);

    // Check if vault is paused
    if (await this.copyVault.paused()) {
      return { success: false, error: "Vault is paused" };
    }

    // Check if leader is approved
    if (!(await this.copyVault.isApprovedLeader(signal.leaderAddress))) {
      return { success: false, error: "Leader not approved" };
    }

    try {
      if (signal.side === "BUY") {
        return await this.executeBuy(signal);
      } else {
        return await this.executeSell(signal);
      }
    } catch (error: any) {
      console.error("Trade execution failed:", error);
      return { success: false, error: error.message };
    }
  }

  private async executeBuy(signal: TradeSignal): Promise<ExecutionResult> {
    // Calculate vault's proportional trade size
    const vaultAmount = await this.calculateVaultAmount(signal);

    if (vaultAmount === 0n) {
      return { success: false, error: "Calculated amount is zero" };
    }

    // Check idle assets
    const idleAssets = await this.copyVault.totalIdleAssets();
    if (vaultAmount > idleAssets) {
      return { success: false, error: "Insufficient idle assets" };
    }

    // Allocate funds from vault to position manager
    const allocateTx = await this.copyVault.allocateForTrade(vaultAmount);
    await allocateTx.wait();

    // Calculate slippage-protected min tokens
    const price = parseFloat(signal.price);
    const expectedTokens = Number(vaultAmount) / price;
    const minTokens = BigInt(Math.floor(expectedTokens * 0.98)); // 2% slippage

    // Open position
    const isYes = signal.tokenId === 1n;
    const openTx = await this.positionManager.openPosition(
      signal.conditionId,
      signal.tokenId,
      vaultAmount,
      minTokens,
      isYes
    );

    const receipt = await openTx.wait();

    // Parse tokens received from event
    const event = receipt?.logs.find((log) => {
      try {
        return (
          this.positionManager.interface.parseLog({
            topics: log.topics as string[],
            data: log.data,
          })?.name === "PositionOpened"
        );
      } catch {
        return false;
      }
    });

    let tokensReceived = 0n;
    if (event) {
      const parsed = this.positionManager.interface.parseLog({
        topics: event.topics as string[],
        data: event.data,
      });
      tokensReceived = parsed?.args.tokensReceived || 0n;
    }

    return {
      success: true,
      txHash: receipt?.hash,
      tokensTraded: tokensReceived,
    };
  }

  private async executeSell(signal: TradeSignal): Promise<ExecutionResult> {
    // Get current position
    const position = await this.positionManager.getPosition(signal.conditionId);

    if (position.amount === 0n) {
      return { success: false, error: "No position to sell" };
    }

    // Calculate tokens to sell (proportional to leader's sell)
    const tokensToSell = await this.calculateTokensToSell(
      signal,
      position.amount
    );

    // Calculate min USDC with slippage protection
    const price = parseFloat(signal.price);
    const expectedUsdc = Number(tokensToSell) * price;
    const minUsdc = BigInt(Math.floor(expectedUsdc * 0.98)); // 2% slippage

    // Close position
    const closeTx = await this.positionManager.closePosition(
      signal.conditionId,
      tokensToSell,
      minUsdc
    );

    const receipt = await closeTx.wait();

    return {
      success: true,
      txHash: receipt?.hash,
      tokensTraded: tokensToSell,
    };
  }

  private async calculateVaultAmount(signal: TradeSignal): Promise<bigint> {
    // Get vault's total assets
    const totalAssets = await this.copyVault.totalAssets();

    // Get leader's portfolio size (from your leader tracking database)
    const leaderPortfolioSize = await this.getLeaderPortfolioSize(
      signal.leaderAddress
    );

    // Calculate proportional trade size
    const ratio = Number(signal.amount) / leaderPortfolioSize;
    const vaultAmount = BigInt(Math.floor(Number(totalAssets) * ratio));

    // Apply max trade size limit
    const maxTradeSizeBps = await this.copyVault.maxTradeSizeBps();
    const maxAmount = (totalAssets * maxTradeSizeBps) / 10000n;

    return vaultAmount > maxAmount ? maxAmount : vaultAmount;
  }

  private async calculateTokensToSell(
    signal: TradeSignal,
    positionAmount: bigint
  ): Promise<bigint> {
    // Calculate proportional amount to sell
    // This logic should match your copy-trading strategy
    return positionAmount; // For now, sell entire position
  }

  private async getLeaderPortfolioSize(leaderAddress: string): Promise<number> {
    // Implement: fetch from your leader tracking database
    return 100000; // Placeholder
  }
}
```

### Position Monitoring Service

```typescript
export class PositionMonitorService {
  private positionManager: PositionManager;
  private db: Database;

  constructor(
    positionManagerAddress: string,
    provider: ethers.Provider,
    db: Database
  ) {
    this.positionManager = PositionManager__factory.connect(
      positionManagerAddress,
      provider
    );
    this.db = db;
  }

  async syncPositions(): Promise<void> {
    const positions = await this.positionManager.getActivePositions();

    for (const position of positions) {
      const currentValue = await this.positionManager.getPositionValue(
        position.conditionId
      );
      const pnl = currentValue - position.costBasis;
      const pnlPercent = (Number(pnl) / Number(position.costBasis)) * 100;

      await this.db.positions.upsert({
        conditionId: position.conditionId,
        tokenId: position.tokenId.toString(),
        amount: position.amount.toString(),
        avgEntryPrice: position.avgEntryPrice.toString(),
        costBasis: position.costBasis.toString(),
        currentValue: currentValue.toString(),
        unrealizedPnl: pnl.toString(),
        unrealizedPnlPercent: pnlPercent,
        isYes: position.isYes,
        openedAt: new Date(Number(position.openedAt) * 1000),
        updatedAt: new Date(),
      });
    }
  }

  async checkForResolutions(): Promise<void> {
    const positions = await this.positionManager.getActivePositions();

    for (const position of positions) {
      const isResolved = await this.checkPolymarketResolution(
        position.conditionId
      );

      if (isResolved) {
        console.log(
          `Market ${position.conditionId} is resolved, queueing redemption`
        );
        await this.queueRedemption(position.conditionId);
      }
    }
  }

  private async checkPolymarketResolution(
    conditionId: string
  ): Promise<boolean> {
    // Check Polymarket API or CTF contract for resolution status
    // Implement based on Polymarket's CTF interface
    return false;
  }

  private async queueRedemption(conditionId: string): Promise<void> {
    // Add to redemption queue for trade executor to process
    await this.db.redemptionQueue.create({
      conditionId,
      status: "pending",
      createdAt: new Date(),
    });
  }
}
```

---

## 11. Security Considerations

### Key Management

**DO:**

- Use AWS KMS, HSM, or MPC (Fireblocks) for private keys
- Never expose private keys in code or logs
- Implement key rotation procedures
- Use separate keys for different environments

**DON'T:**

- Store private keys in environment variables on servers
- Use the same key for testnet and mainnet
- Log transaction signing details

### Rate Limiting

```typescript
class RateLimiter {
  private lastTradeTime: number = 0;
  private tradesInLastHour: number = 0;
  private readonly MIN_TIME_BETWEEN_TRADES_MS = 10000; // 10 seconds
  private readonly MAX_TRADES_PER_HOUR = 50;

  canExecuteTrade(): boolean {
    const now = Date.now();

    // Check minimum time between trades
    if (now - this.lastTradeTime < this.MIN_TIME_BETWEEN_TRADES_MS) {
      return false;
    }

    // Check hourly rate limit
    if (this.tradesInLastHour >= this.MAX_TRADES_PER_HOUR) {
      return false;
    }

    return true;
  }

  recordTrade(): void {
    this.lastTradeTime = Date.now();
    this.tradesInLastHour++;

    // Reset hourly counter after an hour
    setTimeout(() => {
      this.tradesInLastHour = Math.max(0, this.tradesInLastHour - 1);
    }, 3600000);
  }
}
```

### Circuit Breakers

```typescript
interface CircuitBreakerConfig {
  maxHourlyDrawdownPercent: number; // e.g., 10
  maxDailyDrawdownPercent: number; // e.g., 20
  cooldownPeriodMs: number; // e.g., 3600000 (1 hour)
}

class CircuitBreaker {
  private isTripped: boolean = false;
  private tripTime: number = 0;

  constructor(private config: CircuitBreakerConfig) {}

  async check(currentTVL: bigint, historicalTVL: bigint): Promise<boolean> {
    if (this.isTripped) {
      if (Date.now() - this.tripTime < this.config.cooldownPeriodMs) {
        return false; // Still in cooldown
      }
      this.isTripped = false;
    }

    const drawdownPercent =
      (Number(historicalTVL - currentTVL) / Number(historicalTVL)) * 100;

    if (drawdownPercent > this.config.maxHourlyDrawdownPercent) {
      await this.trip("HOURLY_DRAWDOWN");
      return false;
    }

    return true;
  }

  private async trip(reason: string): Promise<void> {
    this.isTripped = true;
    this.tripTime = Date.now();

    // Alert the team
    console.error(`Circuit breaker tripped: ${reason}`);

    // Optionally pause the vault
    // await copyVault.pause();
  }
}
```

### Monitoring Checklist

- [ ] Monitor vault TVL for sudden changes
- [ ] Alert on large withdrawals (>10% of TVL)
- [ ] Track trade execution success rate
- [ ] Monitor gas prices and adjust accordingly
- [ ] Alert on contract pause events
- [ ] Track position P&L and exposure
- [ ] Monitor leader trading patterns for anomalies

---

## 12. FAQ - Common Questions

This section answers frequently asked questions about the smart contract architecture and integration.

### 12.1 Why is the leader list stored on-chain? Who updates it?

**Why on-chain?** The leader list is stored on-chain (`approvedLeaders` mapping + `leaderList` array in `CopyVault.sol`) for security and transparency:

- Anyone can verify which leaders are approved
- Prevents unauthorized trade execution (backend checks `isApprovedLeader()` before mirroring)
- Audit trail of leader changes via `LeaderAdded`/`LeaderRemoved` events

**Who updates it?** Only addresses with `STRATEGIST_ROLE` can call `addLeader()` or `removeLeader()`. This is typically a multisig or admin wallet, NOT the backend service.

**Spam protection:** Users cannot spam the leader list because:

1. Only `STRATEGIST_ROLE` can modify leaders (not users)
2. The backend service has `EXECUTOR_ROLE` (for trades), NOT `STRATEGIST_ROLE`
3. Role separation is intentional - strategists curate leaders, executors execute trades

### 12.2 Why doesn't `returnFromPosition` track per-user or per-leader P&L?

The `returnFromPosition` function only updates `totalIdleAssets`:

```solidity
function returnFromPosition(uint256 amount) external onlyRole(EXECUTOR_ROLE) nonReentrant {
    totalIdleAssets += amount;
    emit PositionReturned(amount);
}
```

**The contract intentionally does NOT track per-user or per-leader P&L on-chain** because:

1. This is a **pooled vault** (ERC-4626) - all users share profits/losses proportionally via share price
2. Individual tracking would be extremely gas-expensive
3. Per-leader attribution should be tracked **in the backend database**

**Backend responsibility:** Your backend should:

- Store which leader triggered each position (in your DB, not on-chain)
- Calculate per-leader performance metrics off-chain
- Track copy relationships in Prisma/PostgreSQL

### 12.3 Why use a vault contract instead of depositing directly to the executor wallet?

The contract DOES interact with Polymarket - the `PositionManager` has:

```solidity
IConditionalTokens public immutable ctf;  // Polymarket CTF
address public immutable exchange;         // Polymarket CLOB
```

**Why use a contract instead of direct wallet deposit?**

1. **Security**: Users' funds are in a non-custodial vault, not a backend-controlled EOA
2. **Transparency**: All trades are auditable on-chain
3. **Share accounting**: ERC-4626 handles fair share distribution automatically
4. **Limits enforcement**: On-chain limits (max trade size 5%, max exposure 80%) prevent rogue backend
5. **Pausability**: Guardian can pause if backend is compromised

The gas cost tradeoff is intentional - the security benefits outweigh gas savings.

### 12.4 What's the difference between `withdraw` and `redeem`?

Both functions allow users to exit the vault, but with different inputs:

| Function                           | Input       | Output        | Use Case                        |
| ---------------------------------- | ----------- | ------------- | ------------------------------- |
| `withdraw(assets, receiver, owner)` | USDC amount | Shares burned | "I want exactly $1000 back"     |
| `redeem(shares, receiver, owner)`   | Share amount | USDC received | "I want to redeem all my shares" |

**Key difference:**

- `withdraw`: User specifies exact USDC amount, contract calculates shares to burn
- `redeem`: User specifies exact shares to burn, contract calculates USDC to return

Both have the same liquidity constraint: reverts with `InsufficientLiquidity` if `assets > totalIdleAssets`.

### 12.5 Is there an on-chain incentive mechanism for leaders?

**Currently no on-chain leader incentives.** The contract has fee infrastructure (`performanceFee`, `managementFee`, `feeRecipient`) but these go to the protocol/admin, not leaders.

**Leader incentives should be implemented off-chain** in the backend:

- Track performance attribution per leader
- Calculate leader commissions from performance fees
- Pay leaders separately (can be off-chain or via a separate mechanism)

This is a product decision, not a contract limitation. If you want on-chain leader fees, the contract would need modification.

### 12.6 Do `openPosition`, `closePosition`, `redeemPosition` validate against the leader list?

**No.** These functions only check for `EXECUTOR_ROLE`:

```solidity
function openPosition(...) external onlyRole(EXECUTOR_ROLE) ...
function closePosition(...) external onlyRole(EXECUTOR_ROLE) ...
function redeemPosition(...) external onlyRole(EXECUTOR_ROLE) ...
```

These functions:

- Only verify the caller has `EXECUTOR_ROLE` (the backend service)
- Have **no concept of leader/follower** on-chain
- Don't validate against the leader list

**The copy-trading logic lives entirely in the backend:**

1. Backend monitors leaders on Polymarket (off-chain)
2. Backend decides when to mirror trades (off-chain)
3. Backend calls `allocateForTrade()` then `openPosition()` (on-chain)

**Why?** Because Polymarket's order book (CLOB) is off-chain. The contract can't watch leaders directly - that's the backend's job.

### 12.7 Architecture Summary: What lives on-chain vs off-chain?

```
┌─────────────────────────────────────────────────────────────────┐
│                    BACKEND (Off-Chain)                           │
│  - Monitor Polymarket for leader trades                          │
│  - Track leader/follower relationships (DB)                      │
│  - Calculate per-leader P&L (DB)                                 │
│  - Decide trade amounts and timing                               │
│  - Execute trades via EXECUTOR_ROLE                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  SMART CONTRACTS (On-Chain)                      │
│  - Custody of user funds (ERC-4626 vault)                        │
│  - Share accounting (fair distribution)                          │
│  - Trade execution limits (max size, exposure)                   │
│  - Leader whitelist (STRATEGIST manages)                         │
│  - Emergency pause (GUARDIAN role)                               │
│  - Actual Polymarket trades via CTF/CLOB                         │
└─────────────────────────────────────────────────────────────────┘
```

The contract is the **execution and custody layer**, while the backend is the **intelligence and attribution layer**.

---

## Appendix: Data Types

### Position Struct

```typescript
interface Position {
  conditionId: string; // bytes32 - Polymarket market ID
  tokenId: bigint; // uint256 - Token ID (1=YES, 2=NO)
  amount: bigint; // uint256 - Number of tokens held
  avgEntryPrice: bigint; // uint256 - Average entry price (6 decimals)
  costBasis: bigint; // uint256 - Total USDC spent
  openedAt: bigint; // uint64 - Unix timestamp
  isYes: boolean; // bool - true for YES, false for NO
}
```

### USDC Decimals

USDC on Polygon uses **6 decimals**:

```typescript
const ONE_USDC = 1_000_000n; // 1 USDC
const ONE_CENT = 10_000n; // $0.01
const ONE_THOUSAND = 1_000_000_000n; // $1,000
```

---

## Contact

For questions about smart contract integration, contact the smart contract team.

For Polymarket API questions, refer to [Polymarket Documentation](https://docs.polymarket.com).
