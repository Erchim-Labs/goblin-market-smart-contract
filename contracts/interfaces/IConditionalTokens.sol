// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IConditionalTokens
 * @notice Interface for Polymarket's Conditional Token Framework (CTF)
 * @dev Based on Gnosis Conditional Token standard
 */
interface IConditionalTokens {
    /**
     * @notice Emitted when tokens are split
     */
    event PositionSplit(
        address indexed stakeholder,
        address collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint256[] partition,
        uint256 amount
    );

    /**
     * @notice Emitted when tokens are merged
     */
    event PositionsMerge(
        address indexed stakeholder,
        address collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint256[] partition,
        uint256 amount
    );

    /**
     * @notice Emitted when payout is redeemed
     */
    event PayoutRedemption(
        address indexed redeemer,
        address indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint256[] indexSets,
        uint256 payout
    );

    /**
     * @notice Split collateral into conditional tokens
     * @param collateralToken The collateral token (e.g., USDC)
     * @param parentCollectionId Parent collection (bytes32(0) for root)
     * @param conditionId The condition identifier
     * @param partition The partition of outcome slots
     * @param amount Amount of collateral to split
     */
    function splitPosition(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    /**
     * @notice Merge conditional tokens back to collateral
     * @param collateralToken The collateral token
     * @param parentCollectionId Parent collection
     * @param conditionId The condition identifier
     * @param partition The partition of outcome slots
     * @param amount Amount to merge
     */
    function mergePositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    /**
     * @notice Redeem positions after condition is resolved
     * @param collateralToken The collateral token
     * @param parentCollectionId Parent collection
     * @param conditionId The condition identifier
     * @param indexSets The index sets to redeem
     */
    function redeemPositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external;

    /**
     * @notice Get balance of a position token
     * @param account The account address
     * @param positionId The position token ID
     * @return Balance of the position
     */
    function balanceOf(address account, uint256 positionId) external view returns (uint256);

    /**
     * @notice Get the position ID for a collection and outcome
     * @param collateralToken The collateral token
     * @param collectionId The collection ID
     * @return Position ID
     */
    function getPositionId(
        address collateralToken,
        bytes32 collectionId
    ) external view returns (uint256);

    /**
     * @notice Get collection ID for a condition and index set
     * @param parentCollectionId Parent collection
     * @param conditionId The condition identifier
     * @param indexSet The index set
     * @return Collection ID
     */
    function getCollectionId(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256 indexSet
    ) external view returns (bytes32);

    /**
     * @notice Check if a condition is resolved
     * @param conditionId The condition identifier
     * @return True if resolved
     */
    function payoutDenominator(bytes32 conditionId) external view returns (uint256);

    /**
     * @notice Get payout numerator for an outcome
     * @param conditionId The condition identifier
     * @param outcomeIndex The outcome index
     * @return Payout numerator
     */
    function payoutNumerators(bytes32 conditionId, uint256 outcomeIndex) external view returns (uint256);

    /**
     * @notice Set approval for an operator
     * @param operator The operator address
     * @param approved Approval status
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @notice Check if operator is approved
     * @param account The account address
     * @param operator The operator address
     * @return True if approved
     */
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /**
     * @notice Safe transfer of position tokens
     * @param from From address
     * @param to To address
     * @param id Token ID
     * @param value Amount
     * @param data Additional data
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external;
}
