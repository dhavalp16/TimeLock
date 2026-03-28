const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  // Get the deployer account (first Hardhat test account by default)
  const [deployer] = await ethers.getSigners();

  console.log("Deploying with account:", deployer.address);
  console.log(
    "Account balance:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH"
  );

  // ── Constructor arguments ──────────────────────────────────────────
  const defaultLockDuration = 30 * 24 * 60 * 60; // 30 days in seconds
  const defaultCooldown     = 24 * 60 * 60;       // 24 hours in seconds
  const penaltyBps          = 500;                // 5% penalty
  const penaltyRecipient    = deployer.address;   // send penalty to yourself for testing

  // ── Deploy ─────────────────────────────────────────────────────────
  const TimelockWallet = await ethers.getContractFactory("TimelockWallet");
  const wallet = await TimelockWallet.deploy(
    defaultLockDuration,
    defaultCooldown,
    penaltyBps,
    penaltyRecipient
  );

  await wallet.waitForDeployment();
  const contractAddress = await wallet.getAddress();

  console.log("\n✅ TimelockWallet deployed to:", contractAddress);
  console.log("   Default lock:     30 days");
  console.log("   Default cooldown: 24 hours");
  console.log("   Emergency penalty: 5%");
  console.log("   Penalty recipient:", penaltyRecipient);

  // ── Write deployment info to a file the frontend can read ──────────
  const artifactPath = path.join(
    __dirname,
    "../artifacts/contracts/TimelockWallet.sol/TimelockWallet.json"
  );
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));

  const deploymentInfo = {
    address: contractAddress,
    abi: artifact.abi,
    network: "localhost",
    chainId: 31337,
    deployedAt: new Date().toISOString(),
    deployer: deployer.address,
  };

  fs.writeFileSync(
    path.join(__dirname, "../deployment.json"),
    JSON.stringify(deploymentInfo, null, 2)
  );

  console.log("\n📄 Deployment info saved to: deployment.json");
  console.log("   Copy the address and ABI into index.html to connect the frontend.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
