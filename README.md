# Goblin Market Smart Contracts

Smart contracts for the Goblin Market copy-trading platform - a social execution layer for Polymarket.

## Overview

Goblin Market enables users to automatically mirror the trading strategies of expert traders ("Leaders") on Polymarket. Users deposit USDC into a vault, and when a Leader executes a trade, the vault automatically executes the same trade proportionally.

### Key Features

- **Vault-Based Copy Trading** - Pooled funds model using ERC-4626 tokenized vault
- **Real Polymarket Positions** - Actual positions on Polymarket, not synthetic
- **Non-Custodial** - Users can withdraw anytime (subject to liquidity)
- **Role-Based Security** - Multisig admin, timelocked upgrades, guardian pause
- **Professional Grade** - Built with OpenZeppelin, comprehensive test coverage

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      USER INTERACTION                        │
│  ┌─────────────┐                         ┌─────────────┐    │
│  │   Deposit   │                         │  Withdraw   │    │
│  │    USDC     │                         │   USDC      │    │
│  └──────┬──────┘                         └──────▲──────┘    │
└─────────┼───────────────────────────────────────┼───────────┘
          │                                       │
          ▼                                       │
┌─────────────────────────────────────────────────────────────┐
│                        COPYVAULT                             │
│                       (ERC-4626)                             │
│  • Deposit/Withdraw          • Share Accounting              │
│  • Leader Management         • Fee Collection                │
│  • Trade Allocation          • Emergency Pause               │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                    POSITION MANAGER                          │
│  • Open/Close Positions      • Position Tracking             │
│  • Slippage Protection       • P&L Calculation               │
│  • Market Resolution         • Exposure Limits               │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                       POLYMARKET                             │
│  • CLOB (Order Book)         • CTF (Conditional Tokens)      │
│  • Trade Execution           • Settlement                    │
└─────────────────────────────────────────────────────────────┘
```

## Contracts

| Contract               | Description                                                                      |
| ---------------------- | -------------------------------------------------------------------------------- |
| `CopyVault.sol`        | Main vault contract (ERC-4626) - handles deposits, withdrawals, share accounting |
| `PositionManager.sol`  | Manages Polymarket positions - open, close, redeem, track P&L                    |
| `AccessController.sol` | Role-based access control with timelock integration                              |
| `Timelock.sol`         | Time-delayed execution for admin operations (48h minimum)                        |

## Security Features

- **ReentrancyGuard** on all state-changing functions
- **Role-Based Access Control** with hierarchical permissions
- **Timelock** for sensitive admin operations (48-hour delay)
- **Pausable** with withdrawals always allowed
- **Virtual Shares Offset** prevents first-depositor inflation attacks
- **Deposit Caps** per-user and vault-wide limits
- **Trade Size Limits** maximum 5% of vault per trade (configurable)
- **Slippage Protection** on all trades

### Role Hierarchy

```
ADMIN (Multisig)
├── Full control over parameters
├── Can unpause, upgrade, manage roles
└── Requires timelock for sensitive operations

EXECUTOR (Backend Service)
├── Can allocate funds for trades
├── Can open/close positions
└── Granted via timelock

GUARDIAN (Security Team)
├── Can pause contracts
└── Cannot steal funds or unpause

STRATEGIST (Trading Team)
├── Can add/remove leaders
└── Cannot execute trades
```

## Getting Started

### Prerequisites

- Node.js >= 18.0.0
- npm or yarn

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/goblin_smart_contract.git
cd goblin_smart_contract

# Install dependencies
npm install

# Copy environment variables
cp .env.example .env
# Edit .env with your configuration
```

### Compile Contracts

```bash
npm run compile
```

### Run Tests

```bash
# Run all tests
npm run test

# Run with coverage
npm run test:coverage

# Run specific test file
npx hardhat test test/CopyVault.test.ts
```

### Local Development

```bash
# Start local Hardhat node
npm run node

# In another terminal, deploy to local network
npm run deploy:local
```

## Deployment

### Testnet (Polygon Amoy)

```bash
# Set environment variables
export POLYGON_AMOY_RPC_URL="https://rpc-amoy.polygon.technology"
export PRIVATE_KEY="your_private_key"

# Deploy
npm run deploy:amoy
```

### Mainnet (Polygon)

```bash
# Set environment variables
export POLYGON_RPC_URL="https://polygon-rpc.com"
export PRIVATE_KEY="your_private_key"

# Deploy
npm run deploy:polygon
```

## Configuration

### Environment Variables

| Variable               | Description                          |
| ---------------------- | ------------------------------------ |
| `POLYGON_RPC_URL`      | Polygon mainnet RPC URL              |
| `POLYGON_AMOY_RPC_URL` | Polygon Amoy testnet RPC URL         |
| `PRIVATE_KEY`          | Deployer private key (without 0x)    |
| `POLYGONSCAN_API_KEY`  | Polygonscan API key for verification |
| `REPORT_GAS`           | Enable gas reporting in tests        |

