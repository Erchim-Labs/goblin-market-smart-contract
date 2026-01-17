// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Timelock
 * @notice Time-delayed execution of admin operations for security
 * @dev Implements a timelock mechanism that requires a waiting period
 *      before sensitive operations can be executed. This gives users
 *      time to exit if they disagree with proposed changes.
 */
contract Timelock is AccessControl {
    /// @notice Minimum delay for queued transactions (48 hours)
    uint256 public constant MINIMUM_DELAY = 48 hours;

    /// @notice Maximum delay for queued transactions (30 days)
    uint256 public constant MAXIMUM_DELAY = 30 days;

    /// @notice Grace period after ETA before transaction expires (14 days)
    uint256 public constant GRACE_PERIOD = 14 days;

    /// @notice Role for proposing transactions
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    /// @notice Role for executing transactions
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /// @notice Role for cancelling transactions
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    /// @notice Current delay for transactions
    uint256 public delay;

    /// @notice Mapping of transaction hash to queued status
    mapping(bytes32 => bool) public queuedTransactions;

    /// @notice Emitted when a transaction is queued
    event TransactionQueued(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        bytes data,
        uint256 eta
    );

    /// @notice Emitted when a transaction is executed
    event TransactionExecuted(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        bytes data
    );

    /// @notice Emitted when a transaction is cancelled
    event TransactionCancelled(bytes32 indexed txHash);

    /// @notice Emitted when the delay is updated
    event DelayUpdated(uint256 oldDelay, uint256 newDelay);

    /// @notice Error when delay is out of bounds
    error DelayOutOfBounds();

    /// @notice Error when ETA is too soon
    error ETATooSoon();

    /// @notice Error when transaction is not queued
    error TransactionNotQueued();

    /// @notice Error when transaction is not ready
    error TransactionNotReady();

    /// @notice Error when transaction has expired
    error TransactionExpired();

    /// @notice Error when transaction execution fails
    error TransactionExecutionFailed();

    /// @notice Error when transaction is already queued
    error TransactionAlreadyQueued();

    /**
     * @notice Constructor
     * @param _admin Admin address (multisig)
     * @param _delay Initial delay period
     */
    constructor(address _admin, uint256 _delay) {
        if (_delay < MINIMUM_DELAY || _delay > MAXIMUM_DELAY) {
            revert DelayOutOfBounds();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PROPOSER_ROLE, _admin);
        _grantRole(EXECUTOR_ROLE, _admin);
        _grantRole(CANCELLER_ROLE, _admin);

        delay = _delay;
    }

    /**
     * @notice Queue a transaction for future execution
     * @param target Target contract address
     * @param value ETH value to send
     * @param data Calldata for the transaction
     * @param eta Estimated time of arrival (execution time)
     * @return txHash Hash of the queued transaction
     */
    function queueTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 eta
    ) external onlyRole(PROPOSER_ROLE) returns (bytes32 txHash) {
        if (eta < block.timestamp + delay) {
            revert ETATooSoon();
        }

        txHash = keccak256(abi.encode(target, value, data, eta));

        if (queuedTransactions[txHash]) {
            revert TransactionAlreadyQueued();
        }

        queuedTransactions[txHash] = true;

        emit TransactionQueued(txHash, target, value, data, eta);
    }

    /**
     * @notice Execute a queued transaction
     * @param target Target contract address
     * @param value ETH value to send
     * @param data Calldata for the transaction
     * @param eta Estimated time of arrival (must match queued transaction)
     * @return result Return data from the transaction
     */
    function executeTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 eta
    ) external onlyRole(EXECUTOR_ROLE) returns (bytes memory result) {
        bytes32 txHash = keccak256(abi.encode(target, value, data, eta));

        if (!queuedTransactions[txHash]) {
            revert TransactionNotQueued();
        }

        if (block.timestamp < eta) {
            revert TransactionNotReady();
        }

        if (block.timestamp > eta + GRACE_PERIOD) {
            revert TransactionExpired();
        }

        queuedTransactions[txHash] = false;

        (bool success, bytes memory returnData) = target.call{value: value}(data);

        if (!success) {
            revert TransactionExecutionFailed();
        }

        emit TransactionExecuted(txHash, target, value, data);

        return returnData;
    }

    /**
     * @notice Cancel a queued transaction
     * @param target Target contract address
     * @param value ETH value
     * @param data Calldata
     * @param eta ETA of the transaction
     */
    function cancelTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 eta
    ) external onlyRole(CANCELLER_ROLE) {
        bytes32 txHash = keccak256(abi.encode(target, value, data, eta));

        if (!queuedTransactions[txHash]) {
            revert TransactionNotQueued();
        }

        queuedTransactions[txHash] = false;

        emit TransactionCancelled(txHash);
    }

    /**
     * @notice Update the delay period
     * @param _newDelay New delay period
     * @dev Can only be called by the timelock itself (through a queued transaction)
     */
    function setDelay(uint256 _newDelay) external {
        require(msg.sender == address(this), "Timelock: only self");

        if (_newDelay < MINIMUM_DELAY || _newDelay > MAXIMUM_DELAY) {
            revert DelayOutOfBounds();
        }

        uint256 oldDelay = delay;
        delay = _newDelay;

        emit DelayUpdated(oldDelay, _newDelay);
    }

    /**
     * @notice Get the hash of a transaction
     * @param target Target contract address
     * @param value ETH value
     * @param data Calldata
     * @param eta ETA
     * @return Transaction hash
     */
    function getTransactionHash(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 eta
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(target, value, data, eta));
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}
}
