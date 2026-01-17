// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPositionManager} from "../interfaces/IPositionManager.sol";

/**
 * @title CopyVault
 * @notice ERC-4626 compliant vault for copy-trading on Polymarket
 * @dev Main entry point for users. Implements:
 *      - Deposit/withdraw functionality
 *      - Share accounting with inflation attack protection
 *      - Role-based access control
 *      - Emergency pause capability (withdrawals always allowed)
 *      - Leader management
 *
 * Security features:
 *      - ReentrancyGuard on all state-changing functions
 *      - Pausable for emergency situations
 *      - Virtual shares offset to prevent inflation attacks
 *      - Per-user and total deposit caps
 *      - Withdrawals always work even when paused
 */
contract CopyVault is ERC4626, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ============ Roles ============

    /// @notice Admin role - can update parameters, manage leaders
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Executor role - can allocate funds for trades
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /// @notice Guardian role - can pause the vault
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    /// @notice Strategist role - can manage leaders
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    // ============ State Variables ============

    /// @notice Position manager contract
    IPositionManager public positionManager;

    /// @notice Maximum total deposits allowed in the vault
    uint256 public maxTotalDeposits;

    /// @notice Maximum deposit per user
    uint256 public maxDepositPerUser;

    /// @notice Minimum deposit amount
    uint256 public minDeposit;

    /// @notice Total idle assets (USDC not in positions)
    uint256 public totalIdleAssets;

    /// @notice Track deposits per user for cap enforcement
    mapping(address => uint256) public userDeposits;

    /// @notice Approved leaders for copy trading
    mapping(address => bool) public approvedLeaders;

    /// @notice List of approved leader addresses
    address[] public leaderList;

    /// @notice Performance fee in basis points (e.g., 1000 = 10%)
    uint256 public performanceFee;

    /// @notice Management fee in basis points (annual)
    uint256 public managementFee;

    /// @notice Fee recipient address
    address public feeRecipient;

    /// @notice High water mark for performance fee calculation
    uint256 public highWaterMark;

    /// @notice Last fee collection timestamp
    uint256 public lastFeeCollection;

    /// @notice Maximum trade size as percentage of vault (basis points)
    uint256 public maxTradeSizeBps;

    // ============ Constants ============

    /// @notice Basis points denominator
    uint256 private constant BPS = 10000;

    /// @notice Decimals offset for virtual shares (prevents inflation attack)
    uint8 private constant DECIMALS_OFFSET = 3;

    // ============ Events ============

    /// @notice Emitted when funds are allocated for a trade
    event TradeAllocated(uint256 amount);

    /// @notice Emitted when funds return from a position
    event PositionReturned(uint256 amount);

    /// @notice Emitted when a leader is added
    event LeaderAdded(address indexed leader);

    /// @notice Emitted when a leader is removed
    event LeaderRemoved(address indexed leader);

    /// @notice Emitted when parameters are updated
    event ParametersUpdated(
        uint256 maxTotalDeposits,
        uint256 maxDepositPerUser,
        uint256 minDeposit
    );

    /// @notice Emitted when position manager is set
    event PositionManagerSet(address indexed positionManager);

    /// @notice Emitted when fees are collected
    event FeesCollected(uint256 performanceFeeAmount, uint256 managementFeeAmount);

    /// @notice Emitted when fee parameters are updated
    event FeeParametersUpdated(
        uint256 performanceFee,
        uint256 managementFee,
        address feeRecipient
    );

    // ============ Errors ============

    /// @notice Error when deposit is below minimum
    error BelowMinimumDeposit();

    /// @notice Error when deposit exceeds vault cap
    error ExceedsVaultCap();

    /// @notice Error when deposit exceeds user cap
    error ExceedsUserCap();

    /// @notice Error when withdrawal amount exceeds available liquidity
    error InsufficientLiquidity();

    /// @notice Error when trade size exceeds maximum
    error ExceedsMaxTradeSize();

    /// @notice Error when insufficient idle assets
    error InsufficientIdleAssets();

    /// @notice Error when leader is already approved
    error LeaderAlreadyApproved();

    /// @notice Error when leader is not approved
    error LeaderNotApproved();

    /// @notice Error when fee exceeds maximum
    error FeeExceedsMaximum();

    /// @notice Error when address is zero
    error ZeroAddress();

    /// @notice Error when amount is zero
    error ZeroAmount();

    // ============ Constructor ============

    /**
     * @notice Constructor
     * @param _asset Underlying asset (USDC)
     * @param _name Vault share token name
     * @param _symbol Vault share token symbol
     * @param _admin Admin address
     */
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _admin
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        if (_admin == address(0)) revert ZeroAddress();
        if (address(_asset) == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);

        // Set default parameters
        maxTotalDeposits = 10_000_000 * 1e6; // $10M (USDC has 6 decimals)
        maxDepositPerUser = 100_000 * 1e6;   // $100k
        minDeposit = 10 * 1e6;               // $10
        maxTradeSizeBps = 500;               // 5% max trade size

        // Set default fees
        performanceFee = 1000;  // 10%
        managementFee = 200;    // 2% annual
        feeRecipient = _admin;

        lastFeeCollection = block.timestamp;
    }

    // ============ User Functions ============

    /**
     * @notice Deposit assets and receive vault shares
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override nonReentrant whenNotPaused returns (uint256 shares) {
        if (assets < minDeposit) revert BelowMinimumDeposit();
        if (totalAssets() + assets > maxTotalDeposits) revert ExceedsVaultCap();
        if (userDeposits[receiver] + assets > maxDepositPerUser) revert ExceedsUserCap();

        shares = previewDeposit(assets);
        if (shares == 0) revert ZeroAmount();

        // Update state before external calls (CEI pattern)
        userDeposits[receiver] += assets;
        totalIdleAssets += assets;

        // Transfer assets from sender
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);

        // Mint shares to receiver
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Withdraw assets by burning shares
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive assets
     * @param owner Owner of the shares
     * @return shares Amount of shares burned
     * @dev Withdrawals are always allowed, even when paused
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();

        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Check liquidity
        if (assets > totalIdleAssets) revert InsufficientLiquidity();

        // Update state before external calls (CEI pattern)
        uint256 userDep = userDeposits[owner];
        userDeposits[owner] = userDep > assets ? userDep - assets : 0;
        totalIdleAssets -= assets;

        // Burn shares from owner
        _burn(owner, shares);

        // Transfer assets to receiver
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Redeem shares for assets
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets
     * @param owner Owner of the shares
     * @return assets Amount of assets received
     * @dev Redemptions are always allowed, even when paused
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        assets = previewRedeem(shares);
        if (assets == 0) revert ZeroAmount();

        // Check liquidity
        if (assets > totalIdleAssets) revert InsufficientLiquidity();

        // Update state before external calls (CEI pattern)
        uint256 userDep = userDeposits[owner];
        userDeposits[owner] = userDep > assets ? userDep - assets : 0;
        totalIdleAssets -= assets;

        // Burn shares from owner
        _burn(owner, shares);

        // Transfer assets to receiver
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    // ============ View Functions ============

    /**
     * @notice Get total assets under management
     * @return Total USDC value (idle + positions)
     */
    function totalAssets() public view virtual override returns (uint256) {
        if (address(positionManager) == address(0)) {
            return totalIdleAssets;
        }
        return totalIdleAssets + positionManager.totalPositionValue();
    }

    /**
     * @notice Check maximum deposit for a receiver
     * @param receiver Address to check
     * @return Maximum deposit amount
     */
    function maxDeposit(address receiver) public view virtual override returns (uint256) {
        if (paused()) return 0;

        uint256 userCap = maxDepositPerUser - userDeposits[receiver];
        uint256 vaultCap = maxTotalDeposits - totalAssets();

        return userCap < vaultCap ? userCap : vaultCap;
    }

    /**
     * @notice Check maximum mint for a receiver
     * @param receiver Address to check
     * @return Maximum shares that can be minted
     */
    function maxMint(address receiver) public view virtual override returns (uint256) {
        return previewDeposit(maxDeposit(receiver));
    }

    /**
     * @notice Check maximum withdrawal for an owner
     * @param owner Address to check
     * @return Maximum withdrawal amount (limited by liquidity)
     */
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        uint256 ownerAssets = previewRedeem(balanceOf(owner));
        return ownerAssets < totalIdleAssets ? ownerAssets : totalIdleAssets;
    }

    /**
     * @notice Check maximum redemption for an owner
     * @param owner Address to check
     * @return Maximum shares that can be redeemed
     */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        uint256 ownerShares = balanceOf(owner);
        uint256 maxAssets = totalIdleAssets;
        uint256 maxSharesFromLiquidity = previewWithdraw(maxAssets);

        return ownerShares < maxSharesFromLiquidity ? ownerShares : maxSharesFromLiquidity;
    }

    /**
     * @notice Get list of approved leaders
     * @return Array of approved leader addresses
     */
    function getLeaders() external view returns (address[] memory) {
        return leaderList;
    }

    /**
     * @notice Check if an address is an approved leader
     * @param leader Address to check
     * @return True if approved
     */
    function isApprovedLeader(address leader) external view returns (bool) {
        return approvedLeaders[leader];
    }

    // ============ Executor Functions ============

    /**
     * @notice Allocate USDC for a trade
     * @param amount USDC amount to allocate
     * @dev Only callable by executor role
     */
    function allocateForTrade(
        uint256 amount
    ) external onlyRole(EXECUTOR_ROLE) whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (amount > totalIdleAssets) revert InsufficientIdleAssets();
        if (amount > _maxTradeSize()) revert ExceedsMaxTradeSize();

        totalIdleAssets -= amount;

        SafeERC20.safeTransfer(IERC20(asset()), address(positionManager), amount);

        emit TradeAllocated(amount);
    }

    /**
     * @notice Return USDC from closed position
     * @param amount USDC amount returned
     * @dev Only callable by executor role
     */
    function returnFromPosition(
        uint256 amount
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant {
        totalIdleAssets += amount;
        emit PositionReturned(amount);
    }

    // ============ Admin Functions ============

    /**
     * @notice Set the position manager contract
     * @param _positionManager Position manager address
     */
    function setPositionManager(
        address _positionManager
    ) external onlyRole(ADMIN_ROLE) {
        if (_positionManager == address(0)) revert ZeroAddress();
        positionManager = IPositionManager(_positionManager);
        emit PositionManagerSet(_positionManager);
    }

    /**
     * @notice Update vault parameters
     * @param _maxTotalDeposits New max total deposits
     * @param _maxDepositPerUser New max deposit per user
     * @param _minDeposit New minimum deposit
     */
    function setParameters(
        uint256 _maxTotalDeposits,
        uint256 _maxDepositPerUser,
        uint256 _minDeposit
    ) external onlyRole(ADMIN_ROLE) {
        maxTotalDeposits = _maxTotalDeposits;
        maxDepositPerUser = _maxDepositPerUser;
        minDeposit = _minDeposit;

        emit ParametersUpdated(_maxTotalDeposits, _maxDepositPerUser, _minDeposit);
    }

    /**
     * @notice Set max trade size in basis points
     * @param _maxTradeSizeBps Max trade size (e.g., 500 = 5%)
     */
    function setMaxTradeSizeBps(
        uint256 _maxTradeSizeBps
    ) external onlyRole(ADMIN_ROLE) {
        if (_maxTradeSizeBps > BPS) revert FeeExceedsMaximum();
        maxTradeSizeBps = _maxTradeSizeBps;
    }

    /**
     * @notice Set fee parameters
     * @param _performanceFee Performance fee in basis points
     * @param _managementFee Management fee in basis points
     * @param _feeRecipient Fee recipient address
     */
    function setFeeParameters(
        uint256 _performanceFee,
        uint256 _managementFee,
        address _feeRecipient
    ) external onlyRole(ADMIN_ROLE) {
        if (_performanceFee > 3000) revert FeeExceedsMaximum(); // Max 30%
        if (_managementFee > 500) revert FeeExceedsMaximum();   // Max 5%
        if (_feeRecipient == address(0)) revert ZeroAddress();

        performanceFee = _performanceFee;
        managementFee = _managementFee;
        feeRecipient = _feeRecipient;

        emit FeeParametersUpdated(_performanceFee, _managementFee, _feeRecipient);
    }

    // ============ Leader Management ============

    /**
     * @notice Add an approved leader
     * @param leader Leader address to add
     */
    function addLeader(address leader) external onlyRole(STRATEGIST_ROLE) {
        if (leader == address(0)) revert ZeroAddress();
        if (approvedLeaders[leader]) revert LeaderAlreadyApproved();

        approvedLeaders[leader] = true;
        leaderList.push(leader);

        emit LeaderAdded(leader);
    }

    /**
     * @notice Remove an approved leader
     * @param leader Leader address to remove
     */
    function removeLeader(address leader) external onlyRole(STRATEGIST_ROLE) {
        if (!approvedLeaders[leader]) revert LeaderNotApproved();

        approvedLeaders[leader] = false;

        // Remove from list
        for (uint256 i = 0; i < leaderList.length; i++) {
            if (leaderList[i] == leader) {
                leaderList[i] = leaderList[leaderList.length - 1];
                leaderList.pop();
                break;
            }
        }

        emit LeaderRemoved(leader);
    }

    // ============ Emergency Functions ============

    /**
     * @notice Pause the vault (deposits and trades)
     * @dev Withdrawals remain enabled
     */
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the vault
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ============ Internal Functions ============

    /**
     * @notice Calculate maximum trade size
     * @return Maximum trade size in asset units
     */
    function _maxTradeSize() internal view returns (uint256) {
        return totalAssets().mulDiv(maxTradeSizeBps, BPS);
    }

    /**
     * @notice Decimals offset for virtual shares
     * @return Offset value (3 = 1000 virtual shares)
     * @dev This prevents the first depositor inflation attack
     */
    function _decimalsOffset() internal pure virtual override returns (uint8) {
        return DECIMALS_OFFSET;
    }
}
