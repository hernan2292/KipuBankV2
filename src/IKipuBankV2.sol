// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IKipuBankV2
 * @notice Interface for KipuBankV2 contract
 * @dev Defines all external functions and events for the multi-token banking system
 */
interface IKipuBankV2 {

    // ========== CUSTOM TYPES ==========

    /**
     * @dev Status of a token in the system
     */
    enum TokenStatus {
        Inactive,      // Token not supported
        Active,        // Token active and accepting deposits
        Paused         // Token paused, no deposits allowed
    }

    /**
     * @dev Information about a supported token
     */
    struct TokenInfo {
        bool isSupported;          // Whether token is supported
        uint8 decimals;            // Token decimals
        TokenStatus status;        // Current status
        uint256 totalDeposits;     // Total deposits in USD value (normalized to 6 decimals)
        uint256 depositCount;      // Number of deposits for this token
        uint256 withdrawalCount;   // Number of withdrawals for this token
    }

    /**
     * @dev User balance information
     */
    struct UserBalance {
        address token;             // Token address (address(0) for ETH)
        uint256 balance;           // Balance in token's native decimals
        uint256 balanceInUSD;      // Balance in USD (6 decimals)
    }

    // ========== EVENTS ==========

    /**
     * @dev Emitted when a user deposits tokens
     * @param user Address of the user
     * @param token Address of the token (address(0) for ETH)
     * @param amount Amount deposited in token's native decimals
     * @param usdValue USD value of the deposit (6 decimals)
     * @param newBalance User's new balance in token
     */
    event Deposit(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 usdValue,
        uint256 newBalance
    );

    /**
     * @dev Emitted when a user withdraws tokens
     * @param user Address of the user
     * @param token Address of the token (address(0) for ETH)
     * @param amount Amount withdrawn in token's native decimals
     * @param usdValue USD value of the withdrawal (6 decimals)
     * @param newBalance User's new balance in token
     */
    event Withdrawal(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 usdValue,
        uint256 newBalance
    );

    /**
     * @dev Emitted when a new token is added to the system
     * @param token Address of the token
     * @param decimals Token decimals
     */
    event TokenAdded(address indexed token, uint8 decimals);

    /**
     * @dev Emitted when a token's status is updated
     * @param token Address of the token
     * @param newStatus New status of the token
     */
    event TokenStatusUpdated(address indexed token, TokenStatus newStatus);

    /**
     * @dev Emitted when bank cap is updated
     * @param oldCap Previous cap in USD (6 decimals)
     * @param newCap New cap in USD (6 decimals)
     */
    event BankCapUpdated(uint256 oldCap, uint256 newCap);

    /**
     * @dev Emitted when withdrawal limit is updated
     * @param oldLimit Previous limit in USD (6 decimals)
     * @param newLimit New limit in USD (6 decimals)
     */
    event WithdrawalLimitUpdated(uint256 oldLimit, uint256 newLimit);

    /**
     * @dev Emitted when emergency withdrawal is executed
     * @param token Address of the token
     * @param amount Amount withdrawn
     * @param recipient Recipient of the funds
     */
    event EmergencyWithdrawal(address indexed token, uint256 amount, address indexed recipient);

    // ========== CUSTOM ERRORS ==========

    /// @dev Thrown when deposit/withdrawal amount is zero
    error ZeroAmount();

    /// @dev Thrown when user has insufficient balance
    error InsufficientBalance();

    /// @dev Thrown when withdrawal exceeds limit
    error WithdrawalLimitExceeded();

    /// @dev Thrown when deposit would exceed bank cap
    error BankCapExceeded();

    /// @dev Thrown when transfer fails
    error TransferFailed();

    /// @dev Thrown when token is not supported
    error TokenNotSupported();

    /// @dev Thrown when token is paused
    error TokenPaused();

    /// @dev Thrown when token is already supported
    error TokenAlreadySupported();

    /// @dev Thrown when address is zero
    error ZeroAddress();

    /// @dev Thrown when invalid decimals provided
    error InvalidDecimals();

    /// @dev Thrown when invalid price from oracle
    error InvalidPrice();

    /// @dev Thrown when stale price from oracle
    error StalePrice();

    /// @dev Thrown when invalid bank cap
    error InvalidBankCap();

    /// @dev Thrown when invalid withdrawal limit
    error InvalidWithdrawalLimit();

    // ========== FUNCTIONS ==========

    /**
     * @dev Deposit ETH into vault
     */
    function depositETH() external payable;

    /**
     * @dev Deposit ERC20 tokens into vault
     * @param token Address of the ERC20 token
     * @param amount Amount to deposit
     */
    function depositToken(address token, uint256 amount) external;

    /**
     * @dev Withdraw ETH from vault
     * @param amount Amount to withdraw in wei
     */
    function withdrawETH(uint256 amount) external;

    /**
     * @dev Withdraw ERC20 tokens from vault
     * @param token Address of the ERC20 token
     * @param amount Amount to withdraw
     */
    function withdrawToken(address token, uint256 amount) external;

    /**
     * @dev Get user's balance for a specific token
     * @param user Address of the user
     * @param token Address of the token (address(0) for ETH)
     * @return balance Balance in token's native decimals
     */
    function getBalance(address user, address token) external view returns (uint256 balance);

    /**
     * @dev Get user's balance in USD
     * @param user Address of the user
     * @param token Address of the token (address(0) for ETH)
     * @return balanceUSD Balance in USD (6 decimals)
     */
    function getBalanceInUSD(address user, address token) external view returns (uint256 balanceUSD);

    /**
     * @dev Get all user balances
     * @param user Address of the user
     * @return balances Array of UserBalance structs
     */
    function getAllBalances(address user) external view returns (UserBalance[] memory balances);

    /**
     * @dev Get token information
     * @param token Address of the token
     * @return info TokenInfo struct
     */
    function getTokenInfo(address token) external view returns (TokenInfo memory info);

    /**
     * @dev Get total bank value in USD
     * @return totalUSD Total value in USD (6 decimals)
     */
    function getTotalBankValueUSD() external view returns (uint256 totalUSD);
}
