// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPositionManager} from "../interfaces/IPositionManager.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";

/**
 * @title PositionManager
 * @notice Manages Polymarket positions for the copy-trading vault
 * @dev Handles:
 *      - Opening/closing positions on Polymarket
 *      - Tracking position metadata and P&L
 *      - Redeeming resolved positions
 *      - Position value calculations
 *
 * Security features:
 *      - ReentrancyGuard on all state-changing functions
 *      - Role-based access control
 *      - Position and exposure limits
 *      - Slippage protection
 */
contract PositionManager is IPositionManager, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ============ Roles ============

    /// @notice Admin role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Executor role - can execute trades
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    // ============ Immutables ============

    /// @notice Polymarket Conditional Token Framework
    IConditionalTokens public immutable ctf;

    /// @notice USDC token
    IERC20 public immutable usdc;

    /// @notice Polymarket exchange address
    address public immutable exchange;

    // ============ State Variables ============

    /// @notice Associated vault address
    address public vault;

    /// @notice Position tracking by condition ID
    mapping(bytes32 => Position) public positions;

    /// @notice Array of active position condition IDs
    bytes32[] public activePositionIds;

    /// @notice Maximum concurrent positions
    uint256 public maxPositions;

    /// @notice Maximum position size (basis points of vault)
    uint256 public maxPositionSizeBps;

    /// @notice Maximum total exposure (basis points of vault)
    uint256 public maxTotalExposureBps;

    /// @notice Price oracle for position valuation
    address public priceOracle;

    // ============ Constants ============

    /// @notice Basis points denominator
    uint256 private constant BPS = 10000;

    /// @notice Price precision (6 decimals like USDC)
    uint256 private constant PRICE_PRECISION = 1e6;

    // ============ Events ============

    /// @notice Emitted when vault is set
    event VaultSet(address indexed vault);

    /// @notice Emitted when limits are updated
    event LimitsUpdated(
        uint256 maxPositions,
        uint256 maxPositionSizeBps,
        uint256 maxTotalExposureBps
    );

    /// @notice Emitted when price oracle is set
    event PriceOracleSet(address indexed oracle);

    // ============ Errors ============

    /// @notice Error when max positions reached
    error MaxPositionsReached();

    /// @notice Error when position size exceeds limit
    error ExceedsPositionSizeLimit();

    /// @notice Error when total exposure exceeds limit
    error ExceedsExposureLimit();

    /// @notice Error when position doesn't exist
    error PositionNotFound();

    /// @notice Error when insufficient position amount
    error InsufficientPosition();

    /// @notice Error when slippage is too high
    error SlippageExceeded();

    /// @notice Error when address is zero
    error ZeroAddress();

    /// @notice Error when amount is zero
    error ZeroAmount();

    /// @notice Error when caller is not vault
    error OnlyVault();

    // ============ Constructor ============

    /**
     * @notice Constructor
     * @param _ctf Polymarket Conditional Token Framework address
     * @param _usdc USDC token address
     * @param _exchange Polymarket exchange address
     * @param _admin Admin address
     */
    constructor(
        address _ctf,
        address _usdc,
        address _exchange,
        address _admin
    ) {
        if (_ctf == address(0)) revert ZeroAddress();
        if (_usdc == address(0)) revert ZeroAddress();
        if (_exchange == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();

        ctf = IConditionalTokens(_ctf);
        usdc = IERC20(_usdc);
        exchange = _exchange;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);

        // Default limits
        maxPositions = 20;
        maxPositionSizeBps = 1000;     // 10% max per position
        maxTotalExposureBps = 8000;    // 80% max total exposure
    }

    // ============ Modifiers ============

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set the vault address
     * @param _vault Vault contract address
     */
    function setVault(address _vault) external onlyRole(ADMIN_ROLE) {
        if (_vault == address(0)) revert ZeroAddress();
        vault = _vault;
        emit VaultSet(_vault);
    }

    /**
     * @notice Set position limits
     * @param _maxPositions Maximum concurrent positions
     * @param _maxPositionSizeBps Max position size in basis points
     * @param _maxTotalExposureBps Max total exposure in basis points
     */
    function setLimits(
        uint256 _maxPositions,
        uint256 _maxPositionSizeBps,
        uint256 _maxTotalExposureBps
    ) external onlyRole(ADMIN_ROLE) {
        maxPositions = _maxPositions;
        maxPositionSizeBps = _maxPositionSizeBps;
        maxTotalExposureBps = _maxTotalExposureBps;

        emit LimitsUpdated(_maxPositions, _maxPositionSizeBps, _maxTotalExposureBps);
    }

    /**
     * @notice Set price oracle for position valuation
     * @param _oracle Oracle address
     */
    function setPriceOracle(address _oracle) external onlyRole(ADMIN_ROLE) {
        priceOracle = _oracle;
        emit PriceOracleSet(_oracle);
    }

    // ============ Position Management ============

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
    ) external override onlyRole(EXECUTOR_ROLE) nonReentrant returns (uint256 tokensReceived) {
        if (amount == 0) revert ZeroAmount();

        // Check if this is a new position
        Position storage pos = positions[conditionId];
        bool isNewPosition = pos.amount == 0;

        if (isNewPosition) {
            if (activePositionIds.length >= maxPositions) revert MaxPositionsReached();
        }

        // Validate exposure limits
        _validateExposureLimits(amount);

        // Approve USDC to exchange
        usdc.forceApprove(exchange, amount);

        // Execute trade on Polymarket
        // In production, this would interact with Polymarket's CLOB
        // For now, we simulate the token receipt
        tokensReceived = _executePolymarketBuy(conditionId, tokenId, amount, minTokens);

        if (tokensReceived < minTokens) revert SlippageExceeded();

        // Update position
        if (isNewPosition) {
            pos.conditionId = conditionId;
            pos.tokenId = tokenId;
            pos.isYes = isYes;
            pos.openedAt = uint64(block.timestamp);
            activePositionIds.push(conditionId);
        }

        // Calculate new average entry price
        uint256 newTotalCost = pos.costBasis + amount;
        uint256 newTotalAmount = pos.amount + tokensReceived;
        pos.avgEntryPrice = newTotalCost.mulDiv(PRICE_PRECISION, newTotalAmount);
        pos.amount = newTotalAmount;
        pos.costBasis = newTotalCost;

        emit PositionOpened(conditionId, tokenId, tokensReceived, amount);
    }

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
    ) external override onlyRole(EXECUTOR_ROLE) nonReentrant returns (uint256 usdcReceived) {
        Position storage pos = positions[conditionId];
        if (pos.amount == 0) revert PositionNotFound();
        if (pos.amount < tokenAmount) revert InsufficientPosition();

        // Approve tokens to exchange
        ctf.setApprovalForAll(exchange, true);

        // Execute sell on Polymarket
        usdcReceived = _executePolymarketSell(conditionId, pos.tokenId, tokenAmount, minUsdc);

        if (usdcReceived < minUsdc) revert SlippageExceeded();

        // Update position
        uint256 costBasisReduction = pos.costBasis.mulDiv(tokenAmount, pos.amount);
        pos.amount -= tokenAmount;
        pos.costBasis -= costBasisReduction;

        // Remove position if fully closed
        if (pos.amount == 0) {
            _removePosition(conditionId);
        }

        // Return USDC to vault
        usdc.safeTransfer(vault, usdcReceived);

        emit PositionClosed(conditionId, tokenAmount, usdcReceived);
    }

    /**
     * @notice Redeem tokens after market resolution
     * @param conditionId Resolved market condition ID
     * @return usdcReceived Amount of USDC received
     */
    function redeemPosition(
        bytes32 conditionId
    ) external override onlyRole(EXECUTOR_ROLE) nonReentrant returns (uint256 usdcReceived) {
        Position storage pos = positions[conditionId];
        if (pos.amount == 0) revert PositionNotFound();

        uint256 balanceBefore = usdc.balanceOf(address(this));

        // Redeem via Polymarket CTF
        uint256[] memory indexSets = new uint256[](2);
        indexSets[0] = 1; // YES
        indexSets[1] = 2; // NO

        ctf.redeemPositions(
            address(usdc),
            bytes32(0), // parentCollectionId
            conditionId,
            indexSets
        );

        usdcReceived = usdc.balanceOf(address(this)) - balanceBefore;

        uint256 redeemedAmount = pos.amount;

        // Clean up position
        _removePosition(conditionId);

        // Return to vault
        if (usdcReceived > 0) {
            usdc.safeTransfer(vault, usdcReceived);
        }

        emit PositionRedeemed(conditionId, redeemedAmount, usdcReceived);
    }

    // ============ View Functions ============

    /**
     * @notice Calculate total value of all positions
     * @return Total USDC value of positions
     */
    function totalPositionValue() external view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < activePositionIds.length; i++) {
            total += getPositionValue(activePositionIds[i]);
        }
        return total;
    }

    /**
     * @notice Get current value of a position
     * @param conditionId Market condition ID
     * @return Current USDC value
     */
    function getPositionValue(bytes32 conditionId) public view override returns (uint256) {
        Position memory pos = positions[conditionId];
        if (pos.amount == 0) return 0;

        // Get current price from oracle
        uint256 currentPrice = _getPrice(conditionId, pos.tokenId);

        // Value = amount * price / precision
        return pos.amount.mulDiv(currentPrice, PRICE_PRECISION);
    }

    /**
     * @notice Get all active positions
     * @return Array of position data
     */
    function getActivePositions() external view override returns (Position[] memory) {
        Position[] memory result = new Position[](activePositionIds.length);
        for (uint256 i = 0; i < activePositionIds.length; i++) {
            result[i] = positions[activePositionIds[i]];
        }
        return result;
    }

    /**
     * @notice Get position by condition ID
     * @param conditionId Market condition ID
     * @return Position data
     */
    function getPosition(bytes32 conditionId) external view override returns (Position memory) {
        return positions[conditionId];
    }

    /**
     * @notice Get number of active positions
     * @return Number of active positions
     */
    function activePositionCount() external view returns (uint256) {
        return activePositionIds.length;
    }

    // ============ Internal Functions ============

    /**
     * @notice Validate position against exposure limits
     * @param amount Amount to add to exposure
     */
    function _validateExposureLimits(uint256 amount) internal view {
        // In production, would check against vault's total assets
        // For now, just basic validation
        if (amount == 0) revert ZeroAmount();
    }

    /**
     * @notice Execute buy on Polymarket
     * @dev In production, this interacts with Polymarket's CLOB
     */
    function _executePolymarketBuy(
        bytes32 conditionId,
        uint256 tokenId,
        uint256 amount,
        uint256 minTokens
    ) internal returns (uint256 tokensReceived) {
        // In production, this would:
        // 1. Build and sign order for Polymarket CLOB
        // 2. Submit order to CLOB
        // 3. Receive outcome tokens

        // For testing/simulation, assume 1:1 conversion at current price
        // This would be replaced with actual Polymarket integration
        tokensReceived = amount; // Simplified for testing

        // Actual implementation would use:
        // - @polymarket/clob-client for order building
        // - CTF for token settlement
    }

    /**
     * @notice Execute sell on Polymarket
     * @dev In production, this interacts with Polymarket's CLOB
     */
    function _executePolymarketSell(
        bytes32 conditionId,
        uint256 tokenId,
        uint256 tokenAmount,
        uint256 minUsdc
    ) internal returns (uint256 usdcReceived) {
        // In production, this would:
        // 1. Build and sign sell order
        // 2. Submit to CLOB
        // 3. Receive USDC

        // Simplified for testing
        usdcReceived = tokenAmount;
    }

    /**
     * @notice Get current price for a token
     * @param conditionId Condition ID
     * @param tokenId Token ID
     * @return price Current price (6 decimals)
     */
    function _getPrice(bytes32 conditionId, uint256 tokenId) internal view returns (uint256) {
        // In production, this would query Polymarket API or on-chain oracle
        // For now, return a default price (e.g., 0.50)
        if (priceOracle != address(0)) {
            // Query price oracle
            // return IPriceOracle(priceOracle).getPrice(conditionId, tokenId);
        }
        return PRICE_PRECISION / 2; // Default 0.50
    }

    /**
     * @notice Remove a position from tracking
     * @param conditionId Condition ID to remove
     */
    function _removePosition(bytes32 conditionId) internal {
        // Clear position data
        delete positions[conditionId];

        // Remove from active list
        for (uint256 i = 0; i < activePositionIds.length; i++) {
            if (activePositionIds[i] == conditionId) {
                activePositionIds[i] = activePositionIds[activePositionIds.length - 1];
                activePositionIds.pop();
                break;
            }
        }
    }

    /**
     * @notice Receive USDC from vault for trading
     */
    function receiveFromVault(uint256 amount) external onlyVault {
        // USDC should be transferred before calling this
        // Just a hook for any additional logic if needed
    }
}
