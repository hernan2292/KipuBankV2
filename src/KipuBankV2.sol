// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./IKipuBankV2.sol";

/**
 * @title KipuBankV2
 * @author KipuBank Team
 * @notice Advanced multi-token banking system with Chainlink price feeds
 * @dev Implements role-based access control, multi-token support, and USD-normalized accounting
 *
 * Features:
 * - Multi-token support (ETH + ERC20)
 * - Chainlink oracle integration for ETH/USD pricing
 * - Role-based access control (Admin, Manager)
 * - USD-normalized internal accounting (6 decimals like USDC)
 * - Configurable bank cap and withdrawal limits
 * - Emergency withdrawal functionality
 * - Gas-optimized with checks-effects-interactions pattern
 */
contract KipuBankV2 is IKipuBankV2, AccessControl, ReentrancyGuard {

    // ========== ROLES ==========

    /// @dev Role for bank managers who can add tokens and update parameters
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // ========== CONSTANTS ==========

    /// @dev Native ETH token representation
    address public constant NATIVE_TOKEN = address(0);

    /// @dev USD decimals for internal accounting (USDC standard)
    uint8 public constant USD_DECIMALS = 6;

    /// @dev Maximum staleness for Chainlink price feeds (1 hour)
    uint256 public constant MAX_PRICE_STALENESS = 3600;

    /// @dev Minimum valid price from oracle
    uint256 public constant MIN_VALID_PRICE = 1e6; // $1 USD

    // ========== IMMUTABLES ==========

    /// @dev Chainlink ETH/USD price feed
    AggregatorV3Interface public immutable ethUsdPriceFeed;

    // ========== STATE VARIABLES ==========

    /// @dev Maximum total bank value in USD (6 decimals)
    uint256 public bankCapUSD;

    /// @dev Maximum withdrawal amount in USD (6 decimals)
    uint256 public withdrawalLimitUSD;

    /// @dev Total bank value in USD (6 decimals)
    uint256 public totalBankValueUSD;

    /// @dev List of all supported tokens
    address[] public supportedTokens;

    /// @dev Mapping: token address => TokenInfo
    mapping(address => TokenInfo) public tokenInfo;

    /// @dev Nested mapping: user => token => balance (in token's native decimals)
    mapping(address => mapping(address => uint256)) public vaults;

    // ========== CONSTRUCTOR ==========

    /**
     * @notice Initialize KipuBankV2 with Chainlink price feed and limits
     * @param _ethUsdPriceFeed Address of Chainlink ETH/USD price feed
     * @param _bankCapUSD Maximum bank capacity in USD (6 decimals)
     * @param _withdrawalLimitUSD Maximum withdrawal in USD (6 decimals)
     */
    constructor(
        address _ethUsdPriceFeed,
        uint256 _bankCapUSD,
        uint256 _withdrawalLimitUSD
    ) {
        if (_ethUsdPriceFeed == address(0)) revert ZeroAddress();
        if (_bankCapUSD == 0) revert InvalidBankCap();
        if (_withdrawalLimitUSD == 0 || _withdrawalLimitUSD > _bankCapUSD) {
            revert InvalidWithdrawalLimit();
        }

        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        bankCapUSD = _bankCapUSD;
        withdrawalLimitUSD = _withdrawalLimitUSD;

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);

        // Add ETH as supported token by default
        tokenInfo[NATIVE_TOKEN] = TokenInfo({
            isSupported: true,
            decimals: 18,
            status: TokenStatus.Active,
            totalDeposits: 0,
            depositCount: 0,
            withdrawalCount: 0
        });
        supportedTokens.push(NATIVE_TOKEN);

        emit TokenAdded(NATIVE_TOKEN, 18);
    }

    // ========== EXTERNAL FUNCTIONS - DEPOSITS ==========

    /**
     * @notice Deposit ETH into your vault
     * @dev Uses Chainlink oracle to convert ETH value to USD
     */
    function depositETH() external payable override nonReentrant {
        if (msg.value == 0) revert ZeroAmount();

        TokenInfo storage info = tokenInfo[NATIVE_TOKEN];
        if (info.status == TokenStatus.Paused) revert TokenPaused();

        // Get ETH price in USD
        uint256 ethPriceUSD = _getETHPrice();

        // Convert deposit amount to USD (6 decimals)
        uint256 depositValueUSD = _convertToUSD(msg.value, 18, ethPriceUSD);

        // Checks
        if (totalBankValueUSD + depositValueUSD > bankCapUSD) revert BankCapExceeded();

        // Effects
        vaults[msg.sender][NATIVE_TOKEN] += msg.value;
        totalBankValueUSD += depositValueUSD;
        info.totalDeposits += depositValueUSD;
        unchecked {
            info.depositCount++;
        }

        // Interactions (none for ETH deposit)

        emit Deposit(msg.sender, NATIVE_TOKEN, msg.value, depositValueUSD, vaults[msg.sender][NATIVE_TOKEN]);
    }

    /**
     * @notice Deposit ERC20 tokens into your vault
     * @param token Address of the ERC20 token
     * @param amount Amount to deposit in token's native decimals
     * @dev Token must be previously added by manager
     */
    function depositToken(address token, uint256 amount) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (token == NATIVE_TOKEN) revert ZeroAddress();

        TokenInfo storage info = tokenInfo[token];
        if (!info.isSupported) revert TokenNotSupported();
        if (info.status == TokenStatus.Paused) revert TokenPaused();

        // Get token value in USD
        // For simplicity, we'll use a 1:1 ratio for stablecoins
        // In production, you'd use Chainlink price feeds for each token
        uint256 depositValueUSD = _convertToUSD(amount, info.decimals, 1e8); // 1:1 for stablecoins

        // Checks
        if (totalBankValueUSD + depositValueUSD > bankCapUSD) revert BankCapExceeded();

        // Effects
        vaults[msg.sender][token] += amount;
        totalBankValueUSD += depositValueUSD;
        info.totalDeposits += depositValueUSD;
        unchecked {
            info.depositCount++;
        }

        // Interactions
        if (!IERC20(token).transferFrom(msg.sender, address(this), amount)) {
            revert TransferFailed();
        }

        emit Deposit(msg.sender, token, amount, depositValueUSD, vaults[msg.sender][token]);
    }

    // ========== EXTERNAL FUNCTIONS - WITHDRAWALS ==========

    /**
     * @notice Withdraw ETH from your vault
     * @param amount Amount to withdraw in wei
     */
    function withdrawETH(uint256 amount) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (vaults[msg.sender][NATIVE_TOKEN] < amount) revert InsufficientBalance();

        // Get ETH price in USD
        uint256 ethPriceUSD = _getETHPrice();

        // Convert withdrawal amount to USD
        uint256 withdrawalValueUSD = _convertToUSD(amount, 18, ethPriceUSD);

        // Checks
        if (withdrawalValueUSD > withdrawalLimitUSD) revert WithdrawalLimitExceeded();

        // Effects
        vaults[msg.sender][NATIVE_TOKEN] -= amount;
        totalBankValueUSD -= withdrawalValueUSD;

        TokenInfo storage info = tokenInfo[NATIVE_TOKEN];
        info.totalDeposits -= withdrawalValueUSD;
        unchecked {
            info.withdrawalCount++;
        }

        uint256 newBalance = vaults[msg.sender][NATIVE_TOKEN];

        // Interactions
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit Withdrawal(msg.sender, NATIVE_TOKEN, amount, withdrawalValueUSD, newBalance);
    }

    /**
     * @notice Withdraw ERC20 tokens from your vault
     * @param token Address of the ERC20 token
     * @param amount Amount to withdraw in token's native decimals
     */
    function withdrawToken(address token, uint256 amount) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (token == NATIVE_TOKEN) revert ZeroAddress();
        if (vaults[msg.sender][token] < amount) revert InsufficientBalance();

        TokenInfo storage info = tokenInfo[token];
        if (!info.isSupported) revert TokenNotSupported();

        // Get token value in USD
        uint256 withdrawalValueUSD = _convertToUSD(amount, info.decimals, 1e8);

        // Checks
        if (withdrawalValueUSD > withdrawalLimitUSD) revert WithdrawalLimitExceeded();

        // Effects
        vaults[msg.sender][token] -= amount;
        totalBankValueUSD -= withdrawalValueUSD;
        info.totalDeposits -= withdrawalValueUSD;
        unchecked {
            info.withdrawalCount++;
        }

        uint256 newBalance = vaults[msg.sender][token];

        // Interactions
        if (!IERC20(token).transfer(msg.sender, amount)) {
            revert TransferFailed();
        }

        emit Withdrawal(msg.sender, token, amount, withdrawalValueUSD, newBalance);
    }

    // ========== EXTERNAL FUNCTIONS - ADMIN ==========

    /**
     * @notice Add a new ERC20 token to the supported list
     * @param token Address of the ERC20 token
     * @dev Only callable by MANAGER_ROLE
     */
    function addToken(address token) external onlyRole(MANAGER_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        if (tokenInfo[token].isSupported) revert TokenAlreadySupported();

        uint8 decimals = IERC20Metadata(token).decimals();
        if (decimals == 0 || decimals > 18) revert InvalidDecimals();

        tokenInfo[token] = TokenInfo({
            isSupported: true,
            decimals: decimals,
            status: TokenStatus.Active,
            totalDeposits: 0,
            depositCount: 0,
            withdrawalCount: 0
        });

        supportedTokens.push(token);

        emit TokenAdded(token, decimals);
    }

    /**
     * @notice Update token status (Active/Paused)
     * @param token Address of the token
     * @param newStatus New status for the token
     * @dev Only callable by MANAGER_ROLE
     */
    function setTokenStatus(address token, TokenStatus newStatus) external onlyRole(MANAGER_ROLE) {
        if (!tokenInfo[token].isSupported) revert TokenNotSupported();

        tokenInfo[token].status = newStatus;

        emit TokenStatusUpdated(token, newStatus);
    }

    /**
     * @notice Update bank cap in USD
     * @param newCapUSD New bank cap in USD (6 decimals)
     * @dev Only callable by MANAGER_ROLE
     */
    function setBankCap(uint256 newCapUSD) external onlyRole(MANAGER_ROLE) {
        if (newCapUSD == 0) revert InvalidBankCap();

        uint256 oldCap = bankCapUSD;
        bankCapUSD = newCapUSD;

        emit BankCapUpdated(oldCap, newCapUSD);
    }

    /**
     * @notice Update withdrawal limit in USD
     * @param newLimitUSD New withdrawal limit in USD (6 decimals)
     * @dev Only callable by MANAGER_ROLE
     */
    function setWithdrawalLimit(uint256 newLimitUSD) external onlyRole(MANAGER_ROLE) {
        if (newLimitUSD == 0 || newLimitUSD > bankCapUSD) revert InvalidWithdrawalLimit();

        uint256 oldLimit = withdrawalLimitUSD;
        withdrawalLimitUSD = newLimitUSD;

        emit WithdrawalLimitUpdated(oldLimit, newLimitUSD);
    }

    /**
     * @notice Emergency withdrawal of tokens (only admin)
     * @param token Address of the token (address(0) for ETH)
     * @param amount Amount to withdraw
     * @param recipient Recipient of the funds
     * @dev Only callable by DEFAULT_ADMIN_ROLE in emergency situations
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        if (token == NATIVE_TOKEN) {
            (bool success, ) = payable(recipient).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            if (!IERC20(token).transfer(recipient, amount)) {
                revert TransferFailed();
            }
        }

        emit EmergencyWithdrawal(token, amount, recipient);
    }

    // ========== EXTERNAL FUNCTIONS - VIEWS ==========

    /**
     * @notice Get user's balance for a specific token
     * @param user Address of the user
     * @param token Address of the token (address(0) for ETH)
     * @return balance Balance in token's native decimals
     */
    function getBalance(address user, address token) external view override returns (uint256 balance) {
        return vaults[user][token];
    }

    /**
     * @notice Get user's balance in USD
     * @param user Address of the user
     * @param token Address of the token (address(0) for ETH)
     * @return balanceUSD Balance in USD (6 decimals)
     */
    function getBalanceInUSD(address user, address token) external view override returns (uint256 balanceUSD) {
        uint256 balance = vaults[user][token];
        if (balance == 0) return 0;

        TokenInfo memory info = tokenInfo[token];
        if (!info.isSupported) return 0;

        if (token == NATIVE_TOKEN) {
            uint256 ethPrice = _getETHPrice();
            return _convertToUSD(balance, info.decimals, ethPrice);
        } else {
            // For ERC20 tokens, use 1:1 ratio (in production, use specific price feeds)
            return _convertToUSD(balance, info.decimals, 1e8);
        }
    }

    /**
     * @notice Get all user balances across all supported tokens
     * @param user Address of the user
     * @return balances Array of UserBalance structs
     */
    function getAllBalances(address user) external view override returns (UserBalance[] memory balances) {
        uint256 tokenCount = supportedTokens.length;
        balances = new UserBalance[](tokenCount);

        for (uint256 i = 0; i < tokenCount; ) {
            address token = supportedTokens[i];
            uint256 balance = vaults[user][token];
            uint256 balanceUSD = 0;

            if (balance > 0) {
                TokenInfo memory info = tokenInfo[token];
                if (token == NATIVE_TOKEN) {
                    uint256 ethPrice = _getETHPrice();
                    balanceUSD = _convertToUSD(balance, info.decimals, ethPrice);
                } else {
                    balanceUSD = _convertToUSD(balance, info.decimals, 1e8);
                }
            }

            balances[i] = UserBalance({
                token: token,
                balance: balance,
                balanceInUSD: balanceUSD
            });

            unchecked {
                i++;
            }
        }

        return balances;
    }

    /**
     * @notice Get token information
     * @param token Address of the token
     * @return info TokenInfo struct
     */
    function getTokenInfo(address token) external view override returns (TokenInfo memory info) {
        return tokenInfo[token];
    }

    /**
     * @notice Get total bank value in USD
     * @return totalUSD Total value in USD (6 decimals)
     */
    function getTotalBankValueUSD() external view override returns (uint256 totalUSD) {
        return totalBankValueUSD;
    }

    /**
     * @notice Get list of all supported tokens
     * @return tokens Array of token addresses
     */
    function getSupportedTokens() external view returns (address[] memory tokens) {
        return supportedTokens;
    }

    /**
     * @notice Get current ETH price in USD from Chainlink
     * @return price ETH price in USD (8 decimals)
     */
    function getETHPriceUSD() external view returns (uint256 price) {
        return _getETHPrice();
    }

    // ========== INTERNAL FUNCTIONS ==========

    /**
     * @notice Get ETH price from Chainlink oracle
     * @return price ETH price in USD (8 decimals)
     * @dev Reverts if price is stale or invalid
     */
    function _getETHPrice() internal view returns (uint256 price) {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethUsdPriceFeed.latestRoundData();

        // Validate price feed data
        if (answeredInRound < roundId) revert StalePrice();
        if (block.timestamp - updatedAt > MAX_PRICE_STALENESS) revert StalePrice();
        if (answer <= 0) revert InvalidPrice();

        price = uint256(answer);
        if (price < MIN_VALID_PRICE) revert InvalidPrice();

        return price;
    }

    /**
     * @notice Convert token amount to USD value (6 decimals)
     * @param amount Amount in token's native decimals
     * @param tokenDecimals Token's decimal places
     * @param priceUSD Price in USD (8 decimals for Chainlink format)
     * @return valueUSD Value in USD (6 decimals)
     * @dev Handles decimal conversion to normalize all values to 6 decimals (USDC standard)
     */
    function _convertToUSD(
        uint256 amount,
        uint8 tokenDecimals,
        uint256 priceUSD
    ) internal pure returns (uint256 valueUSD) {
        // Formula: (amount * priceUSD) / (10^tokenDecimals * 10^8) * 10^6
        // Simplified: (amount * priceUSD * 10^6) / (10^tokenDecimals * 10^8)
        // Further: (amount * priceUSD) / (10^(tokenDecimals + 8 - 6))
        // Final: (amount * priceUSD) / 10^(tokenDecimals + 2)

        uint256 denominator = 10 ** (tokenDecimals + 2);
        valueUSD = (amount * priceUSD) / denominator;

        return valueUSD;
    }

    /**
     * @notice Convert USD value (6 decimals) to token amount
     * @param valueUSD Value in USD (6 decimals)
     * @param tokenDecimals Token's decimal places
     * @param priceUSD Price in USD (8 decimals)
     * @return amount Amount in token's native decimals
     */
    function _convertFromUSD(
        uint256 valueUSD,
        uint8 tokenDecimals,
        uint256 priceUSD
    ) internal pure returns (uint256 amount) {
        // Formula: (valueUSD * 10^tokenDecimals * 10^8) / (priceUSD * 10^6)
        // Simplified: (valueUSD * 10^(tokenDecimals + 8 - 6)) / priceUSD
        // Final: (valueUSD * 10^(tokenDecimals + 2)) / priceUSD

        uint256 numerator = valueUSD * (10 ** (tokenDecimals + 2));
        amount = numerator / priceUSD;

        return amount;
    }
}
