// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";

/**
 * @title MockConditionalTokens
 * @notice Mock Polymarket CTF for testing
 */
contract MockConditionalTokens is IConditionalTokens {
    using SafeERC20 for IERC20;

    // Mapping of condition ID => outcome index => resolution value
    mapping(bytes32 => mapping(uint256 => uint256)) public payouts;
    mapping(bytes32 => uint256) public denominators;

    // Position balances: positionId => account => balance
    mapping(uint256 => mapping(address => uint256)) private _balances;

    // Approvals: account => operator => approved
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * @notice Set condition resolution (for testing)
     */
    function setResolution(
        bytes32 conditionId,
        uint256[] calldata payoutNumeratorsArray
    ) external {
        uint256 total = 0;
        for (uint256 i = 0; i < payoutNumeratorsArray.length; i++) {
            payouts[conditionId][i] = payoutNumeratorsArray[i];
            total += payoutNumeratorsArray[i];
        }
        denominators[conditionId] = total;
    }

    function splitPosition(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external override {
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);

        // Mint outcome tokens to sender
        for (uint256 i = 0; i < partition.length; i++) {
            uint256 positionId = _getPositionId(collateralToken, conditionId, partition[i]);
            _balances[positionId][msg.sender] += amount;
        }

        emit PositionSplit(
            msg.sender,
            collateralToken,
            parentCollectionId,
            conditionId,
            partition,
            amount
        );
    }

    function mergePositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external override {
        // Burn outcome tokens
        for (uint256 i = 0; i < partition.length; i++) {
            uint256 positionId = _getPositionId(collateralToken, conditionId, partition[i]);
            require(_balances[positionId][msg.sender] >= amount, "Insufficient balance");
            _balances[positionId][msg.sender] -= amount;
        }

        // Return collateral
        IERC20(collateralToken).safeTransfer(msg.sender, amount);

        emit PositionsMerge(
            msg.sender,
            collateralToken,
            parentCollectionId,
            conditionId,
            partition,
            amount
        );
    }

    function redeemPositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external override {
        require(denominators[conditionId] > 0, "Not resolved");

        uint256 totalPayout = 0;

        for (uint256 i = 0; i < indexSets.length; i++) {
            uint256 positionId = _getPositionId(collateralToken, conditionId, indexSets[i]);
            uint256 balance = _balances[positionId][msg.sender];

            if (balance > 0) {
                // Calculate payout based on resolution
                uint256 outcomeIndex = indexSets[i] == 1 ? 0 : 1; // YES = 0, NO = 1
                uint256 payout = (balance * payouts[conditionId][outcomeIndex]) / denominators[conditionId];
                totalPayout += payout;

                _balances[positionId][msg.sender] = 0;
            }
        }

        if (totalPayout > 0) {
            IERC20(collateralToken).safeTransfer(msg.sender, totalPayout);
        }

        emit PayoutRedemption(
            msg.sender,
            collateralToken,
            parentCollectionId,
            conditionId,
            indexSets,
            totalPayout
        );
    }

    function balanceOf(address account, uint256 positionId) external view override returns (uint256) {
        return _balances[positionId][account];
    }

    function getPositionId(
        address collateralToken,
        bytes32 collectionId
    ) external pure override returns (uint256) {
        return uint256(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }

    function getCollectionId(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256 indexSet
    ) external pure override returns (bytes32) {
        return keccak256(abi.encodePacked(parentCollectionId, conditionId, indexSet));
    }

    function payoutDenominator(bytes32 conditionId) external view override returns (uint256) {
        return denominators[conditionId];
    }

    function payoutNumerators(bytes32 conditionId, uint256 outcomeIndex) external view override returns (uint256) {
        return payouts[conditionId][outcomeIndex];
    }

    function setApprovalForAll(address operator, bool approved) external override {
        _operatorApprovals[msg.sender][operator] = approved;
    }

    function isApprovedForAll(address account, address operator) external view override returns (bool) {
        return _operatorApprovals[account][operator];
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes calldata /* data */
    ) external override {
        require(
            from == msg.sender || _operatorApprovals[from][msg.sender],
            "Not authorized"
        );
        require(_balances[id][from] >= value, "Insufficient balance");

        _balances[id][from] -= value;
        _balances[id][to] += value;
    }

    function _getPositionId(
        address collateralToken,
        bytes32 conditionId,
        uint256 indexSet
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(collateralToken, conditionId, indexSet)));
    }

    /**
     * @notice Mint tokens directly for testing
     */
    function mintTokens(
        address to,
        address collateralToken,
        bytes32 conditionId,
        uint256 indexSet,
        uint256 amount
    ) external {
        uint256 positionId = _getPositionId(collateralToken, conditionId, indexSet);
        _balances[positionId][to] += amount;
    }
}
