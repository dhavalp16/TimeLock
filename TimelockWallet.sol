// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TimelockWallet
 * @notice A smart contract wallet that enforces time-based withdrawal delays
 *         to prevent impulsive trading and encourage disciplined asset management.
 * @dev Supports multiple deposits with individual lock durations,
 *      withdrawal requests, cooldown enforcement, and emergency exits.
 */
contract TimelockWallet {

    // ─────────────────────────────────────────────
    //  Structs
    // ─────────────────────────────────────────────

    struct Deposit {
        uint256 id;            // Unique deposit ID
        uint256 amount;        // ETH amount in wei
        uint256 lockedUntil;   // Timestamp: deposit cannot be requested before this
        uint256 requestedAt;   // Timestamp: when withdrawal was requested (0 = not requested)
        uint256 cooldown;      // Withdrawal cooldown in seconds after request
        bool    withdrawn;     // Whether funds have been withdrawn
        string  label;         // Optional human-readable label
    }

    // ─────────────────────────────────────────────
    //  State Variables
    // ─────────────────────────────────────────────

    address public immutable owner;

    uint256 public defaultLockDuration;   // seconds — applied if no custom duration given
    uint256 public defaultCooldown;       // seconds — delay between request and execute
    uint256 public emergencyPenaltyBps;   // basis points (e.g. 1000 = 10%)
    address public penaltyRecipient;      // address that receives penalty fees

    uint256 private _nextDepositId;
    mapping(uint256 => Deposit) private _deposits;
    uint256[] private _depositIds;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    // ─────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────

    event Deposited(
        uint256 indexed depositId,
        uint256 amount,
        uint256 lockedUntil,
        uint256 cooldown,
        string  label
    );
    event WithdrawalRequested(uint256 indexed depositId, uint256 executeAfter);
    event WithdrawalExecuted(uint256 indexed depositId, uint256 amount);
    event WithdrawalCancelled(uint256 indexed depositId);
    event EmergencyWithdrawal(uint256 indexed depositId, uint256 amountSent, uint256 penalty);
    event DefaultsUpdated(uint256 lockDuration, uint256 cooldown);
    event EmergencyPenaltyUpdated(uint256 penaltyBps, address recipient);

    // ─────────────────────────────────────────────
    //  Errors
    // ─────────────────────────────────────────────

    error NotOwner();
    error ZeroAmount();
    error DepositNotFound(uint256 id);
    error AlreadyWithdrawn(uint256 id);
    error LockNotExpired(uint256 id, uint256 lockedUntil);
    error WithdrawalAlreadyRequested(uint256 id);
    error NoWithdrawalRequested(uint256 id);
    error CooldownNotElapsed(uint256 id, uint256 executeAfter);
    error TransferFailed();
    error InvalidParameter();

    // ─────────────────────────────────────────────
    //  Modifiers
    // ─────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier depositExists(uint256 depositId) {
        if (_deposits[depositId].amount == 0 && !_deposits[depositId].withdrawn) {
            revert DepositNotFound(depositId);
        }
        _;
    }

    modifier notWithdrawn(uint256 depositId) {
        if (_deposits[depositId].withdrawn) revert AlreadyWithdrawn(depositId);
        _;
    }

    // ─────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────

    /**
     * @param _defaultLockDuration  Default lock duration in seconds (e.g. 7 days = 604800)
     * @param _defaultCooldown      Default cooldown after withdrawal request (e.g. 24 hours = 86400)
     * @param _penaltyBps           Emergency withdrawal penalty in basis points (e.g. 500 = 5%)
     * @param _penaltyRecipient     Address that receives penalty fees (e.g. DAO treasury)
     */
    constructor(
        uint256 _defaultLockDuration,
        uint256 _defaultCooldown,
        uint256 _penaltyBps,
        address _penaltyRecipient
    ) {
        if (_penaltyBps > 3000) revert InvalidParameter();  // max 30% penalty
        if (_penaltyRecipient == address(0)) revert InvalidParameter();

        owner             = msg.sender;
        defaultLockDuration = _defaultLockDuration;
        defaultCooldown   = _defaultCooldown;
        emergencyPenaltyBps = _penaltyBps;
        penaltyRecipient  = _penaltyRecipient;
    }

    // ─────────────────────────────────────────────
    //  Core: Deposit
    // ─────────────────────────────────────────────

    /**
     * @notice Deposit ETH with the default lock duration.
     * @param label Optional human-readable label for this deposit.
     */
    function deposit(string calldata label) external payable onlyOwner returns (uint256 depositId) {
        return _createDeposit(defaultLockDuration, defaultCooldown, label);
    }

    /**
     * @notice Deposit ETH with a custom lock duration and cooldown.
     * @param lockDuration  How long (seconds) before a withdrawal can be requested.
     * @param cooldown      How long (seconds) to wait after requesting before executing.
     * @param label         Optional label.
     */
    function depositWithDuration(
        uint256 lockDuration,
        uint256 cooldown,
        string calldata label
    ) external payable onlyOwner returns (uint256 depositId) {
        return _createDeposit(lockDuration, cooldown, label);
    }

    function _createDeposit(
        uint256 lockDuration,
        uint256 cooldown,
        string calldata label
    ) internal returns (uint256 depositId) {
        if (msg.value == 0) revert ZeroAmount();

        depositId = _nextDepositId++;
        uint256 lockedUntil = block.timestamp + lockDuration;

        _deposits[depositId] = Deposit({
            id:          depositId,
            amount:      msg.value,
            lockedUntil: lockedUntil,
            requestedAt: 0,
            cooldown:    cooldown,
            withdrawn:   false,
            label:       label
        });
        _depositIds.push(depositId);
        totalDeposited += msg.value;

        emit Deposited(depositId, msg.value, lockedUntil, cooldown, label);
    }

    // ─────────────────────────────────────────────
    //  Core: Withdrawal Flow
    // ─────────────────────────────────────────────

    /**
     * @notice Request a withdrawal. The lock period must have expired.
     *         After requesting, you must wait `cooldown` seconds before executing.
     */
    function requestWithdrawal(uint256 depositId)
        external
        onlyOwner
        depositExists(depositId)
        notWithdrawn(depositId)
    {
        Deposit storage dep = _deposits[depositId];

        if (block.timestamp < dep.lockedUntil)
            revert LockNotExpired(depositId, dep.lockedUntil);

        if (dep.requestedAt != 0)
            revert WithdrawalAlreadyRequested(depositId);

        dep.requestedAt = block.timestamp;
        uint256 executeAfter = block.timestamp + dep.cooldown;

        emit WithdrawalRequested(depositId, executeAfter);
    }

    /**
     * @notice Execute a previously requested withdrawal.
     *         The cooldown period must have elapsed since the request.
     */
    function executeWithdrawal(uint256 depositId)
        external
        onlyOwner
        depositExists(depositId)
        notWithdrawn(depositId)
    {
        Deposit storage dep = _deposits[depositId];

        if (dep.requestedAt == 0) revert NoWithdrawalRequested(depositId);

        uint256 executeAfter = dep.requestedAt + dep.cooldown;
        if (block.timestamp < executeAfter)
            revert CooldownNotElapsed(depositId, executeAfter);

        uint256 amount = dep.amount;
        dep.withdrawn = true;
        dep.amount    = 0;
        totalWithdrawn += amount;

        emit WithdrawalExecuted(depositId, amount);

        (bool success,) = owner.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Cancel a pending withdrawal request.
     *         The deposit remains locked until the next request.
     */
    function cancelWithdrawal(uint256 depositId)
        external
        onlyOwner
        depositExists(depositId)
        notWithdrawn(depositId)
    {
        Deposit storage dep = _deposits[depositId];
        if (dep.requestedAt == 0) revert NoWithdrawalRequested(depositId);

        dep.requestedAt = 0;
        emit WithdrawalCancelled(depositId);
    }

    // ─────────────────────────────────────────────
    //  Emergency Exit
    // ─────────────────────────────────────────────

    /**
     * @notice Emergency withdrawal that bypasses the timelock — but incurs a penalty.
     * @dev    Useful if you need funds urgently. Penalty goes to penaltyRecipient.
     */
    function emergencyWithdraw(uint256 depositId)
        external
        onlyOwner
        depositExists(depositId)
        notWithdrawn(depositId)
    {
        Deposit storage dep = _deposits[depositId];

        uint256 amount  = dep.amount;
        uint256 penalty = (amount * emergencyPenaltyBps) / 10_000;
        uint256 payout  = amount - penalty;

        dep.withdrawn = true;
        dep.amount    = 0;
        totalWithdrawn += amount;

        emit EmergencyWithdrawal(depositId, payout, penalty);

        if (penalty > 0) {
            (bool ok1,) = penaltyRecipient.call{value: penalty}("");
            if (!ok1) revert TransferFailed();
        }
        (bool ok2,) = owner.call{value: payout}("");
        if (!ok2) revert TransferFailed();
    }

    // ─────────────────────────────────────────────
    //  Configuration
    // ─────────────────────────────────────────────

    function setDefaults(uint256 lockDuration, uint256 cooldown) external onlyOwner {
        defaultLockDuration = lockDuration;
        defaultCooldown     = cooldown;
        emit DefaultsUpdated(lockDuration, cooldown);
    }

    function setEmergencyPenalty(uint256 penaltyBps, address recipient) external onlyOwner {
        if (penaltyBps > 3000) revert InvalidParameter();
        if (recipient == address(0)) revert InvalidParameter();
        emergencyPenaltyBps = penaltyBps;
        penaltyRecipient    = recipient;
        emit EmergencyPenaltyUpdated(penaltyBps, recipient);
    }

    // ─────────────────────────────────────────────
    //  Views
    // ─────────────────────────────────────────────

    function getDeposit(uint256 depositId) external view returns (Deposit memory) {
        return _deposits[depositId];
    }

    function getAllDeposits() external view returns (Deposit[] memory) {
        uint256 len = _depositIds.length;
        Deposit[] memory all = new Deposit[](len);
        for (uint256 i = 0; i < len; i++) {
            all[i] = _deposits[_depositIds[i]];
        }
        return all;
    }

    function getActiveDeposits() external view returns (Deposit[] memory) {
        uint256 count;
        for (uint256 i = 0; i < _depositIds.length; i++) {
            if (!_deposits[_depositIds[i]].withdrawn) count++;
        }
        Deposit[] memory active = new Deposit[](count);
        uint256 j;
        for (uint256 i = 0; i < _depositIds.length; i++) {
            if (!_deposits[_depositIds[i]].withdrawn) {
                active[j++] = _deposits[_depositIds[i]];
            }
        }
        return active;
    }

    function balance() external view returns (uint256) {
        return address(this).balance;
    }

    function canRequestWithdrawal(uint256 depositId) external view returns (bool) {
        Deposit storage dep = _deposits[depositId];
        return !dep.withdrawn
            && dep.requestedAt == 0
            && block.timestamp >= dep.lockedUntil;
    }

    function canExecuteWithdrawal(uint256 depositId) external view returns (bool) {
        Deposit storage dep = _deposits[depositId];
        return !dep.withdrawn
            && dep.requestedAt != 0
            && block.timestamp >= dep.requestedAt + dep.cooldown;
    }

    function timeUntilUnlock(uint256 depositId) external view returns (uint256) {
        uint256 lu = _deposits[depositId].lockedUntil;
        if (block.timestamp >= lu) return 0;
        return lu - block.timestamp;
    }

    function timeUntilExecutable(uint256 depositId) external view returns (uint256) {
        Deposit storage dep = _deposits[depositId];
        if (dep.requestedAt == 0) return type(uint256).max;
        uint256 executeAfter = dep.requestedAt + dep.cooldown;
        if (block.timestamp >= executeAfter) return 0;
        return executeAfter - block.timestamp;
    }

    // ─────────────────────────────────────────────
    //  Receive
    // ─────────────────────────────────────────────

    receive() external payable {
        // Accept direct ETH sends, auto-deposit with defaults
        if (msg.sender == owner && msg.value > 0) {
            uint256 depositId = _nextDepositId++;
            uint256 lockedUntil = block.timestamp + defaultLockDuration;
            _deposits[depositId] = Deposit({
                id:          depositId,
                amount:      msg.value,
                lockedUntil: lockedUntil,
                requestedAt: 0,
                cooldown:    defaultCooldown,
                withdrawn:   false,
                label:       "Direct transfer"
            });
            _depositIds.push(depositId);
            totalDeposited += msg.value;
            emit Deposited(depositId, msg.value, lockedUntil, defaultCooldown, "Direct transfer");
        }
    }
}
