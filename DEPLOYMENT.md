# Goblin Copy-Trading System - Polygon Mainnet Deployment

**Deployment Date:** January 20, 2026
**Network:** Polygon Mainnet (Chain ID: 137)
**Deployer:** `0xdf4F65A2d7beB026cc57DeeE76A6083bB4020FB4`

---

## Contract Addresses

| Contract         | Address                                      | Polygonscan                                                                             |
| ---------------- | -------------------------------------------- | --------------------------------------------------------------------------------------- |
| CopyVault        | `0xEa6ce4437B49e48b0350324c7435c9b9d0A84061` | [View](https://polygonscan.com/address/0xEa6ce4437B49e48b0350324c7435c9b9d0A84061#code) |
| PositionManager  | `0x766dB1CC757c12ef47749EE90E7770E071396463` | [View](https://polygonscan.com/address/0x766dB1CC757c12ef47749EE90E7770E071396463#code) |
| Timelock         | `0x35C49FE68AEA69EBaAF4ff75066D40adf1F0e9c6` | [View](https://polygonscan.com/address/0x35C49FE68AEA69EBaAF4ff75066D40adf1F0e9c6#code) |
| AccessController | `0x8704c006F2734be577780FE0209A3CeD7493CEC2` | [View](https://polygonscan.com/address/0x8704c006F2734be577780FE0209A3CeD7493CEC2#code) |

### External Contracts (Polymarket)

| Contract                          | Address                                      |
| --------------------------------- | -------------------------------------------- |
| USDC                              | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` |
| Conditional Token Framework (CTF) | `0x4D97DCd97eC945f40cF65F87097ACe5EA0476045` |
| Polymarket Exchange               | `0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E` |

---

## Contract Descriptions

### CopyVault

**Address:** `0xEa6ce4437B49e48b0350324c7435c9b9d0A84061`

The main entry point for users. An ERC-4626 compliant vault that enables copy-trading on Polymarket.

**Features:**

- Deposit/withdraw USDC and receive vault shares
- Share accounting with inflation attack protection (virtual shares offset)
- Role-based access control (Admin, Executor, Guardian, Strategist)
- Emergency pause capability (withdrawals always allowed)
- Leader management for copy-trading

**Default Parameters:**
| Parameter | Value |
|-----------|-------|
| Max Total Deposits | $10,000,000 |
| Max Deposit Per User | $100,000 |
| Min Deposit | $10 |
| Max Trade Size | 5% of vault |
| Performance Fee | 10% |
| Management Fee | 2% annual |

**Key Functions:**

- `deposit(uint256 assets, address receiver)` - Deposit USDC for vault shares
- `withdraw(uint256 assets, address receiver, address owner)` - Withdraw USDC
- `redeem(uint256 shares, address receiver, address owner)` - Redeem shares for USDC
- `totalAssets()` - Get total USDC value (idle + positions)

---

### PositionManager

**Address:** `0x766dB1CC757c12ef47749EE90E7770E071396463`

Manages Polymarket positions for the copy-trading vault. Handles opening, closing, and redeeming positions.

**Features:**

- Open/close positions on Polymarket markets
- Track position metadata and P&L
- Redeem resolved positions via CTF
- Position value calculations
- Slippage protection

**Default Limits:**
| Parameter | Value |
|-----------|-------|
| Max Concurrent Positions | 20 |
| Max Position Size | 10% of vault |
| Max Total Exposure | 80% of vault |

**Key Functions:**

- `openPosition(conditionId, tokenId, amount, minTokens, isYes)` - Open a position
- `closePosition(conditionId, tokenAmount, minUsdc)` - Close a position
- `redeemPosition(conditionId)` - Redeem after market resolution
- `totalPositionValue()` - Get total value of all positions
- `getActivePositions()` - Get all active position data

---

### Timelock

**Address:** `0x35C49FE68AEA69EBaAF4ff75066D40adf1F0e9c6`

Time-delayed execution of admin operations for security. Gives users time to exit if they disagree with proposed changes.

**Parameters:**
| Parameter | Value |
|-----------|-------|
| Current Delay | 48 hours |
| Minimum Delay | 48 hours |
| Maximum Delay | 30 days |
| Grace Period | 14 days |

**Roles:**

- `PROPOSER_ROLE` - Can queue transactions
- `EXECUTOR_ROLE` - Can execute ready transactions
- `CANCELLER_ROLE` - Can cancel queued transactions

**Key Functions:**

- `queueTransaction(target, value, data, eta)` - Queue a transaction
- `executeTransaction(target, value, data, eta)` - Execute after delay
- `cancelTransaction(target, value, data, eta)` - Cancel queued transaction

---

### AccessController

**Address:** `0x8704c006F2734be577780FE0209A3CeD7493CEC2`

Role-based access control for the copy-trading system. Implements a hierarchical role system.

**Roles:**
| Role | Description |
|------|-------------|
| `ADMIN_ROLE` | Full control, should be multisig |
| `EXECUTOR_ROLE` | Can execute trades on behalf of vault |
| `GUARDIAN_ROLE` | Can pause the system in emergencies |
| `STRATEGIST_ROLE` | Can manage copy-trading leaders |

**Key Functions:**

- `grantExecutorRole(account)` - Grant executor (requires timelock)
- `revokeExecutorRole(account)` - Revoke executor (immediate)
- `grantGuardianRole(account)` - Grant guardian
- `grantStrategistRole(account)` - Grant strategist
- `isExecutor(account)` / `isGuardian(account)` / `isAdmin(account)` - Role checks

---

## Configuration

**Admin Address:** `0xdf4F65A2d7beB026cc57DeeE76A6083bB4020FB4`

> **Note:** For production use, the admin address should be transferred to a multisig wallet (e.g., Gnosis Safe).

---

## Security Features

1. **ReentrancyGuard** - All state-changing functions protected
2. **Pausable** - Emergency pause (withdrawals always work)
3. **Virtual Shares Offset** - Prevents first-depositor inflation attack
4. **Timelock** - 48-hour delay on sensitive admin operations
5. **Role Separation** - Different roles for different operations
6. **Deposit Caps** - Per-user and total deposit limits
7. **Slippage Protection** - Minimum output checks on trades
8. **Exposure Limits** - Maximum position and total exposure limits
