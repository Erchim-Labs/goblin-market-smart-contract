# Goblin Market: Copy-Trading Architecture

## Technical Documentation v1.0

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Overview](#2-system-overview)
3. [Smart Contract Architecture](#3-smart-contract-architecture)
4. [Backend Services](#4-backend-services)
5. [Security Architecture](#5-security-architecture)
6. [User Flows](#6-user-flows)
7. [Trade Execution](#7-trade-execution)
8. [Position Management](#8-position-management)
9. [Risk Management](#9-risk-management)
10. [API Specifications](#10-api-specifications)
11. [Deployment Guide](#11-deployment-guide)
12. [Emergency Procedures](#12-emergency-procedures)
13. [Appendix](#13-appendix)

---

## 1. Executive Summary

### 1.1 Purpose

Goblin Market Copy-Trading is a vault-based system that allows users to automatically mirror the Polymarket trading strategies of expert traders ("Leaders"). Users deposit USDC into a vault, and when a Leader executes a trade on Polymarket, the vault automatically executes the same trade proportionally.

### 1.2 Key Features

- **Automated Copy-Trading**: Mirror Leader trades in real-time
- **Vault Model**: Pooled funds for efficient execution
- **Real Polymarket Positions**: Not synthetic - actual positions on Polymarket
- **Non-Lock-Up**: Users can withdraw anytime
- **Professional Security**: Multi-sig, timelocks, audited contracts

### 1.3 Architecture Decision: Vault Model

We chose the **Vault Model** over alternatives because:

| Factor            | Per-User Execution        | Vault Model (Chosen)   | Synthetic |
| ----------------- | ------------------------- | ---------------------- | --------- |
| UX Complexity     | High (API setup per user) | Low (just deposit)     | Low       |
| Real Positions    | Yes                       | Yes                    | No        |
| Liquidity         | Fragmented                | Aggregated             | N/A       |
| Execution Quality | Variable                  | Better (larger orders) | N/A       |
| Counterparty Risk | None                      | None                   | Protocol  |
| Implementation    | Complex                   | Medium                 | Simple    |

### 1.4 Technology Stack

- **Blockchain**: Polygon (same as Polymarket)
- **Token**: USDC
- **Smart Contracts**: Solidity 0.8.20+, Foundry, OpenZeppelin
- **Backend**: TypeScript/Node.js
- **Key Management**: AWS KMS / Fireblocks MPC
- **Frontend**: Next.js, wagmi, viem

---

## 2. System Overview

### 2.1 High-Level Architecture

```
+------------------------------------------------------------------+
|                     GOBLIN COPY-TRADING SYSTEM                    |
+------------------------------------------------------------------+
|                                                                   |
|   USERS                         SMART CONTRACTS (Polygon)         |
|   +----------+                  +-----------------------------+   |
|   | Follower |--deposit/------->|        CopyVault.sol        |   |
|   | Wallets  |  withdraw        |  - User deposits (USDC)     |   |
|   +----------+                  |  - Share accounting         |   |
|                                 |  - Access control           |   |
|                                 +-------------+---------------+   |
|                                               |                   |
|                                               v                   |
|                                 +-----------------------------+   |
|                                 |    PositionManager.sol      |   |
|                                 |  - Holds outcome tokens     |   |
|                                 |  - Tracks positions         |   |
|                                 |  - Redeems on settlement    |   |
|                                 +-------------+---------------+   |
|                                               |                   |
+-----------------------------------------------+-------------------+
                                                |
                                                v
+------------------------------------------------------------------+
|                        BACKEND SERVICES                           |
+------------------------------------------------------------------+
|                                                                   |
|   +------------------+     +------------------+                   |
|   | Leader Monitor   |---->| Trade Executor   |                   |
|   | - WebSocket sub  |     | - Order building |                   |
|   | - Trade detection|     | - CLOB submission|                   |
|   +------------------+     +--------+---------+                   |
|                                     |                             |
|                                     v                             |
|                          +-------------------+                    |
|                          | Secure Key Mgmt   |                    |
|                          | (HSM / KMS / MPC) |                    |
|                          +-------------------+                    |
|                                                                   |
+------------------------------------------------------------------+
                                    |
                                    v
+------------------------------------------------------------------+
|                          POLYMARKET                               |
+------------------------------------------------------------------+
|                                                                   |
|   +------------------+     +------------------+                   |
|   |    CLOB API      |     |   CTF Exchange   |                   |
|   | - Order matching |     | - Settlement     |                   |
|   | - Market data    |     | - Token transfer |                   |
|   +------------------+     +------------------+                   |
|                                                                   |
+------------------------------------------------------------------+
```

### 2.2 Component Summary

| Component           | Purpose                         | Technology                       |
| ------------------- | ------------------------------- | -------------------------------- |
| CopyVault.sol       | User deposits, share accounting | Solidity, ERC-4626               |
| PositionManager.sol | Hold & manage Polymarket tokens | Solidity, ERC-1155               |
| Leader Monitor      | Detect Leader trades            | Node.js, WebSocket               |
| Trade Executor      | Execute trades on CLOB          | Node.js, @polymarket/clob-client |
| Key Management      | Secure transaction signing      | AWS KMS / Fireblocks             |
| Frontend            | User interface                  | Next.js, wagmi                   |

### 2.3 Data Flow

```
1. User deposits USDC
   User Wallet --> approve() --> USDC Contract
   User Wallet --> deposit() --> CopyVault
   CopyVault --> mint shares --> User receives vault shares

2. Leader trades on Polymarket
   Leader Wallet --> trade --> Polymarket
   Leader Monitor --> detects trade via WebSocket

3. Vault mirrors trade
   Trade Executor --> builds order
   Key Management --> signs order
   Trade Executor --> submits to Polymarket CLOB
   Polymarket --> settles --> tokens to PositionManager

4. User withdraws
   User --> withdraw() --> CopyVault
   CopyVault --> calculates pro-rata share
   CopyVault --> burns shares, transfers USDC
```

---

## 3. Smart Contract Architecture

### 3.1 Contract Overview

```
contracts/
├── core/
│   ├── CopyVault.sol           # Main vault contract (ERC-4626)
│   ├── PositionManager.sol     # Manages Polymarket positions
│   └── VaultAccounting.sol     # Share/asset calculations
├── access/
│   ├── AccessController.sol    # Role-based access control
│   └── Timelock.sol           # Delayed admin actions
├── security/
│   ├── EmergencyModule.sol    # Pause and emergency functions
│   └── RateLimiter.sol        # Trade rate limiting
├── interfaces/
│   ├── ICopyVault.sol
│   ├── IPositionManager.sol
│   ├── IPolymarketCTF.sol     # Polymarket CTF interface
│   └── IPolymarketExchange.sol
└── libraries/
    ├── PositionLib.sol        # Position math helpers
    └── ShareMath.sol          # Share calculation helpers
```

### 3.2 CopyVault.sol

#### 3.2.1 Purpose

The CopyVault is the main entry point for users. It:

- Accepts USDC deposits
- Mints shares representing ownership
- Tracks total assets (USDC + position value)
- Handles withdrawals

#### 3.2.2 Inheritance

```solidity
contract CopyVault is
    ERC4626,           // Tokenized vault standard
    AccessControlled,  // Role-based permissions
    Pausable,          // Emergency pause
    ReentrancyGuard    // Reentrancy protection
{
    // Implementation
}
```

#### 3.2.3 State Variables

```solidity
// Core state
IERC20 public immutable asset;              // USDC
IPositionManager public positionManager;     // Position management

// Limits
uint256 public maxTotalDeposits;            // Total vault cap
uint256 public maxDepositPerUser;           // Per-user cap
uint256 public minDeposit;                  // Minimum deposit

// Accounting
uint256 public totalIdleAssets;             // USDC not in positions
mapping(address => uint256) public userDeposits;  // Track deposits per user

// Leaders
mapping(address => bool) public approvedLeaders;
address[] public leaderList;

// Fee configuration
uint256 public performanceFee;              // Fee on profits (basis points)
uint256 public managementFee;               // Annual fee (basis points)
address public feeRecipient;
```

#### 3.2.4 Key Functions

```solidity
// ============ USER FUNCTIONS ============

/// @notice Deposit USDC and receive vault shares
/// @param assets Amount of USDC to deposit
/// @param receiver Address to receive shares
/// @return shares Amount of shares minted
function deposit(uint256 assets, address receiver)
    public
    override
    nonReentrant
    whenNotPaused
    returns (uint256 shares)
{
    // Checks
    require(assets >= minDeposit, "Below minimum deposit");
    require(totalAssets() + assets <= maxTotalDeposits, "Exceeds vault cap");
    require(userDeposits[receiver] + assets <= maxDepositPerUser, "Exceeds user cap");

    // Calculate shares
    shares = previewDeposit(assets);
    require(shares > 0, "Zero shares");

    // Effects
    userDeposits[receiver] += assets;
    totalIdleAssets += assets;

    // Interactions
    asset.safeTransferFrom(msg.sender, address(this), assets);
    _mint(receiver, shares);

    emit Deposit(msg.sender, receiver, assets, shares);
}

/// @notice Withdraw USDC by burning shares
/// @param shares Amount of shares to burn
/// @param receiver Address to receive USDC
/// @param owner Owner of the shares
/// @return assets Amount of USDC withdrawn
function withdraw(uint256 shares, address receiver, address owner)
    public
    override
    nonReentrant
    returns (uint256 assets)
{
    // Note: Withdrawals allowed even when paused

    if (msg.sender != owner) {
        _spendAllowance(owner, msg.sender, shares);
    }

    // Calculate assets owed
    assets = previewRedeem(shares);
    require(assets > 0, "Zero assets");

    // Check liquidity
    require(assets <= totalIdleAssets, "Insufficient liquidity");

    // Effects
    userDeposits[owner] -= min(userDeposits[owner], assets);
    totalIdleAssets -= assets;

    // Interactions
    _burn(owner, shares);
    asset.safeTransfer(receiver, assets);

    emit Withdraw(msg.sender, receiver, owner, assets, shares);
}

// ============ VIEW FUNCTIONS ============

/// @notice Total assets under management
/// @return Total USDC value (idle + positions)
function totalAssets() public view override returns (uint256) {
    return totalIdleAssets + positionManager.totalPositionValue();
}

/// @notice Calculate shares for a deposit amount
function previewDeposit(uint256 assets) public view override returns (uint256) {
    return _convertToShares(assets, Math.Rounding.Down);
}

/// @notice Calculate assets for a share amount
function previewRedeem(uint256 shares) public view override returns (uint256) {
    return _convertToAssets(shares, Math.Rounding.Down);
}

// ============ EXECUTOR FUNCTIONS ============

/// @notice Allocate USDC for a trade (called by executor)
/// @param amount USDC amount to allocate
function allocateForTrade(uint256 amount)
    external
    onlyRole(EXECUTOR_ROLE)
    whenNotPaused
{
    require(amount <= totalIdleAssets, "Insufficient idle assets");
    require(amount <= _maxTradeSize(), "Exceeds max trade size");

    totalIdleAssets -= amount;
    asset.safeTransfer(address(positionManager), amount);

    emit TradeAllocated(amount);
}

/// @notice Return USDC from closed position
/// @param amount USDC amount returned
function returnFromPosition(uint256 amount)
    external
    onlyRole(EXECUTOR_ROLE)
{
    totalIdleAssets += amount;
    emit PositionClosed(amount);
}
```

#### 3.2.5 Share Calculation (ERC-4626)

```solidity
/// @dev Internal conversion from assets to shares
function _convertToShares(uint256 assets, Math.Rounding rounding)
    internal
    view
    returns (uint256)
{
    uint256 supply = totalSupply();

    // First depositor edge case: use 1:1 ratio with offset
    // This prevents inflation attacks
    return (assets == 0 || supply == 0)
        ? assets + 10 ** _decimalsOffset()
        : assets.mulDiv(supply + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
}

/// @dev Internal conversion from shares to assets
function _convertToAssets(uint256 shares, Math.Rounding rounding)
    internal
    view
    returns (uint256)
{
    uint256 supply = totalSupply();

    return (supply == 0)
        ? shares - 10 ** _decimalsOffset()
        : shares.mulDiv(totalAssets() + 1, supply + 10 ** _decimalsOffset(), rounding);
}

/// @dev Offset for virtual shares (prevents inflation attack)
function _decimalsOffset() internal pure returns (uint8) {
    return 3; // 1000 virtual shares
}
```

### 3.3 PositionManager.sol

#### 3.3.1 Purpose

Manages all Polymarket positions:

- Holds ERC-1155 outcome tokens
- Tracks position metadata
- Calculates position values
- Handles redemption after resolution

#### 3.3.2 State Variables

```solidity
// Polymarket contracts
IConditionalTokens public immutable ctf;      // Conditional Token Framework
address public immutable exchange;             // Polymarket Exchange
IERC20 public immutable usdc;

// Position tracking
struct Position {
    bytes32 conditionId;      // Polymarket market identifier
    uint256 tokenId;          // YES or NO token ID
    uint256 amount;           // Number of tokens held
    uint256 avgEntryPrice;    // Average entry price (6 decimals)
    uint256 costBasis;        // Total USDC spent
    uint64 openedAt;          // Timestamp when opened
    bool isYes;               // true = YES token, false = NO
}

mapping(bytes32 => Position) public positions;  // conditionId => Position
bytes32[] public activePositionIds;

// Limits
uint256 public maxPositions;           // Max concurrent positions
uint256 public maxPositionSize;        // Max size per position (% of vault, basis points)
uint256 public maxTotalExposure;       // Max total in positions (% of vault, basis points)
```

#### 3.3.3 Key Functions

```solidity
// ============ TRADE EXECUTION ============

/// @notice Open or add to a position
/// @param conditionId Polymarket market condition ID
/// @param tokenId Token ID (YES or NO)
/// @param amount USDC amount to spend
/// @param minTokens Minimum tokens to receive (slippage protection)
/// @param isYes Whether this is a YES or NO position
function openPosition(
    bytes32 conditionId,
    uint256 tokenId,
    uint256 amount,
    uint256 minTokens,
    bool isYes
) external onlyRole(EXECUTOR_ROLE) nonReentrant returns (uint256 tokensReceived) {
    // Validate
    require(activePositionIds.length < maxPositions, "Max positions reached");
    require(_isWithinExposureLimits(amount), "Exceeds exposure limits");

    // Approve USDC to Polymarket Exchange
    usdc.safeApprove(exchange, amount);

    // Execute trade on Polymarket (tokens sent to this contract)
    tokensReceived = _executePolymarketBuy(conditionId, tokenId, amount, minTokens);

    // Update position tracking
    Position storage pos = positions[conditionId];
    if (pos.amount == 0) {
        // New position
        pos.conditionId = conditionId;
        pos.tokenId = tokenId;
        pos.isYes = isYes;
        pos.openedAt = uint64(block.timestamp);
        activePositionIds.push(conditionId);
    }

    // Update amounts
    uint256 newTotal = pos.amount + tokensReceived;
    pos.avgEntryPrice = (pos.costBasis + amount) * 1e6 / newTotal;
    pos.amount = newTotal;
    pos.costBasis += amount;

    emit PositionOpened(conditionId, tokenId, tokensReceived, amount);
}

/// @notice Close or reduce a position
/// @param conditionId Market condition ID
/// @param tokenAmount Tokens to sell
/// @param minUsdc Minimum USDC to receive
function closePosition(
    bytes32 conditionId,
    uint256 tokenAmount,
    uint256 minUsdc
) external onlyRole(EXECUTOR_ROLE) nonReentrant returns (uint256 usdcReceived) {
    Position storage pos = positions[conditionId];
    require(pos.amount >= tokenAmount, "Insufficient position");

    // Approve tokens to Exchange
    ctf.setApprovalForAll(exchange, true);

    // Execute sell on Polymarket
    usdcReceived = _executePolymarketSell(conditionId, pos.tokenId, tokenAmount, minUsdc);

    // Update position
    uint256 costBasisReduction = pos.costBasis * tokenAmount / pos.amount;
    pos.amount -= tokenAmount;
    pos.costBasis -= costBasisReduction;

    if (pos.amount == 0) {
        _removePosition(conditionId);
    }

    // Return USDC to vault
    usdc.safeTransfer(address(vault), usdcReceived);
    vault.returnFromPosition(usdcReceived);

    emit PositionClosed(conditionId, tokenAmount, usdcReceived);
}

/// @notice Redeem tokens after market resolution
/// @param conditionId Resolved market condition ID
function redeemPosition(bytes32 conditionId)
    external
    onlyRole(EXECUTOR_ROLE)
    nonReentrant
    returns (uint256 usdcReceived)
{
    Position storage pos = positions[conditionId];
    require(pos.amount > 0, "No position");

    // Redeem via Polymarket CTF
    uint256 balanceBefore = usdc.balanceOf(address(this));

    uint256[] memory indexSets = new uint256[](2);
    indexSets[0] = 1; // YES
    indexSets[1] = 2; // NO

    ctf.redeemPositions(
        usdc,
        bytes32(0), // parentCollectionId
        conditionId,
        indexSets
    );

    usdcReceived = usdc.balanceOf(address(this)) - balanceBefore;

    // Clean up position
    _removePosition(conditionId);

    // Return to vault
    if (usdcReceived > 0) {
        usdc.safeTransfer(address(vault), usdcReceived);
        vault.returnFromPosition(usdcReceived);
    }

    emit PositionRedeemed(conditionId, pos.amount, usdcReceived);
}

// ============ VIEW FUNCTIONS ============

/// @notice Calculate total value of all positions
/// @return Total USDC value of positions
function totalPositionValue() external view returns (uint256) {
    uint256 total = 0;
    for (uint256 i = 0; i < activePositionIds.length; i++) {
        total += getPositionValue(activePositionIds[i]);
    }
    return total;
}

/// @notice Get current value of a position
/// @param conditionId Market condition ID
/// @return Current USDC value
function getPositionValue(bytes32 conditionId) public view returns (uint256) {
    Position memory pos = positions[conditionId];
    if (pos.amount == 0) return 0;

    // Get current price from Polymarket
    uint256 currentPrice = _getPolymarketPrice(conditionId, pos.tokenId);

    // Value = amount * price
    return pos.amount * currentPrice / 1e6;
}

/// @notice Get all active positions
/// @return Array of position data
function getActivePositions() external view returns (Position[] memory) {
    Position[] memory result = new Position[](activePositionIds.length);
    for (uint256 i = 0; i < activePositionIds.length; i++) {
        result[i] = positions[activePositionIds[i]];
    }
    return result;
}
```

### 3.4 AccessController.sol

#### 3.4.1 Role Definitions

```solidity
// Role hierarchy and permissions
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
```

#### 3.4.2 Permission Matrix

| Role             | Deposit/Withdraw | Execute Trades | Pause | Change Params | Upgrade | Emergency Shutdown |
| ---------------- | ---------------- | -------------- | ----- | ------------- | ------- | ------------------ |
| User             | Own funds only   | No             | No    | No            | No      | No                 |
| Executor         | No               | Yes            | No    | No            | No      | No                 |
| Guardian         | No               | No             | Yes   | No            | No      | No                 |
| Strategist       | No               | No             | No    | Leaders only  | No      | No                 |
| Admin (Multisig) | No               | No             | Yes   | Yes           | Yes     | Yes                |

#### 3.4.3 Implementation

```solidity
contract AccessController is AccessControlEnumerable {
    // Timelock for admin actions
    ITimelock public timelock;

    constructor(address _admin, address _timelock) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        timelock = ITimelock(_timelock);
    }

    /// @notice Modifier for timelocked admin functions
    modifier onlyTimelocked() {
        require(msg.sender == address(timelock), "Must go through timelock");
        _;
    }

    /// @notice Grant executor role (admin only, timelocked)
    function grantExecutorRole(address account)
        external
        onlyTimelocked
    {
        _grantRole(EXECUTOR_ROLE, account);
    }

    /// @notice Revoke executor role (admin only, immediate for security)
    function revokeExecutorRole(address account)
        external
        onlyRole(ADMIN_ROLE)
    {
        _revokeRole(EXECUTOR_ROLE, account);
    }

    /// @notice Grant guardian role (admin only)
    function grantGuardianRole(address account)
        external
        onlyRole(ADMIN_ROLE)
    {
        _grantRole(GUARDIAN_ROLE, account);
    }
}
```

### 3.5 Timelock.sol

```solidity
contract Timelock {
    uint256 public constant MINIMUM_DELAY = 48 hours;
    uint256 public constant MAXIMUM_DELAY = 30 days;
    uint256 public constant GRACE_PERIOD = 14 days;

    uint256 public delay;

    mapping(bytes32 => bool) public queuedTransactions;

    event TransactionQueued(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        bytes data,
        uint256 eta
    );

    event TransactionExecuted(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        bytes data
    );

    event TransactionCancelled(bytes32 indexed txHash);

    /// @notice Queue a transaction for future execution
    function queueTransaction(
        address target,
        uint256 value,
        bytes memory data,
        uint256 eta
    ) external onlyAdmin returns (bytes32) {
        require(eta >= block.timestamp + delay, "ETA too soon");

        bytes32 txHash = keccak256(abi.encode(target, value, data, eta));
        queuedTransactions[txHash] = true;

        emit TransactionQueued(txHash, target, value, data, eta);
        return txHash;
    }

    /// @notice Execute a queued transaction
    function executeTransaction(
        address target,
        uint256 value,
        bytes memory data,
        uint256 eta
    ) external onlyAdmin returns (bytes memory) {
        bytes32 txHash = keccak256(abi.encode(target, value, data, eta));

        require(queuedTransactions[txHash], "Transaction not queued");
        require(block.timestamp >= eta, "Transaction not ready");
        require(block.timestamp <= eta + GRACE_PERIOD, "Transaction expired");

        queuedTransactions[txHash] = false;

        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "Transaction execution failed");

        emit TransactionExecuted(txHash, target, value, data);
        return result;
    }

    /// @notice Cancel a queued transaction
    function cancelTransaction(
        address target,
        uint256 value,
        bytes memory data,
        uint256 eta
    ) external onlyAdmin {
        bytes32 txHash = keccak256(abi.encode(target, value, data, eta));
        queuedTransactions[txHash] = false;
        emit TransactionCancelled(txHash);
    }
}
```

---

## 4. Backend Services

### 4.1 Service Architecture

```
backend/
├── src/
│   ├── services/
│   │   ├── leader-monitor/
│   │   │   ├── LeaderMonitorService.ts
│   │   │   ├── PolymarketWebSocket.ts
│   │   │   └── TradeDetector.ts
│   │   ├── trade-executor/
│   │   │   ├── TradeExecutorService.ts
│   │   │   ├── OrderBuilder.ts
│   │   │   ├── PolymarketClient.ts
│   │   │   └── SlippageCalculator.ts
│   │   ├── position-tracker/
│   │   │   ├── PositionTrackerService.ts
│   │   │   ├── PriceOracle.ts
│   │   │   └── SettlementMonitor.ts
│   │   └── key-management/
│   │       ├── KeyManagementService.ts
│   │       ├── AWKMSigner.ts
│   │       └── FireblocksSigner.ts
│   ├── database/
│   │   ├── models/
│   │   ├── migrations/
│   │   └── repositories/
│   ├── api/
│   │   ├── routes/
│   │   ├── middleware/
│   │   └── controllers/
│   └── utils/
│       ├── logger.ts
│       ├── metrics.ts
│       └── alerts.ts
├── config/
│   ├── default.json
│   ├── production.json
│   └── development.json
└── tests/
```

### 4.2 Leader Monitor Service

#### 4.2.1 Purpose

Monitors Leader wallets for trades on Polymarket and emits signals when trades are detected.

#### 4.2.2 Implementation

```typescript
// LeaderMonitorService.ts

import { EventEmitter } from "events";
import { PolymarketWebSocket } from "./PolymarketWebSocket";

interface LeaderTrade {
  leaderAddress: string;
  conditionId: string;
  tokenId: string;
  side: "BUY" | "SELL";
  size: string;
  price: string;
  timestamp: number;
}

export class LeaderMonitorService extends EventEmitter {
  private wsClient: PolymarketWebSocket;
  private leaders: Map<string, LeaderConfig> = new Map();

  constructor(
    private config: LeaderMonitorConfig,
    private db: Database
  ) {
    super();
    this.wsClient = new PolymarketWebSocket(config.wsEndpoint);
  }

  async start(): Promise<void> {
    // Load approved leaders from database
    const leaders = await this.db.leaders.findApproved();
    leaders.forEach((l) => this.leaders.set(l.address.toLowerCase(), l));

    // Connect to Polymarket WebSocket
    await this.wsClient.connect();

    // Subscribe to trade events for each leader
    for (const [address, leader] of this.leaders) {
      await this.subscribeToLeader(address);
    }

    // Handle incoming trades
    this.wsClient.on("trade", this.handleTrade.bind(this));

    console.log(
      `Leader Monitor started, tracking ${this.leaders.size} leaders`
    );
  }

  private async subscribeToLeader(address: string): Promise<void> {
    // Subscribe to user's trade events via Polymarket WebSocket
    await this.wsClient.subscribe({
      channel: "user",
      markets: [], // All markets
      auth: null, // Public trades are visible
    });
  }

  private async handleTrade(trade: PolymarketTrade): Promise<void> {
    const makerAddress = trade.maker_address.toLowerCase();

    // Check if this is from a tracked leader
    if (!this.leaders.has(makerAddress)) {
      return;
    }

    const leader = this.leaders.get(makerAddress)!;

    // Validate trade meets criteria
    if (!this.isValidTrade(trade, leader)) {
      console.log(`Trade filtered out for leader ${makerAddress}`);
      return;
    }

    // Emit signal for trade executor
    const signal: LeaderTrade = {
      leaderAddress: makerAddress,
      conditionId: trade.market,
      tokenId: trade.asset_id,
      side: trade.side as "BUY" | "SELL",
      size: trade.size,
      price: trade.price,
      timestamp: Date.now(),
    };

    this.emit("leaderTrade", signal);

    // Log for audit
    await this.db.leaderTrades.create({
      ...signal,
      rawData: JSON.stringify(trade),
    });
  }

  private isValidTrade(trade: PolymarketTrade, leader: LeaderConfig): boolean {
    // Check minimum trade size
    if (parseFloat(trade.size) < leader.minTradeSize) {
      return false;
    }

    // Check if market is allowed
    if (
      leader.allowedMarkets &&
      !leader.allowedMarkets.includes(trade.market)
    ) {
      return false;
    }

    // Check if market is blocked
    if (leader.blockedMarkets && leader.blockedMarkets.includes(trade.market)) {
      return false;
    }

    return true;
  }

  async addLeader(address: string, config: LeaderConfig): Promise<void> {
    this.leaders.set(address.toLowerCase(), config);
    await this.subscribeToLeader(address.toLowerCase());
  }

  async removeLeader(address: string): Promise<void> {
    this.leaders.delete(address.toLowerCase());
  }
}
```

### 4.3 Trade Executor Service

#### 4.3.1 Purpose

Receives trade signals from Leader Monitor and executes corresponding trades on Polymarket for the vault.

#### 4.3.2 Implementation

```typescript
// TradeExecutorService.ts

import { ClobClient } from "@polymarket/clob-client";
import { KeyManagementService } from "../key-management/KeyManagementService";

interface TradeSignal {
  leaderAddress: string;
  conditionId: string;
  tokenId: string;
  side: "BUY" | "SELL";
  size: string;
  price: string;
}

interface ExecutionResult {
  success: boolean;
  orderId?: string;
  tokensTraded?: string;
  avgPrice?: string;
  error?: string;
}

export class TradeExecutorService {
  private clobClient: ClobClient;
  private kms: KeyManagementService;
  private isProcessing: boolean = false;
  private tradeQueue: TradeSignal[] = [];

  constructor(
    private config: TradeExecutorConfig,
    private db: Database,
    private vault: VaultContract,
    private positionManager: PositionManagerContract
  ) {
    this.kms = new KeyManagementService(config.kmsConfig);
  }

  async initialize(): Promise<void> {
    // Initialize Polymarket CLOB client
    const signer = await this.kms.getSigner();

    this.clobClient = new ClobClient(
      this.config.clobEndpoint,
      this.config.chainId,
      signer,
      this.config.clobCredentials
    );

    console.log("Trade Executor initialized");
  }

  async handleLeaderTrade(signal: TradeSignal): Promise<void> {
    // Add to queue
    this.tradeQueue.push(signal);

    // Process queue if not already processing
    if (!this.isProcessing) {
      await this.processQueue();
    }
  }

  private async processQueue(): Promise<void> {
    this.isProcessing = true;

    while (this.tradeQueue.length > 0) {
      const signal = this.tradeQueue.shift()!;

      try {
        await this.executeTrade(signal);
      } catch (error) {
        console.error("Trade execution failed:", error);
        await this.handleExecutionError(signal, error);
      }

      // Rate limiting
      await this.delay(this.config.minTimeBetweenTrades);
    }

    this.isProcessing = false;
  }

  private async executeTrade(signal: TradeSignal): Promise<ExecutionResult> {
    console.log(`Executing trade: ${signal.side} on ${signal.conditionId}`);

    // 1. Calculate position size for vault
    const vaultSize = await this.calculateVaultSize(signal);

    if (vaultSize === 0) {
      return { success: false, error: "Calculated vault size is 0" };
    }

    // 2. Validate against risk limits
    const validation = await this.validateTrade(signal, vaultSize);
    if (!validation.valid) {
      return { success: false, error: validation.reason };
    }

    // 3. Get current market price and calculate slippage bounds
    const marketData = await this.clobClient.getMarket(signal.conditionId);
    const slippagePrice = this.calculateSlippagePrice(
      signal.side,
      signal.price,
      this.config.maxSlippageBps
    );

    // 4. Build order
    const order = await this.buildOrder(signal, vaultSize, slippagePrice);

    // 5. Sign order via KMS
    const signedOrder = await this.kms.signOrder(order);

    // 6. Submit to Polymarket CLOB
    const result = await this.clobClient.postOrder(signedOrder, {
      orderType: "GTC", // Good-til-cancelled
    });

    // 7. Update position tracking on-chain
    if (result.success) {
      await this.updateOnChainPosition(signal, result);
    }

    // 8. Log execution
    await this.logExecution(signal, result);

    return result;
  }

  private async calculateVaultSize(signal: TradeSignal): Promise<number> {
    // Get vault's total assets
    const totalAssets = await this.vault.totalAssets();

    // Get leader's position size relative to their portfolio
    const leaderPortfolioSize = await this.getLeaderPortfolioSize(
      signal.leaderAddress
    );
    const leaderTradeRatio = parseFloat(signal.size) / leaderPortfolioSize;

    // Calculate vault's proportional trade size
    let vaultSize = totalAssets * leaderTradeRatio;

    // Apply max trade size limit
    const maxTradeSize = totalAssets * (this.config.maxTradeSizeBps / 10000);
    vaultSize = Math.min(vaultSize, maxTradeSize);

    // Ensure minimum viable trade
    if (vaultSize < this.config.minTradeSize) {
      return 0;
    }

    return vaultSize;
  }

  private async validateTrade(
    signal: TradeSignal,
    size: number
  ): Promise<{ valid: boolean; reason?: string }> {
    // Check if market is allowed
    const market = await this.db.markets.findByConditionId(signal.conditionId);
    if (market?.blocked) {
      return { valid: false, reason: "Market is blocked" };
    }

    // Check current exposure
    const currentExposure = await this.positionManager.totalPositionValue();
    const totalAssets = await this.vault.totalAssets();
    const exposureRatio = (currentExposure + size) / totalAssets;

    if (exposureRatio > this.config.maxTotalExposureBps / 10000) {
      return { valid: false, reason: "Would exceed max exposure" };
    }

    // Check position count
    const positionCount = await this.positionManager.activePositionCount();
    if (signal.side === "BUY" && positionCount >= this.config.maxPositions) {
      return { valid: false, reason: "Max positions reached" };
    }

    // Check idle assets
    const idleAssets = await this.vault.totalIdleAssets();
    if (signal.side === "BUY" && size > idleAssets) {
      return { valid: false, reason: "Insufficient idle assets" };
    }

    return { valid: true };
  }

  private calculateSlippagePrice(
    side: "BUY" | "SELL",
    price: string,
    maxSlippageBps: number
  ): string {
    const priceNum = parseFloat(price);
    const slippage = priceNum * (maxSlippageBps / 10000);

    if (side === "BUY") {
      // For buys, we're willing to pay up to price + slippage
      return (priceNum + slippage).toFixed(4);
    } else {
      // For sells, we're willing to receive down to price - slippage
      return (priceNum - slippage).toFixed(4);
    }
  }

  private async buildOrder(
    signal: TradeSignal,
    size: number,
    price: string
  ): Promise<Order> {
    const tokenId = signal.tokenId;

    return {
      tokenId,
      price,
      size: size.toString(),
      side: signal.side,
      feeRateBps: "0",
      nonce: Date.now().toString(),
      expiration: (Math.floor(Date.now() / 1000) + 3600).toString(), // 1 hour
    };
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
```

### 4.4 Key Management Service

#### 4.4.1 Purpose

Securely manages private keys for signing Polymarket orders. Keys never leave the secure environment (HSM/KMS).

#### 4.4.2 AWS KMS Implementation

```typescript
// AWKMSigner.ts

import {
  KMSClient,
  SignCommand,
  GetPublicKeyCommand,
} from "@aws-sdk/client-kms";
import { ethers } from "ethers";

export class AWSKMSSigner {
  private kmsClient: KMSClient;
  private keyId: string;
  private publicKey: string | null = null;
  private address: string | null = null;

  constructor(config: AWSKMSConfig) {
    this.kmsClient = new KMSClient({
      region: config.region,
      credentials: {
        accessKeyId: config.accessKeyId,
        secretAccessKey: config.secretAccessKey,
      },
    });
    this.keyId = config.keyId;
  }

  async initialize(): Promise<void> {
    // Fetch public key from KMS
    const command = new GetPublicKeyCommand({ KeyId: this.keyId });
    const response = await this.kmsClient.send(command);

    // Parse the public key
    this.publicKey = this.parsePublicKey(response.PublicKey!);
    this.address = ethers.computeAddress(this.publicKey);

    console.log(`KMS Signer initialized. Address: ${this.address}`);
  }

  getAddress(): string {
    if (!this.address) throw new Error("Signer not initialized");
    return this.address;
  }

  async signMessage(message: Uint8Array): Promise<string> {
    // Hash the message (Ethereum uses keccak256)
    const hash = ethers.keccak256(message);

    // Sign via KMS
    const command = new SignCommand({
      KeyId: this.keyId,
      Message: Buffer.from(hash.slice(2), "hex"),
      MessageType: "DIGEST",
      SigningAlgorithm: "ECDSA_SHA_256",
    });

    const response = await this.kmsClient.send(command);

    // Convert AWS signature format to Ethereum format
    const signature = this.convertSignature(response.Signature!, hash);

    return signature;
  }

  async signTypedData(
    domain: ethers.TypedDataDomain,
    types: Record<string, ethers.TypedDataField[]>,
    value: Record<string, any>
  ): Promise<string> {
    // Compute EIP-712 hash
    const hash = ethers.TypedDataEncoder.hash(domain, types, value);

    // Sign the hash
    return this.signMessage(ethers.getBytes(hash));
  }

  private parsePublicKey(derPublicKey: Uint8Array): string {
    // Parse DER-encoded public key to get raw coordinates
    // AWS KMS returns public key in DER format
    // ... implementation details
    return "0x" + Buffer.from(derPublicKey).toString("hex");
  }

  private convertSignature(awsSignature: Uint8Array, hash: string): string {
    // Convert AWS DER signature to Ethereum RSV format
    // ... implementation details
    return signature;
  }
}
```

#### 4.4.3 Fireblocks MPC Implementation (Alternative)

```typescript
// FireblocksSigner.ts

import { FireblocksSDK } from "fireblocks-sdk";

export class FireblocksSigner {
  private fireblocks: FireblocksSDK;
  private vaultAccountId: string;

  constructor(config: FireblocksConfig) {
    this.fireblocks = new FireblocksSDK(
      config.apiSecret,
      config.apiKey,
      config.baseUrl
    );
    this.vaultAccountId = config.vaultAccountId;
  }

  async signTransaction(tx: TransactionRequest): Promise<string> {
    const txResponse = await this.fireblocks.createTransaction({
      assetId: "MATIC_POLYGON",
      source: {
        type: "VAULT_ACCOUNT",
        id: this.vaultAccountId,
      },
      destination: {
        type: "ONE_TIME_ADDRESS",
        oneTimeAddress: {
          address: tx.to,
        },
      },
      amount: tx.value?.toString() || "0",
      extraParameters: {
        contractCallData: tx.data,
      },
    });

    // Wait for signing
    const result = await this.waitForTransaction(txResponse.id);

    return result.signedTxHash;
  }
}
```

---

## 5. Security Architecture

### 5.1 Security Layers

```
+------------------------------------------------------------------+
|                    SECURITY ARCHITECTURE                          |
+------------------------------------------------------------------+
|                                                                   |
|  LAYER 1: SMART CONTRACT SECURITY                                 |
|  +--------------------------------------------------------------+ |
|  | - Audited by 2+ firms (Trail of Bits, OpenZeppelin)          | |
|  | - Formal verification of critical paths                      | |
|  | - 95%+ test coverage with Foundry                            | |
|  | - Invariant testing and fuzzing                              | |
|  | - Bug bounty on Immunefi ($100k+)                            | |
|  +--------------------------------------------------------------+ |
|                                                                   |
|  LAYER 2: ACCESS CONTROL                                          |
|  +--------------------------------------------------------------+ |
|  | - Role-based permissions (Admin, Executor, Guardian)         | |
|  | - Admin = 4/7 Multisig (Gnosis Safe)                         | |
|  | - 48-hour timelock on parameter changes                      | |
|  | - Executor has trade-only permissions                        | |
|  | - Guardian can only pause (not steal)                        | |
|  +--------------------------------------------------------------+ |
|                                                                   |
|  LAYER 3: KEY MANAGEMENT                                          |
|  +--------------------------------------------------------------+ |
|  | - Private keys in HSM (FIPS 140-2 Level 3)                   | |
|  | - Or MPC via Fireblocks/Fordefi                              | |
|  | - Keys never exposed to application code                     | |
|  | - Audit trail for every signing operation                    | |
|  +--------------------------------------------------------------+ |
|                                                                   |
|  LAYER 4: OPERATIONAL SECURITY                                    |
|  +--------------------------------------------------------------+ |
|  | - Rate limiting on all operations                            | |
|  | - Anomaly detection (unusual sizes/frequency)                | |
|  | - Automatic circuit breakers                                 | |
|  | - 24/7 monitoring with PagerDuty alerts                      | |
|  | - Incident response runbooks                                 | |
|  +--------------------------------------------------------------+ |
|                                                                   |
|  LAYER 5: INFRASTRUCTURE SECURITY                                 |
|  +--------------------------------------------------------------+ |
|  | - Backend in private VPC                                     | |
|  | - No public endpoints except API gateway                     | |
|  | - Encrypted at rest and in transit                           | |
|  | - Regular security audits and pen testing                    | |
|  +--------------------------------------------------------------+ |
|                                                                   |
+------------------------------------------------------------------+
```

### 5.2 Smart Contract Security Checklist

| Category              | Check                        | Implementation                                  |
| --------------------- | ---------------------------- | ----------------------------------------------- |
| Reentrancy            | All external calls protected | ReentrancyGuard on all state-changing functions |
| Access Control        | Role-based permissions       | OpenZeppelin AccessControl                      |
| Integer Safety        | No overflow/underflow        | Solidity 0.8+ built-in checks                   |
| Input Validation      | All inputs validated         | require() checks on all parameters              |
| Emergency Controls    | Can pause if needed          | Pausable, but withdrawals always work           |
| Upgrade Safety        | If upgradeable, safe pattern | UUPS with storage gaps                          |
| External Calls        | Check return values          | SafeERC20 for all token transfers               |
| Flash Loan Protection | Not vulnerable               | Share calculation prevents inflation            |
| Price Manipulation    | Protected                    | Not relying on spot prices for critical logic   |

### 5.3 Multisig Configuration

```
ADMIN MULTISIG (Gnosis Safe)
├── Threshold: 4 of 7
├── Signers:
│   ├── Founder 1 (Hardware wallet)
│   ├── Founder 2 (Hardware wallet)
│   ├── CTO (Hardware wallet)
│   ├── Security Lead (Hardware wallet)
│   ├── Legal Counsel (Hardware wallet)
│   ├── Investor Rep (Hardware wallet)
│   └── Community Rep (Hardware wallet)
└── Recovery:
    └── 5 of 7 can replace a signer (via timelock)
```

### 5.4 Timelock Parameters

| Action                | Delay     | Rationale                  |
| --------------------- | --------- | -------------------------- |
| Change fee parameters | 48 hours  | Users can exit if disagree |
| Add new leader        | 24 hours  | Lower risk action          |
| Remove leader         | Immediate | Security action            |
| Upgrade contract      | 72 hours  | High risk, users can exit  |
| Change risk limits    | 48 hours  | Users can exit             |
| Emergency pause       | Immediate | Security action            |
| Emergency shutdown    | Immediate | Security action            |

### 5.5 Monitoring & Alerting

```typescript
// alerts.ts - Alert conditions

const ALERT_CONDITIONS = {
  // Critical - Page immediately
  CRITICAL: [
    {
      name: "Large withdrawal",
      condition: "withdrawal > 10% of TVL",
      action: "page_oncall",
    },
    {
      name: "Rapid TVL decrease",
      condition: "TVL drops > 20% in 1 hour",
      action: "page_oncall",
    },
    {
      name: "Executor key used from new IP",
      condition: "signing_request from unknown_ip",
      action: "page_oncall + pause_trading",
    },
    {
      name: "Contract paused",
      condition: "Paused event emitted",
      action: "page_all",
    },
  ],

  // High - Alert within 5 minutes
  HIGH: [
    {
      name: "High slippage trade",
      condition: "slippage > 5%",
      action: "alert_slack",
    },
    {
      name: "Position near liquidation",
      condition: "unrealized_loss > 30%",
      action: "alert_slack",
    },
    {
      name: "Trade execution failure",
      condition: "trade_failed",
      action: "alert_slack + retry",
    },
  ],

  // Medium - Daily digest
  MEDIUM: [
    {
      name: "Low vault utilization",
      condition: "idle_ratio > 50% for 24h",
      action: "daily_report",
    },
    {
      name: "Leader inactive",
      condition: "no_trades for 7 days",
      action: "daily_report",
    },
  ],
};
```

---

## 6. User Flows

### 6.1 Deposit Flow

```
User Journey: Depositing USDC

1. USER CONNECTS WALLET
   └── User visits app, clicks "Connect Wallet"
   └── Selects wallet (MetaMask, Coinbase, etc.)
   └── Approves connection on Polygon network

2. USER VIEWS VAULT INFO
   └── Sees current TVL, share price, performance
   └── Sees list of Leaders being copied
   └── Sees current positions and P&L

3. USER ENTERS DEPOSIT AMOUNT
   └── Enters USDC amount
   └── Sees estimated shares to receive
   └── Sees current share price

4. USER APPROVES USDC
   └── Clicks "Approve USDC"
   └── Signs approval transaction in wallet
   └── Waits for confirmation

5. USER DEPOSITS
   └── Clicks "Deposit"
   └── Signs deposit transaction in wallet
   └── Transaction submitted to blockchain

6. SMART CONTRACT PROCESSING
   └── Validates deposit (min amount, caps)
   └── Transfers USDC from user to vault
   └── Calculates shares: shares = deposit * totalShares / totalAssets
   └── Mints shares to user
   └── Emits Deposit event

7. USER RECEIVES CONFIRMATION
   └── UI shows success message
   └── User's share balance updated
   └── User can now track portfolio performance
```

### 6.2 Withdrawal Flow

```
User Journey: Withdrawing USDC

1. USER INITIATES WITHDRAWAL
   └── Clicks "Withdraw" in portfolio
   └── Enters shares to redeem (or "Max")
   └── Sees estimated USDC to receive

2. LIQUIDITY CHECK
   └── System checks vault's idle USDC
   └── IF sufficient: proceed to step 3
   └── IF insufficient: show options
       ├── Option A: Partial withdrawal (available amount)
       ├── Option B: Queue full withdrawal
       └── Option C: Receive proportional tokens

3. USER CONFIRMS WITHDRAWAL
   └── Clicks "Confirm Withdrawal"
   └── Signs transaction in wallet

4. SMART CONTRACT PROCESSING
   └── Calculates USDC: assets = shares * totalAssets / totalShares
   └── Burns user's shares
   └── Transfers USDC to user
   └── Emits Withdraw event

5. USER RECEIVES FUNDS
   └── USDC arrives in wallet
   └── UI shows success message
   └── Portfolio updated
```

### 6.3 Copy-Trade Execution Flow

```
System Flow: Leader Trade → Vault Trade

1. LEADER TRADES ON POLYMARKET
   └── Leader buys 10,000 YES tokens on "BTC > $100k"
   └── Trade executes at $0.45 per token
   └── Costs Leader 4,500 USDC

2. LEADER MONITOR DETECTS TRADE
   └── WebSocket receives trade event
   └── Validates: Is leader approved? Is market allowed?
   └── Emits LeaderTrade signal

3. TRADE EXECUTOR PROCESSES SIGNAL
   └── Calculates vault position size
       ├── Leader portfolio: $100,000
       ├── Leader trade: $4,500 (4.5%)
       ├── Vault TVL: $500,000
       └── Vault trade: $22,500 (4.5%)
   └── Validates against risk limits
   └── Builds Polymarket order

4. ORDER SIGNING
   └── Order sent to KMS/HSM
   └── Private key signs EIP-712 message
   └── Signed order returned

5. ORDER SUBMISSION
   └── Signed order submitted to Polymarket CLOB
   └── Order matched against order book
   └── Trade executes

6. POSITION UPDATE
   └── Vault receives 50,000 YES tokens
   └── PositionManager records position
   └── Vault accounting updated

7. MONITORING
   └── Trade logged to database
   └── Metrics updated
   └── Alert if any issues
```

---

## 7. Trade Execution

### 7.1 Order Building

```typescript
interface PolymarketOrder {
  // Market identification
  tokenId: string; // YES or NO token ID

  // Order parameters
  price: string; // Limit price (0.01 - 0.99)
  size: string; // Number of tokens
  side: "BUY" | "SELL"; // Direction

  // Execution parameters
  feeRateBps: string; // Fee rate in basis points
  nonce: string; // Unique nonce
  expiration: string; // Unix timestamp

  // Addresses
  maker: string; // Vault's Polymarket address
  signer: string; // Signing address
  taker: string; // Operator address

  // Signature
  signatureType: number; // 0 = EOA, 1 = Proxy, 2 = Safe
  signature: string; // EIP-712 signature
}
```

### 7.2 Slippage Protection

```typescript
function calculateSlippage(
  side: "BUY" | "SELL",
  targetPrice: number,
  maxSlippageBps: number
): { limitPrice: number; worstPrice: number } {
  const slippageFactor = maxSlippageBps / 10000;

  if (side === "BUY") {
    return {
      limitPrice: targetPrice,
      worstPrice: targetPrice * (1 + slippageFactor),
    };
  } else {
    return {
      limitPrice: targetPrice,
      worstPrice: targetPrice * (1 - slippageFactor),
    };
  }
}

// Example:
// Buying at $0.45 with 2% max slippage
// limitPrice: 0.45
// worstPrice: 0.459 (will not execute above this)
```

### 7.3 Order Types Used

| Order Type               | Use Case                 | Behavior                                |
| ------------------------ | ------------------------ | --------------------------------------- |
| GTC (Good-Til-Cancelled) | Default for limit orders | Stays on book until filled or cancelled |
| FOK (Fill-Or-Kill)       | Time-sensitive trades    | Fill entire order immediately or cancel |
| GTD (Good-Til-Date)      | Expiring orders          | Auto-cancel after specified time        |

### 7.4 Execution Quality Metrics

```typescript
interface ExecutionMetrics {
  // Slippage
  expectedPrice: number;
  executedPrice: number;
  slippageBps: number;

  // Timing
  signalTimestamp: number;
  executionTimestamp: number;
  latencyMs: number;

  // Fill
  requestedSize: number;
  filledSize: number;
  fillRate: number;

  // Cost
  gasCost: number;
  polymarketFees: number;
  totalCost: number;
}
```

---

## 8. Position Management

### 8.1 Position Tracking

```solidity
struct Position {
    bytes32 conditionId;      // Polymarket market ID
    uint256 tokenId;          // YES (1) or NO (2) token
    uint256 amount;           // Number of tokens held
    uint256 avgEntryPrice;    // Weighted average entry (6 decimals)
    uint256 costBasis;        // Total USDC spent
    uint64 openedAt;          // Timestamp when first opened
    uint64 lastUpdated;       // Last modification timestamp
    bool isYes;               // Position direction
}
```

### 8.2 Position Valuation

```
Current Position Value = Token Amount × Current Token Price

Example:
- Position: 50,000 YES tokens
- Current YES price: $0.52
- Position Value: 50,000 × $0.52 = $26,000

Unrealized P&L = Current Value - Cost Basis

Example:
- Cost Basis: $22,500 (bought at avg $0.45)
- Current Value: $26,000
- Unrealized P&L: +$3,500 (+15.6%)
```

### 8.3 Market Resolution & Settlement

```
Resolution Flow:

1. MARKET RESOLVES ON POLYMARKET
   └── UMA Oracle finalizes outcome
   └── Example: "BTC > $100k by Dec 31" resolves YES

2. BACKEND DETECTS RESOLUTION
   └── Monitors Polymarket for resolved markets
   └── Checks if vault has position in market

3. REDEEM TOKENS
   └── Calls CTF.redeemPositions()
   └── YES tokens → 1 USDC each (winner)
   └── NO tokens → 0 USDC (loser)

4. UPDATE VAULT
   └── USDC credited to vault
   └── Position removed from tracking
   └── Share price automatically reflects gain/loss

Example Settlement:
- Vault held: 50,000 YES tokens
- Market resolved: YES
- Redemption: 50,000 × $1 = $50,000 USDC
- Original cost: $22,500
- Realized profit: $27,500
```

### 8.4 Share Price Calculation

```
Share Price = Total Assets / Total Shares

Total Assets = Idle USDC + Sum(Position Values)

Example:
- Idle USDC: $400,000
- Position 1 value: $26,000
- Position 2 value: $18,000
- Total Assets: $444,000
- Total Shares: 1,000,000
- Share Price: $0.444 per share

User Value:
- User shares: 50,000
- User value: 50,000 × $0.444 = $22,200
```

---

## 9. Risk Management

### 9.1 Risk Parameters

```yaml
# Vault-level limits
vault:
  max_tvl: 10_000_000 # $10M max TVL
  max_single_position: 1000 # 10% of vault (basis points)
  max_total_exposure: 8000 # 80% of vault in positions
  min_idle_ratio: 2000 # Keep 20% liquid
  max_positions: 20 # Max concurrent positions

# Trade-level limits
trades:
  max_trade_size: 500 # 5% of vault per trade
  max_slippage: 200 # 2% max slippage
  min_trade_size: 100 # $100 minimum trade
  min_time_between: 10 # 10 seconds between trades
  max_trades_per_hour: 50 # Rate limit

# User-level limits
users:
  max_deposit: 100_000 # $100k per user
  min_deposit: 10 # $10 minimum

# Circuit breakers
circuit_breakers:
  max_daily_drawdown: 2000 # 20% - pause new trades
  max_hourly_drawdown: 1000 # 10% - pause new trades
  resume_after: 3600 # 1 hour cooldown
```

### 9.2 Exposure Monitoring

```typescript
interface ExposureReport {
  // Vault-level
  totalAssets: number;
  totalExposure: number; // $ in positions
  exposureRatio: number; // exposure / assets
  idleAssets: number;
  idleRatio: number;

  // Position-level
  positions: {
    market: string;
    exposure: number;
    exposureRatio: number; // position / assets
    unrealizedPnl: number;
    unrealizedPnlPercent: number;
  }[];

  // Risk metrics
  largestPosition: number;
  concentrationRisk: number; // Herfindahl index

  // Limits
  withinLimits: boolean;
  violations: string[];
}
```

### 9.3 Circuit Breakers

```typescript
class CircuitBreaker {
  private pauseUntil: number = 0;

  async checkAndTrip(metrics: VaultMetrics): Promise<boolean> {
    // Check hourly drawdown
    const hourlyReturn = this.calculateHourlyReturn(metrics);
    if (hourlyReturn < -0.1) {
      // -10%
      await this.tripBreaker("hourly_drawdown", 3600);
      return true;
    }

    // Check daily drawdown
    const dailyReturn = this.calculateDailyReturn(metrics);
    if (dailyReturn < -0.2) {
      // -20%
      await this.tripBreaker("daily_drawdown", 86400);
      return true;
    }

    // Check for unusual activity
    const tradesLastHour = await this.getTradeCount(3600);
    if (tradesLastHour > 100) {
      await this.tripBreaker("unusual_activity", 1800);
      return true;
    }

    return false;
  }

  private async tripBreaker(reason: string, duration: number): Promise<void> {
    this.pauseUntil = Date.now() + duration * 1000;

    // Pause trading on contract
    await this.vault.pauseTrading();

    // Alert team
    await this.alertService.sendCritical({
      type: "circuit_breaker_tripped",
      reason,
      duration,
      resumeAt: new Date(this.pauseUntil),
    });
  }

  isTripped(): boolean {
    return Date.now() < this.pauseUntil;
  }
}
```

### 9.4 Loss Limits

```
Per-Position Loss Limit:
- Max unrealized loss per position: 30%
- Action: Alert team, consider closing

Portfolio Loss Limit:
- Max daily drawdown: 20%
- Action: Pause new trades, alert team

Recovery Mode:
- If drawdown > 15%: Reduce position sizes by 50%
- If drawdown > 20%: Pause all new trades
- Resume when drawdown < 10%
```

---

## 10. API Specifications

### 10.1 REST API Endpoints

```yaml
# Public endpoints (no auth)
GET /api/v1/vault/info
  description: Get vault information
  response:
    tvl: number
    sharePrice: number
    totalShares: number
    performance24h: number
    performance7d: number
    performance30d: number

GET /api/v1/vault/positions
  description: Get current positions
  response:
    positions:
      - market: string
        side: YES | NO
        size: number
        entryPrice: number
        currentPrice: number
        unrealizedPnl: number

GET /api/v1/vault/leaders
  description: Get leader information
  response:
    leaders:
      - address: string
        name: string
        performance30d: number
        tradesCount: number
        winRate: number

GET /api/v1/markets/{conditionId}
  description: Get market information
  response:
    conditionId: string
    question: string
    yesPrice: number
    noPrice: number
    volume24h: number
    liquidity: number

# Authenticated endpoints (wallet signature)
GET /api/v1/user/portfolio
  description: Get user's portfolio
  auth: wallet signature
  response:
    shares: number
    value: number
    depositedAmount: number
    pnl: number
    pnlPercent: number

GET /api/v1/user/transactions
  description: Get user's transaction history
  auth: wallet signature
  response:
    transactions:
      - type: DEPOSIT | WITHDRAW
        amount: number
        shares: number
        timestamp: number
        txHash: string

# Admin endpoints (multisig)
POST /api/v1/admin/leaders
  description: Add a new leader
  auth: multisig signature
  body:
    address: string
    config: LeaderConfig

DELETE /api/v1/admin/leaders/{address}
  description: Remove a leader
  auth: multisig signature

POST /api/v1/admin/pause
  description: Pause trading
  auth: guardian or admin signature

POST /api/v1/admin/unpause
  description: Resume trading
  auth: admin signature
```

### 10.2 WebSocket API

```typescript
// Client subscription
ws.send(
  JSON.stringify({
    type: "subscribe",
    channels: ["vault", "positions", "trades"],
  })
);

// Server messages
interface VaultUpdate {
  type: "vault_update";
  data: {
    tvl: number;
    sharePrice: number;
    idleAssets: number;
  };
}

interface PositionUpdate {
  type: "position_update";
  data: {
    conditionId: string;
    action: "opened" | "increased" | "decreased" | "closed" | "settled";
    amount: number;
    price: number;
  };
}

interface TradeUpdate {
  type: "trade_executed";
  data: {
    conditionId: string;
    side: "BUY" | "SELL";
    size: number;
    price: number;
    leader: string;
    timestamp: number;
  };
}
```

---

## 11. Deployment Guide

### 11.1 Pre-Deployment Checklist

```
[ ] Smart Contracts
    [ ] All tests passing (>95% coverage)
    [ ] Audit completed and issues resolved
    [ ] Formal verification on critical paths
    [ ] Deployment scripts tested on testnet
    [ ] Contract addresses documented
    [ ] Verification on Polygonscan prepared

[ ] Backend Services
    [ ] All services containerized
    [ ] Environment variables documented
    [ ] Secrets in AWS Secrets Manager
    [ ] Database migrations ready
    [ ] Monitoring dashboards created
    [ ] Alert rules configured

[ ] Key Management
    [ ] HSM/KMS configured
    [ ] Signing key generated
    [ ] Backup procedures documented
    [ ] Access policies configured

[ ] Multisig
    [ ] Safe deployed on Polygon
    [ ] All signers added
    [ ] Threshold set (4/7)
    [ ] Test transaction executed

[ ] Infrastructure
    [ ] VPC configured
    [ ] Load balancers ready
    [ ] SSL certificates
    [ ] CDN for frontend
    [ ] Backup procedures

[ ] Operations
    [ ] Runbooks written
    [ ] On-call schedule set
    [ ] Incident response plan
    [ ] Communication channels
```

### 11.2 Deployment Steps

```bash
# 1. Deploy contracts
forge script script/Deploy.s.sol:Deploy --rpc-url polygon --broadcast --verify

# 2. Configure contracts
forge script script/Configure.s.sol:Configure --rpc-url polygon --broadcast

# 3. Transfer ownership to timelock
forge script script/TransferOwnership.s.sol --rpc-url polygon --broadcast

# 4. Deploy backend
kubectl apply -f k8s/production/

# 5. Run migrations
kubectl exec -it backend-pod -- npm run migrate

# 6. Start services
kubectl scale deployment leader-monitor --replicas=2
kubectl scale deployment trade-executor --replicas=2

# 7. Verify deployment
./scripts/verify-deployment.sh
```

### 11.3 Post-Deployment Verification

```typescript
async function verifyDeployment(): Promise<VerificationResult> {
  const checks = [
    // Contract checks
    await checkContractDeployed(VAULT_ADDRESS),
    await checkContractVerified(VAULT_ADDRESS),
    await checkOwnership(VAULT_ADDRESS, TIMELOCK_ADDRESS),
    await checkRoles(VAULT_ADDRESS),

    // Backend checks
    await checkServiceHealth("leader-monitor"),
    await checkServiceHealth("trade-executor"),
    await checkDatabaseConnection(),
    await checkKMSConnection(),

    // Integration checks
    await checkPolymarketConnection(),
    await checkWebSocketConnection(),

    // Monitoring checks
    await checkMetricsExporter(),
    await checkAlertRouting(),
  ];

  return {
    passed: checks.every((c) => c.passed),
    checks,
  };
}
```

---

## 12. Emergency Procedures

### 12.1 Emergency Contacts

```
Primary On-Call: [Phone Number]
Secondary On-Call: [Phone Number]
Security Lead: [Phone Number]
Legal Counsel: [Phone Number]

Slack Channel: #goblin-incidents
PagerDuty: goblin-critical
```

### 12.2 Emergency Procedures

#### Procedure 1: Pause Trading

```
TRIGGER: Suspected exploit, unusual activity, market manipulation

STEPS:
1. Guardian calls vault.pauseTrading()
2. Alert team via PagerDuty
3. Assess situation
4. If false alarm: Admin multisig calls unpause()
5. If real incident: Proceed to Procedure 2 or 3
```

#### Procedure 2: Emergency Withdrawal

```
TRIGGER: Critical vulnerability discovered

STEPS:
1. Pause all trading (Guardian)
2. Notify users via all channels
3. Admin multisig enables emergency mode
4. Users can withdraw (receive pro-rata tokens if needed)
5. Assess and patch vulnerability
6. Redeploy if necessary
```

#### Procedure 3: Full Shutdown

```
TRIGGER: Unrecoverable exploit, regulatory action

STEPS:
1. Admin multisig calls emergencyShutdown()
2. All positions closed at market
3. USDC distributed pro-rata to shareholders
4. Notify users, regulators, partners
5. Post-mortem analysis
6. Insurance claim if applicable
```

### 12.3 Incident Response Template

```markdown
# Incident Report: [TITLE]

## Summary

- Date/Time:
- Duration:
- Severity: Critical / High / Medium / Low
- Impact:

## Timeline

- [Time] - Incident detected
- [Time] - Team alerted
- [Time] - Response initiated
- [Time] - Incident resolved
- [Time] - Post-mortem completed

## Root Cause

[Description of what caused the incident]

## Impact

- Users affected:
- Funds at risk:
- Actual loss:

## Response Actions

1. [Action taken]
2. [Action taken]

## Prevention

- [ ] [Preventive measure]
- [ ] [Preventive measure]

## Lessons Learned

[Key takeaways]
```

---

## 13. Appendix

### 13.1 Contract Addresses (Polygon)

```
# Production (to be filled after deployment)
CopyVault:
PositionManager:
AccessController:
Timelock:

# External contracts
USDC (Polygon): 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
Polymarket CTF: [address]
Polymarket Exchange: [address]

# Multisig
Admin Safe:
```

### 13.2 Environment Variables

```bash
# Backend
POLYGON_RPC_URL=
POLYMARKET_CLOB_URL=https://clob.polymarket.com
POLYMARKET_WS_URL=wss://ws-subscriptions-clob.polymarket.com/ws

# Key Management
AWS_REGION=
AWS_KMS_KEY_ID=

# Database
DATABASE_URL=

# Monitoring
DATADOG_API_KEY=
PAGERDUTY_ROUTING_KEY=

# Contract addresses
VAULT_ADDRESS=
POSITION_MANAGER_ADDRESS=
```

### 13.3 Glossary

| Term         | Definition                                         |
| ------------ | -------------------------------------------------- |
| TVL          | Total Value Locked - total assets under management |
| Share        | ERC-20 token representing ownership in vault       |
| Leader       | Expert trader whose trades are copied              |
| Follower     | User who deposits to copy Leaders                  |
| Condition ID | Unique identifier for a Polymarket market          |
| Token ID     | Identifier for YES or NO outcome token             |
| CLOB         | Central Limit Order Book                           |
| CTF          | Conditional Token Framework                        |
| Basis Points | 1/100th of a percent (100 bps = 1%)                |

### 13.4 References

- [Polymarket Documentation](https://docs.polymarket.com)
- [ERC-4626 Standard](https://eips.ethereum.org/EIPS/eip-4626)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts)
- [Foundry Book](https://book.getfoundry.sh)
- [Gnosis Safe](https://docs.safe.global)

---

## Document History

| Version | Date       | Author      | Changes         |
| ------- | ---------- | ----------- | --------------- |
| 1.0     | 2024-XX-XX | Goblin Team | Initial release |

---

_This document is confidential and intended for internal use only._
