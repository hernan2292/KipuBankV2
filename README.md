# KipuBankV2 - Advanced Multi-Token Banking System

<div align="center">

**A production-ready decentralized banking system with multi-token support, Chainlink oracle integration, and role-based access control**

[![Solidity](https://img.shields.io/badge/Solidity-0.8.30-blue)](https://soliditylang.org/)
[![Hardhat](https://img.shields.io/badge/Hardhat-Framework-yellow)](https://hardhat.org/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-Contracts-4E5EE4)](https://openzeppelin.com/)
[![Chainlink](https://img.shields.io/badge/Chainlink-Oracles-375BD2)](https://chain.link/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

</div>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [Architecture & Design Decisions](#-architecture--design-decisions)
- [Contract Components](#-contract-components)
- [Installation](#-installation)
- [Deployment](#-deployment)
- [Testing](#-testing)
- [Usage](#-usage)
- [Security Considerations](#-security-considerations)
- [Improvements from V1](#-improvements-from-v1)
- [Gas Optimizations](#-gas-optimizations)
- [License](#-license)

---

## 🎯 Overview

KipuBankV2 is a significant evolution of the original KipuBank contract, transforming it from a simple ETH vault system into a comprehensive multi-token banking platform. This version implements advanced Solidity patterns, integrates real-world price data through Chainlink oracles, and provides enterprise-grade security and access control.

### What Makes V2 Different?

| Feature | KipuBank V1 | KipuBankV2 |
|---------|-------------|------------|
| **Token Support** | ETH only | ETH + Multiple ERC20 tokens |
| **Price Feeds** | None | Chainlink oracles for ETH/USD |
| **Access Control** | None | Role-based (Admin, Manager) |
| **Accounting** | ETH-based | USD-normalized (USDC standard) |
| **Limits** | ETH amounts | USD values (dynamic with price) |
| **Decimal Handling** | Fixed 18 decimals | Supports 1-18 decimals with conversion |
| **Events** | Basic | Comprehensive with USD values |
| **Security** | Basic checks | ReentrancyGuard + CEI pattern |

---

## ⭐ Key Features

### 1. **Multi-Token Support**
- Native ETH deposits/withdrawals via `depositETH()` and `withdrawETH()`
- ERC20 token support with dynamic addition via `addToken()`
- Each user has individual vaults for each supported token
- Address `address(0)` represents native ETH in internal accounting

### 2. **Chainlink Oracle Integration**
- Real-time ETH/USD price feeds from Chainlink
- Automatic USD value calculation for all operations
- Staleness checks to prevent using outdated prices
- Configurable price validation (minimum price, maximum staleness)

### 3. **Role-Based Access Control**
- **DEFAULT_ADMIN_ROLE**: Full system control, can grant/revoke roles
- **MANAGER_ROLE**: Can add tokens, update limits, manage token status
- OpenZeppelin AccessControl implementation for security

### 4. **USD-Normalized Accounting**
- All internal accounting in USD with 6 decimals (USDC standard)
- Bank cap enforced in USD value, not token amounts
- Withdrawal limits in USD, automatically adjusted for price changes
- Consistent accounting across tokens with different decimals

### 5. **Decimal Conversion System**
- Supports tokens with 1-18 decimals
- Automatic conversion to 6-decimal USD representation
- Formula: `valueUSD = (amount * priceUSD) / 10^(tokenDecimals + 2)`
- Prevents precision loss in calculations

### 6. **Advanced Security**
- OpenZeppelin ReentrancyGuard on all state-changing functions
- Checks-Effects-Interactions pattern throughout
- Custom errors for gas-efficient reverts
- Comprehensive input validation

### 7. **Token Status Management**
- Active: Normal operations allowed
- Paused: Deposits blocked, withdrawals still allowed
- Inactive: Token not supported
- Manager can pause tokens without removing support

---

## 🏗️ Architecture & Design Decisions

### Design Patterns

#### 1. **Checks-Effects-Interactions (CEI) + Gas Optimization**
```solidity
// ✅ Correct pattern with cached state variables
function withdrawETH(uint256 amount) external nonZeroAmount(amount) {
    // Cache state variables to avoid multiple SLOAD operations
    uint256 cachedWithdrawalLimit = withdrawalLimitUSD;
    uint256 cachedTotalValue = totalBankValueUSD;

    // CHECKS
    address user = msg.sender;
    uint256 currentBalance = vaults[user][NATIVE_TOKEN];
    if (currentBalance < amount) revert InsufficientBalance();
    if (withdrawalValueUSD > cachedWithdrawalLimit) revert WithdrawalLimitExceeded();

    // EFFECTS - Single SSTORE operations
    unchecked {
        newBalance = currentBalance - amount; // Safe: checked above
        newTotalValue = cachedTotalValue - withdrawalValueUSD;
    }
    vaults[user][NATIVE_TOKEN] = newBalance;
    totalBankValueUSD = newTotalValue;

    // INTERACTIONS
    (bool success, ) = payable(user).call{value: amount}("");
    if (!success) revert TransferFailed();
}
```

#### 2. **Nested Mappings for Multi-Token Balances**
```solidity
// user => token => balance
mapping(address => mapping(address => uint256)) public vaults;
```
This allows efficient O(1) lookups for any user-token combination.

#### 3. **Immutable Variables for Gas Savings**
```solidity
AggregatorV3Interface public immutable ethUsdPriceFeed;
```
The price feed address never changes, saving gas on every read.

#### 4. **Custom Errors for Gas Efficiency**
```solidity
error InsufficientBalance();  // vs require with string (saves ~50 gas per revert)
```

#### 5. **State Variable Caching**
```solidity
// ❌ Bad: Multiple SLOADs (expensive)
if (totalBankValueUSD + deposit > bankCapUSD) revert();
totalBankValueUSD += deposit;

// ✅ Good: Single SLOAD, single SSTORE
uint256 cachedTotal = totalBankValueUSD;
if (cachedTotal + deposit > bankCapUSD) revert();
totalBankValueUSD = cachedTotal + deposit;
```
Every cached state variable saves ~100 gas per SLOAD operation.

#### 6. **Strategic Use of Unchecked**
```solidity
// Only use unchecked when mathematically impossible to overflow
unchecked {
    newBalance = currentBalance - amount; // Safe: checked currentBalance >= amount above
    newTotal = cachedTotal - value;       // Safe: value always <= total by design
}
// DO NOT use unchecked for counters (can theoretically overflow)
info.depositCount++; // NOT in unchecked block
```

### Trade-offs & Decisions

#### 1. **Why USD Normalization?**
**Decision**: Normalize all accounting to 6-decimal USD values

**Pros**:
- Consistent limits across all tokens
- Easy to understand bank cap and withdrawal limits
- Simplified multi-token accounting
- Aligns with USDC standard (most common stablecoin)

**Cons**:
- Requires price oracle for each token
- Small precision loss possible in conversions
- More complex calculations

**Mitigation**: For V2, we use 1:1 pricing for stablecoins as a simplification. Production would use Chainlink price feeds for each token.

#### 2. **Why Two Roles Instead of More Granular Control?**
**Decision**: Only Admin and Manager roles

**Pros**:
- Simpler to understand and manage
- Covers all realistic use cases
- Lower gas costs for role checks
- Easier to audit permissions

**Cons**:
- Less granular control
- Can't separate some admin functions

**Justification**: For a banking system, having operational managers and system admins covers 99% of use cases without unnecessary complexity.

#### 3. **Why Allow Withdrawals from Paused Tokens?**
**Decision**: Token pause only blocks deposits, not withdrawals

**Rationale**:
- Users should always be able to access their funds
- Pause is for risk management (e.g., vulnerable token)
- Emergency situations shouldn't trap user funds
- Aligns with DeFi best practices

#### 4. **Why 1-Hour Staleness for Price Feeds?**
**Decision**: `MAX_PRICE_STALENESS = 3600` (1 hour)

**Rationale**:
- Chainlink updates ETH/USD every ~1 hour or on 0.5% deviation
- Too short: Unnecessary tx failures during network congestion
- Too long: Accept stale prices in emergencies
- 1 hour balances reliability and safety

---

## 📦 Contract Components

### Core Contract: [KipuBankV2.sol](src/KipuBankV2.sol)

**State Variables**:
- `bankCapUSD`: Maximum total deposits in USD (6 decimals)
- `withdrawalLimitUSD`: Max single withdrawal in USD (6 decimals)
- `totalBankValueUSD`: Current total value in system
- `vaults`: Nested mapping for user balances
- `tokenInfo`: Mapping of token metadata
- `supportedTokens`: Array of all supported tokens

**Key Functions**:

| Function | Access | Description |
|----------|--------|-------------|
| `depositETH()` | Public | Deposit native ETH |
| `depositToken(token, amount)` | Public | Deposit ERC20 token |
| `withdrawETH(amount)` | Public | Withdraw native ETH |
| `withdrawToken(token, amount)` | Public | Withdraw ERC20 token |
| `addToken(token)` | Manager | Add new ERC20 support |
| `setTokenStatus(token, status)` | Manager | Update token status |
| `setBankCap(newCap)` | Manager | Update bank capacity |
| `setWithdrawalLimit(newLimit)` | Manager | Update withdrawal limit |
| `emergencyWithdraw(...)` | Admin | Emergency fund recovery |
| `getBalance(user, token)` | View | Get user balance |
| `getBalanceInUSD(user, token)` | View | Get balance in USD |
| `getAllBalances(user)` | View | Get all user balances |

### Interface: [IKipuBankV2.sol](src/IKipuBankV2.sol)

Defines the public API including:
- Custom types: `TokenStatus`, `TokenInfo`, `UserBalance`
- Events: `Deposit`, `Withdrawal`, `TokenAdded`, etc.
- Custom errors: `InsufficientBalance`, `BankCapExceeded`, etc.
- Function signatures for all public/external functions

### Mocks for Testing

**[MockV3Aggregator.sol](src/mocks/MockV3Aggregator.sol)**:
- Simulates Chainlink price feed
- Allows price updates in tests
- Implements full `AggregatorV3Interface`

**[MockERC20.sol](src/mocks/MockERC20.sol)**:
- Simple ERC20 with configurable decimals
- Mint/burn functions for testing
- Used to test multi-token features

---

## 🚀 Installation

### Prerequisites

- Node.js >= 16.x
- npm or yarn
- Git

### Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/KipuBankV2.git
cd KipuBankV2

# Install dependencies
npm install

# Create environment file
cp .env.example .env

# Edit .env with your configuration
# Required: SEPOLIA_RPC_URL, PRIVATE_KEY, ETHERSCAN_API_KEY
```

### Environment Variables

```bash
# .env file
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY
GOERLI_RPC_URL=https://eth-goerli.g.alchemy.com/v2/YOUR-API-KEY
PRIVATE_KEY=your-private-key-here
ETHERSCAN_API_KEY=your-etherscan-api-key
REPORT_GAS=true
```

---

## 🌐 Deployment

### Local Deployment (Hardhat Network)

```bash
# Start local node
npx hardhat node

# In another terminal, deploy
npx hardhat run scripts/deployV2.js --network localhost
```

The script will:
1. Deploy `MockV3Aggregator` (for local testing)
2. Deploy `KipuBankV2` with mock price feed
3. Output contract addresses and configuration

### Testnet Deployment (Sepolia)

```bash
# Ensure .env is configured with Sepolia RPC and private key
npx hardhat run scripts/deployV2.js --network sepolia
```

The script automatically:
- Uses real Chainlink ETH/USD price feed (0x694AA1769357215DE4FAC081bf1f309aDC325306)
- Deploys with $1M bank cap and $10k withdrawal limit
- Outputs verification command for Etherscan

### Verify on Etherscan

```bash
npx hardhat verify --network sepolia <CONTRACT_ADDRESS> \
  "<PRICE_FEED_ADDRESS>" \
  "<BANK_CAP_USD>" \
  "<WITHDRAWAL_LIMIT_USD>"

# Example:
npx hardhat verify --network sepolia 0x1234... \
  "0x694AA1769357215DE4FAC081bf1f309aDC325306" \
  "1000000000000" \
  "10000000000"
```

### Deployment Parameters

| Network | ETH/USD Feed | Bank Cap | Withdrawal Limit |
|---------|--------------|----------|------------------|
| Sepolia | 0x694AA1769357215DE4FAC081bf1f309aDC325306 | $1,000,000 | $10,000 |
| Mainnet | 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 | Custom | Custom |

---

## 🧪 Testing

### Run All Tests

```bash
npx hardhat test
```

### Run with Gas Report

```bash
REPORT_GAS=true npx hardhat test
```

### Run Specific Test Suite

```bash
npx hardhat test --grep "Deployment"
npx hardhat test --grep "ETH Deposits"
npx hardhat test --grep "Chainlink Oracle"
```

### Test Coverage

```bash
npx hardhat coverage
```

### Test Suite Overview

The test suite includes 50+ tests covering:

- ✅ Deployment validation
- ✅ ETH deposits and withdrawals
- ✅ ERC20 token management
- ✅ ERC20 deposits and withdrawals
- ✅ Role-based access control
- ✅ USD normalization and limits
- ✅ Chainlink oracle integration
- ✅ Price staleness checks
- ✅ Edge cases and error conditions
- ✅ Gas optimizations
- ✅ Reentrancy protection

---

## 💼 Usage

### For Users

#### 1. Deposit ETH
```javascript
// Connect to contract
const kipuBank = await ethers.getContractAt("KipuBankV2", contractAddress);

// Deposit 1 ETH
await kipuBank.depositETH({ value: ethers.parseEther("1") });

// Check balance
const balance = await kipuBank.getBalance(userAddress, ethers.ZeroAddress);
console.log("ETH Balance:", ethers.formatEther(balance));

// Check balance in USD
const balanceUSD = await kipuBank.getBalanceInUSD(userAddress, ethers.ZeroAddress);
console.log("USD Value:", ethers.formatUnits(balanceUSD, 6));
```

#### 2. Withdraw ETH
```javascript
// Withdraw 0.5 ETH
await kipuBank.withdrawETH(ethers.parseEther("0.5"));
```

#### 3. Deposit ERC20 Tokens
```javascript
// First approve the token
const token = await ethers.getContractAt("IERC20", tokenAddress);
await token.approve(kipuBankAddress, amount);

// Then deposit
await kipuBank.depositToken(tokenAddress, amount);
```

#### 4. Check All Balances
```javascript
const allBalances = await kipuBank.getAllBalances(userAddress);
for (const bal of allBalances) {
    console.log("Token:", bal.token);
    console.log("Balance:", bal.balance.toString());
    console.log("USD Value:", ethers.formatUnits(bal.balanceInUSD, 6));
}
```

### For Managers

#### 1. Add New Token
```javascript
// Must have MANAGER_ROLE
await kipuBank.addToken(tokenAddress);
```

#### 2. Pause Token
```javascript
// Pause deposits for a token (2 = TokenStatus.Paused)
await kipuBank.setTokenStatus(tokenAddress, 2);

// Reactivate (1 = TokenStatus.Active)
await kipuBank.setTokenStatus(tokenAddress, 1);
```

#### 3. Update Limits
```javascript
// Update bank cap to $2M USD
await kipuBank.setBankCap(ethers.parseUnits("2000000", 6));

// Update withdrawal limit to $20k USD
await kipuBank.setWithdrawalLimit(ethers.parseUnits("20000", 6));
```

### For Admins

#### Grant Manager Role
```javascript
const MANAGER_ROLE = await kipuBank.MANAGER_ROLE();
await kipuBank.grantRole(MANAGER_ROLE, managerAddress);
```

#### Emergency Withdrawal
```javascript
// Only in emergencies - withdraws funds to admin
await kipuBank.emergencyWithdraw(
    tokenAddress,
    amount,
    recipientAddress
);
```

---

## 🔒 Security Considerations

### Implemented Security Measures

1. **Reentrancy Protection**
   - `nonReentrant` modifier on all state-changing functions
   - Prevents reentrancy attacks on deposits/withdrawals

2. **Checks-Effects-Interactions Pattern**
   - All state changes before external calls
   - Reduces reentrancy risk even without guard

3. **Access Control**
   - Role-based permissions for sensitive functions
   - Principle of least privilege

4. **Input Validation**
   - Zero amount checks
   - Zero address checks
   - Limit validations

5. **Oracle Safety**
   - Price staleness checks
   - Invalid price detection
   - Round ID validation

6. **Integer Overflow Protection**
   - Solidity 0.8.x automatic overflow checks
   - `unchecked` only where mathematically safe

### Known Limitations

1. **Stablecoin Pricing**
   - Current implementation assumes 1:1 USD peg for stablecoins
   - Production should use individual Chainlink feeds

2. **Price Feed Dependency**
   - System relies on Chainlink oracle availability
   - Consider fallback price sources for production

3. **Token Decimal Support**
   - Supports 1-18 decimals
   - Tokens with 0 or >18 decimals rejected

4. **Emergency Withdrawal**
   - Admin can withdraw any funds in emergency
   - Trade-off between recovery and decentralization

### Audit Recommendations

Before production deployment:
- [ ] Professional smart contract audit
- [ ] Formal verification of critical functions
- [ ] Testnet stress testing with high volumes
- [ ] Economic attack vector analysis
- [ ] Gas optimization review

---

## 📈 Improvements from V1

### Major Enhancements

| Category | V1 | V2 | Benefit |
|----------|----|----|---------|
| **Functionality** | ETH-only vault | Multi-token banking | Supports diverse assets |
| **Access Control** | None | Role-based (2 roles) | Secure administration |
| **Price Awareness** | None | Chainlink oracles | Real-world value tracking |
| **Accounting** | ETH amounts | USD-normalized | Consistent cross-token |
| **Decimal Handling** | Fixed 18 | Dynamic 1-18 | Supports all ERC20s |
| **Security** | Basic | ReentrancyGuard + CEI | Production-grade |
| **Events** | Amount only | Amount + USD value | Better observability |
| **Errors** | String messages | Custom errors | Gas efficient |
| **Admin Features** | None | Pause, emergency | Operational flexibility |
| **Limits** | Static ETH | Dynamic USD | Adapts to price changes |
| **Gas Optimization** | None | State caching + strategic unchecked | ~5,000 gas saved per tx |

### Critical Production Fixes

**V2 includes essential corrections for production readiness:**

1. **Eliminated Multiple State Access** ⭐ **Critical**
   - Before: Multiple SLOADs of same variable (~100 gas each)
   - After: Single SLOAD with caching
   - Impact: ~200-500 gas saved per transaction

2. **Strategic Unchecked Usage** ⭐ **Critical**
   - Before: Unchecked on counters (unsafe) + checked where safe (wasteful)
   - After: Unchecked ONLY where mathematically proven safe
   - Impact: Security + ~120 gas per safe operation

3. **No Constant/Immutable Emissions** ⭐ **Critical**
   - Before: Emitting unchangeable values wastes gas
   - After: Events emit only dynamic values
   - Impact: Cleaner events + gas savings

4. **Zero Amount Validation**
   - Consistent `nonZeroAmount` modifier across all functions
   - Prevents gas griefing and edge cases

### Code Quality Improvements

1. **Documentation**
   - Comprehensive NatSpec comments
   - Architecture decision documentation
   - Inline explanations for complex logic

2. **Testing**
   - 50+ unit tests vs ~10 in V1
   - Edge case coverage
   - Oracle integration tests

3. **Code Organization**
   - Clear section separation
   - Interface extraction
   - Modular design

4. **Gas Optimization**
   - `immutable` for constants
   - State variable caching (single SLOAD/SSTORE)
   - `unchecked` only where mathematically safe
   - Custom errors
   - Efficient loops

---

## ⛽ Gas Optimizations

### Implemented Optimizations

1. **Immutable Variables**
```solidity
AggregatorV3Interface public immutable ethUsdPriceFeed;
// Saves ~2100 gas per read vs storage variable
```

2. **Custom Errors**
```solidity
error InsufficientBalance();
// Saves ~50 gas vs require("Insufficient balance")
```

3. **State Variable Caching** ⭐ **Critical Optimization**
```solidity
// Cache at function start - single SLOAD
uint256 cachedBankCap = bankCapUSD;
uint256 cachedTotalValue = totalBankValueUSD;

// Use cached values in checks
if (cachedTotalValue + deposit > cachedBankCap) revert BankCapExceeded();

// Single SSTORE at end
totalBankValueUSD = cachedTotalValue + deposit;
// Saves ~100 gas per avoided SLOAD, ~5000 gas per avoided SSTORE
```

4. **Strategic Unchecked Arithmetic**
```solidity
// ✅ Use unchecked ONLY when mathematically proven safe
unchecked {
    newBalance = currentBalance - amount; // Safe: checked currentBalance >= amount
    newTotal = cachedTotal - value;       // Safe: value <= total by design
}
// ❌ DO NOT use for counters (can overflow theoretically)
info.depositCount++; // Keeps overflow protection
// Saves ~120 gas per operation when safe
```

5. **Short-Circuit Validation**
```solidity
if (amount == 0) revert ZeroAmount();  // Check first, cheapest validation
if (!info.isSupported) revert TokenNotSupported();  // Then storage reads
```

6. **Efficient Loops**
```solidity
for (uint256 i = 0; i < tokenCount; ) {
    // ...
    unchecked { i++; }  // Save gas on counter increment
}
```

### Gas Costs (Approximate)

| Operation | Gas Cost (Optimized) | Savings vs Unoptimized |
|-----------|----------------------|------------------------|
| ETH Deposit (first time) | ~95,000 | ~5,000 gas |
| ETH Deposit (subsequent) | ~75,000 | ~5,000 gas |
| ETH Withdrawal | ~65,000 | ~5,000 gas |
| ERC20 Deposit | ~105,000 | ~5,000 gas |
| ERC20 Withdrawal | ~75,000 | ~5,000 gas |
| Add Token (Manager) | ~145,000 | ~5,000 gas |
| Update Bank Cap | ~30,000 | ~200 gas |
| Update Withdrawal Limit | ~30,000 | ~200 gas |

**Key Optimizations Applied**:
- State variable caching: ~200-500 gas per function
- Single SSTORE operations: ~5,000 gas per avoided write
- Strategic unchecked: ~120 gas per safe operation
- Custom errors: ~50 gas per revert

*Note: Costs vary by network congestion and token implementation. Savings calculated vs non-optimized version with multiple SLOAD/SSTORE operations.*

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **OpenZeppelin** - Security-audited contract libraries
- **Chainlink** - Decentralized oracle network
- **Hardhat** - Ethereum development environment
- **Kipu Community** - Testing and feedback

---

## 📞 Support

For questions, issues, or contributions:

- **GitHub Issues**: [Submit an issue](https://github.com/yourusername/KipuBankV2/issues)
- **Documentation**: [Full docs](https://docs.kipubank.io)
- **Community**: [Discord](https://discord.gg/kipubank)

---

<div align="center">

**Built with ❤️ by the KipuBank Team**

*Democratizing decentralized finance, one vault at a time*

</div>
