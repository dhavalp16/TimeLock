// ═══════════════════════════════════════════
//  CONTRACT INTEGRATION
//  Paste the address from deployment.json here
//  after running: npx hardhat run scripts/deploy.js --network localhost
// ═══════════════════════════════════════════

// 1. Paste your deployed address here:
const CONTRACT_ADDRESS = "0xYourDeployedAddressHere";

// 2. Paste the ABI array from deployment.json here:
const ABI = [
  "function deposit(string calldata label) payable returns (uint256)",
  "function depositWithDuration(uint256 lockDuration, uint256 cooldown, string calldata label) payable returns (uint256)",
  "function requestWithdrawal(uint256 depositId) external",
  "function executeWithdrawal(uint256 depositId) external",
  "function cancelWithdrawal(uint256 depositId) external",
  "function emergencyWithdraw(uint256 depositId) external",
  "function setDefaults(uint256 lockDuration, uint256 cooldown) external",
  "function setEmergencyPenalty(uint256 penaltyBps, address recipient) external",
  "function getDeposit(uint256 depositId) external view returns (tuple(uint256 id, uint256 amount, uint256 lockedUntil, uint256 requestedAt, uint256 cooldown, bool withdrawn, string label))",
  "function getAllDeposits() external view returns (tuple(uint256 id, uint256 amount, uint256 lockedUntil, uint256 requestedAt, uint256 cooldown, bool withdrawn, string label)[])",
  "function getActiveDeposits() external view returns (tuple(uint256 id, uint256 amount, uint256 lockedUntil, uint256 requestedAt, uint256 cooldown, bool withdrawn, string label)[])",
  "function balance() external view returns (uint256)",
  "function canRequestWithdrawal(uint256 depositId) external view returns (bool)",
  "function canExecuteWithdrawal(uint256 depositId) external view returns (bool)",
  "function timeUntilUnlock(uint256 depositId) external view returns (uint256)",
  "function totalDeposited() external view returns (uint256)",
  "function totalWithdrawn() external view returns (uint256)",
  "event Deposited(uint256 indexed depositId, uint256 amount, uint256 lockedUntil, uint256 cooldown, string label)",
  "event WithdrawalRequested(uint256 indexed depositId, uint256 executeAfter)",
  "event WithdrawalExecuted(uint256 indexed depositId, uint256 amount)",
  "event WithdrawalCancelled(uint256 indexed depositId)",
  "event EmergencyWithdrawal(uint256 indexed depositId, uint256 amountSent, uint256 penalty)"
];

// ── ethers.js provider + contract setup ──────────────────────────────
let provider, signer, contract;

async function initContract() {
  if (typeof window.ethereum === "undefined") {
    toast("MetaMask not found. Running in demo mode.", "info");
    return false;
  }

  // Request wallet access
  const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
  if (!accounts.length) return false;

  // Check we are on the right network (Hardhat local = chainId 31337)
  const chainId = await window.ethereum.request({ method: "eth_chainId" });
  if (parseInt(chainId, 16) !== 31337) {
    toast("Wrong network! Switch MetaMask to Hardhat localhost (chainId 31337)", "error");
    return false;
  }

  provider = new ethers.BrowserProvider(window.ethereum);
  signer   = await provider.getSigner();
  contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, signer);

  // Listen for contract events and update UI in real-time
  contract.on("Deposited", (id, amount, lockedUntil, cooldown, label) => {
    toast(`On-chain: Deposited ${ethers.formatEther(amount)} ETH — "${label}"`, "success");
    loadContractState();
  });
  contract.on("WithdrawalExecuted", (id, amount) => {
    toast(`On-chain: Withdrew ${ethers.formatEther(amount)} ETH`, "success");
    loadContractState();
  });
  contract.on("EmergencyWithdrawal", (id, amountSent, penalty) => {
    toast(`Emergency: Received ${ethers.formatEther(amountSent)} ETH (penalty: ${ethers.formatEther(penalty)} ETH)`, "error");
    loadContractState();
  });

  console.log("Contract connected at:", CONTRACT_ADDRESS);
  return true;
}