### Vault Parameters

| Parameter           | Default     | Description                      |
| ------------------- | ----------- | -------------------------------- |
| `maxTotalDeposits`  | $10,000,000 | Maximum total deposits in vault  |
| `maxDepositPerUser` | $100,000    | Maximum deposit per user         |
| `minDeposit`        | $10         | Minimum deposit amount           |
| `maxTradeSizeBps`   | 500 (5%)    | Maximum trade size as % of vault |
| `performanceFee`    | 1000 (10%)  | Performance fee on profits       |
| `managementFee`     | 200 (2%)    | Annual management fee            |

## Project Structure

```
goblin_smart_contract/
├── contracts/
│   ├── core/
│   │   ├── CopyVault.sol          # Main vault (ERC-4626)
│   │   └── PositionManager.sol    # Position management
│   ├── access/
│   │   ├── AccessController.sol   # Role-based access
│   │   └── Timelock.sol          # Time-delayed admin
│   ├── interfaces/
│   │   ├── ICopyVault.sol
│   │   ├── IPositionManager.sol
│   │   └── IConditionalTokens.sol # Polymarket CTF
│   └── mocks/
│       ├── MockUSDC.sol
│       └── MockConditionalTokens.sol
├── test/
│   ├── CopyVault.test.ts
│   ├── PositionManager.test.ts
│   └── AccessController.test.ts
├── scripts/
│   └── deploy.ts
├── docs/
│   ├── goblin_market_doc.md           # Product documentation
│   ├── copy_trading_architecture.md   # Technical architecture
│   └── backend_integration_guide.md   # Backend integration guide
├── hardhat.config.ts
└── package.json
```

## Testing

The project includes comprehensive tests with **114 test cases** covering:

- **CopyVault**: Deposits, withdrawals, share calculation, trade allocation, leader management, emergency functions
- **PositionManager**: Position opening/closing, value calculation, exposure limits
- **AccessController**: Role management, timelock integration
- **Timelock**: Transaction queuing, execution, cancellation

```bash
# Run tests with verbose output
npx hardhat test --verbose

# Run tests with gas reporting
REPORT_GAS=true npm run test
```

## Documentation

| Document                                                    | Description                                 |
| ----------------------------------------------------------- | ------------------------------------------- |
| [Product Doc](docs/goblin_market_doc.md)                    | Product overview and architecture decisions |
| [Technical Architecture](docs/copy_trading_architecture.md) | Detailed technical specification            |
| [Backend Integration](docs/backend_integration_guide.md)    | Guide for backend engineers                 |

## External Dependencies

### Polymarket Contracts (Polygon)

| Contract                 | Address                                      |
| ------------------------ | -------------------------------------------- |
| USDC                     | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` |
| CTF (Conditional Tokens) | `0x4D97DCd97eC945f40cF65F87097ACe5EA0476045` |
| Exchange                 | `0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E` |

### OpenZeppelin Contracts

- ERC4626 (Tokenized Vault)
- AccessControl (Role-Based Permissions)
- ReentrancyGuard
- Pausable
- SafeERC20

## Scripts

| Command                  | Description                     |
| ------------------------ | ------------------------------- |
| `npm run compile`        | Compile contracts               |
| `npm run test`           | Run all tests                   |
| `npm run test:coverage`  | Run tests with coverage report  |
| `npm run deploy:local`   | Deploy to local Hardhat network |
| `npm run deploy:amoy`    | Deploy to Polygon Amoy testnet  |
| `npm run deploy:polygon` | Deploy to Polygon mainnet       |
| `npm run clean`          | Clean build artifacts           |
| `npm run node`           | Start local Hardhat node        |

## Security Considerations

### Audit Status

- [ ] Internal review completed
- [ ] External audit (pending)
- [ ] Bug bounty program (pending)

### Known Limitations

1. **Liquidity Risk**: Withdrawals limited by idle assets (funds not in positions)
2. **Oracle Dependency**: Position valuation depends on price oracle accuracy
3. **Polymarket Integration**: Requires off-chain backend for trade execution on Polymarket CLOB

### Reporting Security Issues

Please report security vulnerabilities to security@goblinmarket.com (do not create public issues).

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style

- Solidity: Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- TypeScript: ESLint + Prettier configuration included
- Comments: NatSpec for all public functions

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [OpenZeppelin](https://openzeppelin.com/) - Security-audited contract libraries
- [Hardhat](https://hardhat.org/) - Development environment
- [Polymarket](https://polymarket.com/) - Prediction market infrastructure

---

Built with ❤️ by the Goblin Market team
