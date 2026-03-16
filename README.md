# 🔐 Timelock Wallet

A smart contract + frontend that secures digital assets behind time-based withdrawal rules, preventing impulsive trading.

---

## What It Does

| Feature | Description |
|---|---|
| **Timed Locks** | Each deposit is locked for a configurable duration (1 day → 90+ days) |
| **Withdrawal Cooldown** | After requesting, you must wait (1h → 1 week) before funds release |
| **Emergency Exit** | Break the lock early — but pay a configurable penalty (default 5%) |
| **Multi-Deposit** | Manage many independent timelocked positions simultaneously |
| **Labels** | Tag each deposit (e.g. "HODL bag", "Emergency fund") |

---

## Project Structure

```
TimelockWallet.sol   — Solidity smart contract (Solidity ^0.8.20)
index.html           — Frontend UI (vanilla JS, no build step needed)
README.md            — This file
```

---

## Smart Contract

### Deployment

```bash
# Using Hardhat
npx hardhat compile
npx hardhat deploy --network mainnet

# Constructor args
TimelockWallet(
  uint256 defaultLockDuration,   // e.g. 2592000 = 30 days
  uint256 defaultCooldown,       // e.g. 86400 = 24 hours
  uint256 penaltyBps,            // e.g. 500 = 5%
  address penaltyRecipient       // treasury or DAO address
)
```

### Core Functions

```solidity
// Deposit with default settings
deposit(string label) payable

// Deposit with custom settings
depositWithDuration(uint256 lockDuration, uint256 cooldown, string label) payable

// Normal withdrawal flow (2 steps):
requestWithdrawal(uint256 depositId)   // Step 1: after lock expires
executeWithdrawal(uint256 depositId)   // Step 2: after cooldown elapses

// Cancel a pending request
cancelWithdrawal(uint256 depositId)

// Break the lock (pays penalty)
emergencyWithdraw(uint256 depositId)
```

### Withdrawal Flow

```
Deposit Created
      │
      ▼
  [LOCKED] ──────────────────────────────────► emergencyWithdraw() (penalty)
      │  (lock duration elapses)
      ▼
  [UNLOCKED]
      │  requestWithdrawal()
      ▼
  [COOLING] ─────────────────────────────────► cancelWithdrawal()
      │  (cooldown elapses)           │
      ▼                               └──────► emergencyWithdraw() (penalty)
  [READY]
      │  executeWithdrawal()
      ▼
  [WITHDRAWN] ✓
```

---

## Frontend

Open `index.html` directly in a browser — no build step required.

**Demo mode** works out of the box with simulated deposits and countdowns.

**MetaMask mode**: Click "Connect Wallet". The frontend will use your wallet address and the live contract once deployed. Update the contract address and ABI in the `<script>` section.

### Connecting to a deployed contract

In `index.html`, replace the `// CONTRACT INTEGRATION` comment block with:

```javascript
const CONTRACT_ADDRESS = "0xYourDeployedAddress";
const ABI = [ /* paste ABI from artifacts */ ];

// Load ethers.js
const provider = new ethers.BrowserProvider(window.ethereum);
const signer   = await provider.getSigner();
const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, signer);

// Then replace demo actions with real calls:
// await contract.deposit(label, { value: ethers.parseEther(amount) });
// await contract.requestWithdrawal(depositId);
// await contract.executeWithdrawal(depositId);
```

---

## Security Considerations

- **Owner-only**: All deposit and withdrawal functions are `onlyOwner`
- **Re-entrancy safe**: State is updated before external calls (CEI pattern)
- **Penalty cap**: Emergency penalty is capped at 30% in the constructor
- **Zero-address check**: penaltyRecipient cannot be zero address
- **Audit before mainnet**: This contract has not been audited. Use at your own risk.

---

## Customization

| Parameter | Default | Description |
|---|---|---|
| `defaultLockDuration` | 30 days | How long funds are locked after deposit |
| `defaultCooldown` | 24 hours | Delay between request and execute |
| `emergencyPenaltyBps` | 500 (5%) | Penalty for bypassing the timelock |

These can be updated via `setDefaults()` and `setEmergencyPenalty()`.

---

## License

MIT
