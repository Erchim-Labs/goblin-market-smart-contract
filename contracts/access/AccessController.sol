// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/**
 * @title AccessController
 * @notice Role-based access control for the Goblin Market copy-trading system
 * @dev Implements a hierarchical role system with:
 *      - ADMIN_ROLE: Full control, requires multisig
 *      - EXECUTOR_ROLE: Can execute trades on behalf of the vault
 *      - GUARDIAN_ROLE: Can pause the system in emergencies
 *      - STRATEGIST_ROLE: Can manage leaders
 */
contract AccessController is AccessControlEnumerable {
    /// @notice Role for admin operations (should be multisig)
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Role for executing trades
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /// @notice Role for emergency pause operations
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    /// @notice Role for managing trading strategies and leaders
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    /// @notice Address of the timelock contract for delayed admin actions
    address public timelock;

    /// @notice Emitted when timelock is updated
    event TimelockUpdated(address indexed oldTimelock, address indexed newTimelock);

    /// @notice Error when caller is not the timelock
    error OnlyTimelock();

    /// @notice Error when address is zero
    error ZeroAddress();

    /**
     * @notice Constructor
     * @param _admin Initial admin address (should be multisig)
     * @param _timelock Timelock contract address
     */
    constructor(address _admin, address _timelock) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_timelock == address(0)) revert ZeroAddress();

        // Set up role hierarchy
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);

        // Admin can grant all roles
        _setRoleAdmin(EXECUTOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(GUARDIAN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(STRATEGIST_ROLE, ADMIN_ROLE);

        timelock = _timelock;
    }

    /**
     * @notice Modifier for functions that must go through timelock
     */
    modifier onlyTimelock() {
        if (msg.sender != timelock) revert OnlyTimelock();
        _;
    }

    /**
     * @notice Update the timelock address
     * @param _newTimelock New timelock address
     * @dev Must be called through the existing timelock
     */
    function setTimelock(address _newTimelock) external onlyTimelock {
        if (_newTimelock == address(0)) revert ZeroAddress();

        address oldTimelock = timelock;
        timelock = _newTimelock;

        emit TimelockUpdated(oldTimelock, _newTimelock);
    }

    /**
     * @notice Grant executor role (requires timelock for security)
     * @param account Account to grant role to
     */
    function grantExecutorRole(address account) external onlyTimelock {
        _grantRole(EXECUTOR_ROLE, account);
    }

    /**
     * @notice Revoke executor role (immediate for security)
     * @param account Account to revoke role from
     */
    function revokeExecutorRole(address account) external onlyRole(ADMIN_ROLE) {
        _revokeRole(EXECUTOR_ROLE, account);
    }

    /**
     * @notice Grant guardian role
     * @param account Account to grant role to
     */
    function grantGuardianRole(address account) external onlyRole(ADMIN_ROLE) {
        _grantRole(GUARDIAN_ROLE, account);
    }

    /**
     * @notice Revoke guardian role
     * @param account Account to revoke role from
     */
    function revokeGuardianRole(address account) external onlyRole(ADMIN_ROLE) {
        _revokeRole(GUARDIAN_ROLE, account);
    }

    /**
     * @notice Grant strategist role
     * @param account Account to grant role to
     */
    function grantStrategistRole(address account) external onlyRole(ADMIN_ROLE) {
        _grantRole(STRATEGIST_ROLE, account);
    }

    /**
     * @notice Revoke strategist role
     * @param account Account to revoke role from
     */
    function revokeStrategistRole(address account) external onlyRole(ADMIN_ROLE) {
        _revokeRole(STRATEGIST_ROLE, account);
    }

    /**
     * @notice Check if an account has the executor role
     * @param account Account to check
     * @return True if account has executor role
     */
    function isExecutor(address account) external view returns (bool) {
        return hasRole(EXECUTOR_ROLE, account);
    }

    /**
     * @notice Check if an account has the guardian role
     * @param account Account to check
     * @return True if account has guardian role
     */
    function isGuardian(address account) external view returns (bool) {
        return hasRole(GUARDIAN_ROLE, account);
    }

    /**
     * @notice Check if an account has the admin role
     * @param account Account to check
     * @return True if account has admin role
     */
    function isAdmin(address account) external view returns (bool) {
        return hasRole(ADMIN_ROLE, account);
    }

    /**
     * @notice Check if an account has the strategist role
     * @param account Account to check
     * @return True if account has strategist role
     */
    function isStrategist(address account) external view returns (bool) {
        return hasRole(STRATEGIST_ROLE, account);
    }
}
