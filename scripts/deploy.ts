import { ethers } from "hardhat";

async function main() {
  console.log("Starting deployment...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());
  console.log("");

  // Configuration - Update these for production
  const config = {
    // For testnet, we deploy a mock USDC. For mainnet, use the actual USDC address
    useRealUSDC: false,
    usdcAddress: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359", // Polygon USDC
    // Polymarket CTF address (Polygon mainnet)
    ctfAddress: "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045",
    // Polymarket Exchange address
    exchangeAddress: "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E",
    // Admin address (should be multisig in production)
    adminAddress: deployer.address,
    // Timelock delay (48 hours for production)
    timelockDelay: 48 * 60 * 60, // 48 hours in seconds
  };

  // Step 1: Deploy or use USDC
  let usdcAddress: string;
  if (config.useRealUSDC) {
    usdcAddress = config.usdcAddress;
    console.log("Using existing USDC at:", usdcAddress);
  } else {
    console.log("Deploying MockUSDC...");
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const mockUSDC = await MockUSDC.deploy();
    await mockUSDC.waitForDeployment();
    usdcAddress = await mockUSDC.getAddress();
    console.log("MockUSDC deployed to:", usdcAddress);
  }

  // Step 2: Deploy MockConditionalTokens (for testnet) or use real CTF
  let ctfAddress: string;
  if (config.useRealUSDC) {
    ctfAddress = config.ctfAddress;
    console.log("Using existing CTF at:", ctfAddress);
  } else {
    console.log("\nDeploying MockConditionalTokens...");
    const MockCTF = await ethers.getContractFactory("MockConditionalTokens");
    const mockCTF = await MockCTF.deploy();
    await mockCTF.waitForDeployment();
    ctfAddress = await mockCTF.getAddress();
    console.log("MockConditionalTokens deployed to:", ctfAddress);
  }

  // Step 3: Deploy Timelock
  console.log("\nDeploying Timelock...");
  const Timelock = await ethers.getContractFactory("Timelock");
  const timelock = await Timelock.deploy(config.adminAddress, config.timelockDelay);
  await timelock.waitForDeployment();
  const timelockAddress = await timelock.getAddress();
  console.log("Timelock deployed to:", timelockAddress);

  // Step 4: Deploy AccessController
  console.log("\nDeploying AccessController...");
  const AccessController = await ethers.getContractFactory("AccessController");
  const accessController = await AccessController.deploy(config.adminAddress, timelockAddress);
  await accessController.waitForDeployment();
  const accessControllerAddress = await accessController.getAddress();
  console.log("AccessController deployed to:", accessControllerAddress);

  // Step 5: Deploy CopyVault
  console.log("\nDeploying CopyVault...");
  const CopyVault = await ethers.getContractFactory("CopyVault");
  const copyVault = await CopyVault.deploy(
    usdcAddress,
    "Goblin Copy Vault",
    "gcvUSDC",
    config.adminAddress
  );
  await copyVault.waitForDeployment();
  const copyVaultAddress = await copyVault.getAddress();
  console.log("CopyVault deployed to:", copyVaultAddress);

  // Step 6: Deploy PositionManager
  console.log("\nDeploying PositionManager...");
  const exchangeAddress = config.useRealUSDC ? config.exchangeAddress : config.adminAddress;
  const PositionManager = await ethers.getContractFactory("PositionManager");
  const positionManager = await PositionManager.deploy(
    ctfAddress,
    usdcAddress,
    exchangeAddress,
    config.adminAddress
  );
  await positionManager.waitForDeployment();
  const positionManagerAddress = await positionManager.getAddress();
  console.log("PositionManager deployed to:", positionManagerAddress);

  // Step 7: Configure contracts
  console.log("\nConfiguring contracts...");

  // Set position manager in vault
  console.log("Setting position manager in vault...");
  const setPositionManagerTx = await copyVault.setPositionManager(positionManagerAddress);
  await setPositionManagerTx.wait();
  console.log("Position manager set");

  // Set vault in position manager
  console.log("Setting vault in position manager...");
  const setVaultTx = await positionManager.setVault(copyVaultAddress);
  await setVaultTx.wait();
  console.log("Vault set");

  // Print summary
  console.log("\n========================================");
  console.log("DEPLOYMENT SUMMARY");
  console.log("========================================");
  console.log("Network:", (await ethers.provider.getNetwork()).name);
  console.log("Deployer:", deployer.address);
  console.log("");
  console.log("Contract Addresses:");
  console.log("- USDC:", usdcAddress);
  console.log("- CTF:", ctfAddress);
  console.log("- Timelock:", timelockAddress);
  console.log("- AccessController:", accessControllerAddress);
  console.log("- CopyVault:", copyVaultAddress);
  console.log("- PositionManager:", positionManagerAddress);
  console.log("");
  console.log("Configuration:");
  console.log("- Admin:", config.adminAddress);
  console.log("- Timelock Delay:", config.timelockDelay / 3600, "hours");
  console.log("========================================");

  // Save deployment addresses to file
  const deploymentData = {
    network: (await ethers.provider.getNetwork()).name,
    chainId: (await ethers.provider.getNetwork()).chainId.toString(),
    timestamp: new Date().toISOString(),
    deployer: deployer.address,
    contracts: {
      usdc: usdcAddress,
      ctf: ctfAddress,
      timelock: timelockAddress,
      accessController: accessControllerAddress,
      copyVault: copyVaultAddress,
      positionManager: positionManagerAddress,
    },
    config: {
      adminAddress: config.adminAddress,
      timelockDelay: config.timelockDelay,
      useRealUSDC: config.useRealUSDC,
    },
  };

  console.log("\nDeployment data (save this for verification):");
  console.log(JSON.stringify(deploymentData, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
