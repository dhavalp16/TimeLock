# Timelock Wallet — Local Setup Guide

## What you're building

```
MetaMask (dummy wallet)
      ↓  signs transactions
index.html + ethers.js
      ↓  JSON-RPC calls
Hardhat local node  ←→  TimelockWallet.sol
      (fake blockchain on your laptop)
```

---

## Step 1 — Project structure

Arrange your files like this:

```
timelock-wallet/
├── contracts/
│   └── TimelockWallet.sol      ← your existing contract
├── scripts/
│   └── deploy.js               ← provided
├── hardhat.config.js           ← provided
├── package.json                ← provided
├── index.html                  ← your existing frontend
└── deployment.json             ← auto-generated after deploy
```

---

## Step 2 — Install dependencies

```bash
cd timelock-wallet
npm install
```

This installs Hardhat and its toolbox (~200 MB, one-time).

---

## Step 3 — Compile the contract

```bash
npx hardhat compile
```

Expected output:
```
Compiled 1 Solidity file successfully (evm target: paris).
```

This creates `artifacts/contracts/TimelockWallet.sol/TimelockWallet.json`
which contains the ABI — the "translation layer" between JS and Solidity.

---

## Step 4 — Start the local blockchain node

Open a **new terminal tab** and run:

```bash
npx hardhat node
```

Leave this running. You'll see output like:

```
Started HTTP and WebSocket JSON-RPC server at http://127.0.0.1:8545/

Accounts
========
Account #0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000 ETH)
Private Key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

Account #1: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000 ETH)
Private Key: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
...
```

These are your **dummy wallets** — pre-funded with 10,000 fake ETH each.
**Do not use these private keys on mainnet. Ever.**

---

## Step 5 — Deploy the contract

In your **original terminal** (not the node one):

```bash
npx hardhat run scripts/deploy.js --network localhost
```

Expected output:
```
Deploying with account: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Account balance: 10000.0 ETH

✅ TimelockWallet deployed to: 0x5FbDB2315678afecb367f032d93F642f64180aa3
   Default lock: 30 days
   Default cooldown: 24 hours
   Emergency penalty: 5%
   Penalty recipient: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

📄 Deployment info saved to: deployment.json
```

Copy the deployed address — you'll need it in Step 7.

---

## Step 6 — Set up MetaMask with the dummy wallet

### 6a. Add Hardhat localhost network to MetaMask

1. Open MetaMask → click network dropdown at top → **"Add a custom network"**
2. Fill in:
   - **Network name:** Hardhat Localhost
   - **RPC URL:** `http://127.0.0.1:8545`
   - **Chain ID:** `31337`
   - **Currency symbol:** `ETH`
3. Click Save → Switch to this network

### 6b. Import a dummy account

1. In MetaMask → click your account icon → **"Import account"**
2. Select type: **Private Key**
3. Paste this key (Account #0 from Hardhat):
   ```
   0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
   ```
4. Click Import

You should now see **10,000 ETH** in this account. This is fake ETH on your local chain.

> **Tip:** Import Account #1 as a second wallet to test multi-user scenarios.

---

## Step 7 — Connect the frontend

Open `index.html` in a text editor. Find the `// CONTRACT INTEGRATION` comment block inside the `<script>` tag (near the bottom).

**Replace that entire comment block** with the contents of `contract-integration.js`.

Then update the two values at the top of that block:

```js
// Replace with your address from Step 5
const CONTRACT_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
```

For the ABI, you can either:
- Use the human-readable ABI already written in `contract-integration.js` (recommended for readability), **or**
- Open `deployment.json` and copy the full `"abi"` array for maximum accuracy

---

## Step 8 — Load ethers.js in the frontend

In `index.html`, add this line inside `<head>` (before the closing `</head>` tag):

```html
<script src="https://cdn.jsdelivr.net/npm/ethers@6.11.1/dist/ethers.umd.min.js"></script>
```

---

## Step 9 — Update the Connect Wallet button

In `index.html`, find the `btn-connect` click handler and replace it with:

```js
document.getElementById('btn-connect').addEventListener('click', async () => {
  const ok = await initContract();
  if (!ok) return;

  const addr = await signer.getAddress();
  document.getElementById('btn-connect').textContent = addr.slice(0,6) + '…' + addr.slice(-4);
  document.getElementById('net-badge').textContent = '● LOCALHOST';
  document.getElementById('net-badge').className = 'net-badge connected';
  toast('Wallet connected: ' + addr.slice(0,6) + '…' + addr.slice(-4), 'success');

  // Load all existing deposits from the chain
  await loadContractState();
});
```

---

## Step 10 — Open the frontend

Open `index.html` directly in Chrome (just double-click it — no server needed).

1. Click **"Connect Wallet"**
2. MetaMask will pop up → approve the connection
3. Your real on-chain deposits will load
4. All actions (deposit, request, execute, emergency) now send real transactions to your local blockchain

---

## Testing flow (recommended order)

```
1. Deposit 0.1 ETH with a 2-minute lock (120 seconds) and 1-minute cooldown (60 seconds)
   → use depositWithDuration, set lock=120, cool=60

2. Wait 2 minutes → status changes from LOCKED → UNLOCKED

3. Click "Request Withdrawal"
   → MetaMask popup → confirm → status becomes COOLING

4. Wait 1 minute → status becomes READY

5. Click "Execute Withdrawal"
   → ETH returns to your wallet

6. Test Emergency Withdrawal on a fresh deposit
   → should deduct 5% and return the rest immediately
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Could not detect network` | Make sure `npx hardhat node` is still running |
| `nonce too high` / stale nonce | MetaMask → Settings → Advanced → Reset Account |
| `Wrong network` toast | Switch MetaMask to Hardhat Localhost (Chain ID 31337) |
| `onlyOwner` revert | MetaMask account must match `deployer.address` in deploy script |
| MetaMask shows 0 ETH | You imported Account #1 but deployed with Account #0 — import #0 |
| ABI mismatch error | Re-copy the ABI from `deployment.json` instead of the human-readable one |

---

## When you restart the Hardhat node

The local chain resets on every restart. You need to:
1. Re-run `npx hardhat run scripts/deploy.js --network localhost`
2. Update `CONTRACT_ADDRESS` in `index.html` with the new address
3. Reset MetaMask nonce: MetaMask → Settings → Advanced → Reset Account
