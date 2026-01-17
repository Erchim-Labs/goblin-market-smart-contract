// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPositionManager
 * @notice Interface for the PositionManager contract that manages Polymarket positions
 */
interface IPositionManager {
    /// @notice Position data structure
    struct Position {
        bytes32 conditionId;      // Polymarket market identifier
        uint256 tokenId;          // YES or NO token ID
        uint256 amount;           // Number of tokens held
        uint256 avgEntryPrice;    // Average entry price (6 decimals)
        uint256 costBasis;        // Total USDC spent
        uint64 openedAt;          // Timestamp when opened
        bool isYes;               // true = YES token, false = NO
    }

    /// @notice Emitted when a position is opened
    event PositionOpened(
        bytes32 indexed conditionId,
        uint256 indexed tokenId,
        uint256 tokensReceived,
        uint256 usdcSpent
    );

    /// @notice Emitted when a position is closed
    event PositionClosed(
        bytes32 indexed conditionId,
        uint256 tokensSold,
        uint256 usdcReceived
    );

    /// @notice Emitted when a position is redeemed after market resolution
    event PositionRedeemed(
        bytes32 indexed conditionId,
        uint256 tokensRedeemed,
        uint256 usdcReceived
    );

    /**
     * @notice Open or add to a position
     * @param conditionId Polymarket market condition ID
     * @param tokenId Token ID (YES or NO)
     * @param amount USDC amount to spend
     * @param minTokens Minimum tokens to receive (slippage protection)
     * @param isYes Whether this is a YES or NO position
     * @return tokensReceived Number of tokens received
     */
    function openPosition(
        bytes32 conditionId,
        uint256 tokenId,
        uint256 amount,
        uint256 minTokens,
        bool isYes
    ) external returns (uint256 tokensReceived);

    /**
     * @notice Close or reduce a position
     * @param conditionId Market condition ID
     * @param tokenAmount Tokens to sell
     * @param minUsdc Minimum USDC to receive
     * @return usdcReceived Amount of USDC received
     */
    function closePosition(
        bytes32 conditionId,
        uint256 tokenAmount,
        uint256 minUsdc
    ) external returns (uint256 usdcReceived);

    /**
     * @notice Redeem tokens after market resolution
     * @param conditionId Resolved market condition ID
     * @return usdcReceived Amount of USDC received
     */
    function redeemPosition(bytes32 conditionId) external returns (uint256 usdcReceived);

    /**
     * @notice Calculate total value of all positions
     * @return Total USDC value of positions
     */
    function totalPositionValue() external view returns (uint256);

    /**
     * @notice Get current value of a position
     * @param conditionId Market condition ID
     * @return Current USDC value
     */
    function getPositionValue(bytes32 conditionId) external view returns (uint256);

    /**
     * @notice Get all active positions
     * @return Array of position data
     */
    function getActivePositions() external view returns (Position[] memory);

    /**
     * @notice Get position by condition ID
     * @param conditionId Market condition ID
     * @return Position data
     */
    function getPosition(bytes32 conditionId) external view returns (Position memory);
}