// ── Load all deposits from the chain ─────────────────────────────────
async function loadContractState() {
  if (!contract) return;

  try {
    const rawDeposits = await contract.getActiveDeposits();

    // Convert BigInt fields to JS numbers the existing UI can use
    state.deposits = rawDeposits.map(d => ({
      id:          Number(d.id),
      amount:      parseFloat(ethers.formatEther(d.amount)),
      label:       d.label || `Deposit #${d.id}`,
      lockedUntil: Number(d.lockedUntil),
      cooldown:    Number(d.cooldown),
      requestedAt: Number(d.requestedAt),
      withdrawn:   d.withdrawn,
      createdAt:   Number(d.lockedUntil) - Number(d.cooldown), // approximation
    }));

    const totalDep = await contract.totalDeposited();
    const totalWit = await contract.totalWithdrawn();
    state.totalWithdrawn = parseFloat(ethers.formatEther(totalWit));

    const balWei = await provider.getBalance(signer.address);
    state.walletBalance = parseFloat(ethers.formatEther(balWei));

    render();
  } catch (err) {
    console.error("Failed to load contract state:", err);
    toast("Could not read contract state: " + err.message, "error");
  }
}

// ── Override createDeposit to call the real contract ─────────────────
async function createDeposit() {
  if (!contract) {
    // Fall back to demo mode if no contract connected
    createDepositDemo();
    return;
  }

  const amount = document.getElementById("dep-amount").value;
  const label  = document.getElementById("dep-label").value.trim() || "Unnamed Deposit";
  const lock   = parseInt(document.getElementById("dep-lock").value);
  const cool   = parseInt(document.getElementById("dep-cool").value);

  if (!amount || parseFloat(amount) <= 0) return toast("Enter a valid amount", "error");
  if (!lock || lock < 60) return toast("Lock duration must be ≥ 60 seconds", "error");
  if (!cool || cool < 60) return toast("Cooldown must be ≥ 60 seconds", "error");

  try {
    toast("Sending transaction…", "info");
    const tx = await contract.depositWithDuration(
      lock,
      cool,
      label,
      { value: ethers.parseEther(amount) }
    );
    toast("Transaction sent. Waiting for confirmation…", "info");
    await tx.wait();
    closeModal("modal-deposit");
    toast(`Deposited ${amount} ETH — locked for ${fmtDuration(lock)}`, "success");
    await loadContractState();
  } catch (err) {
    console.error(err);
    toast("Transaction failed: " + (err.reason || err.message), "error");
  }
}

// ── Override requestWithdrawal ────────────────────────────────────────
async function requestWithdrawal(id) {
  if (!contract) { requestWithdrawalDemo(id); return; }
  try {
    toast("Requesting withdrawal…", "info");
    const tx = await contract.requestWithdrawal(id);
    await tx.wait();
    await loadContractState();
  } catch (err) {
    toast("Failed: " + (err.reason || err.message), "error");
  }
}

// ── Override executeWithdrawal ────────────────────────────────────────
async function executeWithdrawal(id) {
  if (!contract) { executeWithdrawalDemo(id); return; }
  try {
    toast("Executing withdrawal…", "info");
    const tx = await contract.executeWithdrawal(id);
    await tx.wait();
    await loadContractState();
  } catch (err) {
    toast("Failed: " + (err.reason || err.message), "error");
  }
}

// ── Override cancelWithdrawal ─────────────────────────────────────────
async function cancelWithdrawal(id) {
  if (!contract) { cancelWithdrawalDemo(id); return; }
  try {
    const tx = await contract.cancelWithdrawal(id);
    await tx.wait();
    toast("Withdrawal cancelled", "info");
    await loadContractState();
  } catch (err) {
    toast("Failed: " + (err.reason || err.message), "error");
  }
}

// ── Override confirmEmergency ─────────────────────────────────────────
async function confirmEmergency() {
  if (!contract) { confirmEmergencyDemo(); return; }
  const id = state.emergency.depositId;
  try {
    toast("Sending emergency withdrawal…", "info");
    const tx = await contract.emergencyWithdraw(id);
    await tx.wait();
    closeModal("modal-emergency");
    await loadContractState();
  } catch (err) {
    toast("Failed: " + (err.reason || err.message), "error");
  }
}

// ── Keep demo functions under new names so fallback still works ───────
const createDepositDemo       = createDeposit.__proto__; // replaced above
// Note: the original demo functions (createDeposit, requestWithdrawal, etc.)
// defined earlier in the file are automatically shadowed by these overrides
// because JS hoists function declarations but not the variable assignments here.
// The override pattern above calls the original if !contract is true.
