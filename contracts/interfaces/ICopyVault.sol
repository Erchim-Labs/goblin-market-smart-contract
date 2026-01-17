// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title ICopyVault
 * @notice Interface for the CopyVault contract
 */
interface ICopyVault is IERC4626 {
    /// @notice Emitted when USDC is allocated for a trade
    event TradeAllocated(uint256 amount);

    /// @notice Emitted when USDC is returned from a closed position
    event PositionReturned(uint256 amount);

    /// @notice Emitted when a leader is added
    event LeaderAdded(address indexed leader);

    /// @notice Emitted when a leader is removed
    event LeaderRemoved(address indexed leader);

    /// @notice Emitted when vault parameters are updated
    event ParametersUpdated(
        uint256 maxTotalDeposits,
        uint256 maxDepositPerUser,
        uint256 minDeposit
    );

    /**
     * @notice Allocate USDC for a trade
     * @param amount USDC amount to allocate
     */
    function allocateForTrade(uint256 amount) external;

    /**
     * @notice Return USDC from closed position
     * @param amount USDC amount returned
     */
    function returnFromPosition(uint256 amount) external;

    /**
     * @notice Get total idle assets (not in positions)
     * @return Total idle USDC
     */
    function totalIdleAssets() external view returns (uint256);

    /**
     * @notice Check if an address is an approved leader
     * @param leader Address to check
     * @return True if approved leader
     */
    function isApprovedLeader(address leader) external view returns (bool);

    /**
     * @notice Get user's total deposits
     * @param user User address
     * @return Total deposited amount
     */
    function userDeposits(address user) external view returns (uint256);
}
