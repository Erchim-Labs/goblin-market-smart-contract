import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { PositionManager, MockUSDC, MockConditionalTokens } from "../typechain-types";
import { parseUnits } from "ethers";

describe("PositionManager", function () {
  let positionManager: PositionManager;
  let usdc: MockUSDC;
  let mockCTF: MockConditionalTokens;
  let owner: HardhatEthersSigner;
  let admin: HardhatEthersSigner;
  let executor: HardhatEthersSigner;
  let vault: HardhatEthersSigner;
  let user1: HardhatEthersSigner;

  const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
  const EXECUTOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("EXECUTOR_ROLE"));

  // USDC amounts (6 decimals)
  const ONE_USDC = parseUnits("1", 6);
  const HUNDRED_USDC = parseUnits("100", 6);
  const THOUSAND_USDC = parseUnits("1000", 6);
  const TEN_THOUSAND_USDC = parseUnits("10000", 6);
  const MILLION_USDC = parseUnits("1000000", 6);

  // Test condition IDs
  const CONDITION_ID_1 = ethers.keccak256(ethers.toUtf8Bytes("TEST_MARKET_1"));
  const CONDITION_ID_2 = ethers.keccak256(ethers.toUtf8Bytes("TEST_MARKET_2"));
  const TOKEN_ID_YES = 1n;
  const TOKEN_ID_NO = 2n;

  beforeEach(async function () {
    [owner, admin, executor, vault, user1] = await ethers.getSigners();

    // Deploy mock USDC
    const MockUSDCFactory = await ethers.getContractFactory("MockUSDC");
    usdc = await MockUSDCFactory.deploy();
    await usdc.waitForDeployment();

    // Deploy mock CTF
    const MockCTFFactory = await ethers.getContractFactory("MockConditionalTokens");
    mockCTF = await MockCTFFactory.deploy();
    await mockCTF.waitForDeployment();

    // Deploy PositionManager
    const PositionManagerFactory = await ethers.getContractFactory("PositionManager");
    positionManager = await PositionManagerFactory.deploy(
      await mockCTF.getAddress(),
      await usdc.getAddress(),
      admin.address, // Using admin as mock exchange
      admin.address
    );
    await positionManager.waitForDeployment();

    // Setup roles
    await positionManager.connect(admin).grantRole(EXECUTOR_ROLE, executor.address);
    await positionManager.connect(admin).setVault(vault.address);

    // Mint USDC to position manager for testing
    await usdc.mint(await positionManager.getAddress(), MILLION_USDC);
    await usdc.mint(vault.address, MILLION_USDC);
  });

  describe("Deployment", function () {
    it("Should set correct CTF address", async function () {
      expect(await positionManager.ctf()).to.equal(await mockCTF.getAddress());
    });

    it("Should set correct USDC address", async function () {
      expect(await positionManager.usdc()).to.equal(await usdc.getAddress());
    });

    it("Should set correct exchange address", async function () {
      expect(await positionManager.exchange()).to.equal(admin.address);
    });

    it("Should set default limits", async function () {
      expect(await positionManager.maxPositions()).to.equal(20);
      expect(await positionManager.maxPositionSizeBps()).to.equal(1000); // 10%
      expect(await positionManager.maxTotalExposureBps()).to.equal(8000); // 80%
    });

    it("Should revert with zero addresses", async function () {
      const PositionManagerFactory = await ethers.getContractFactory("PositionManager");
      await expect(
        PositionManagerFactory.deploy(
          ethers.ZeroAddress,
          await usdc.getAddress(),
          admin.address,
          admin.address
        )
      ).to.be.revertedWithCustomError(PositionManagerFactory, "ZeroAddress");
    });
  });

  describe("Open Position", function () {
    it("Should open a new position", async function () {
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_1,
        TOKEN_ID_YES,
        THOUSAND_USDC,
        THOUSAND_USDC, // minTokens
        true // isYes
      );

      const position = await positionManager.getPosition(CONDITION_ID_1);
      expect(position.conditionId).to.equal(CONDITION_ID_1);
      expect(position.tokenId).to.equal(TOKEN_ID_YES);
      expect(position.amount).to.equal(THOUSAND_USDC);
      expect(position.isYes).to.be.true;
    });

    it("Should emit PositionOpened event", async function () {
      await expect(
        positionManager.connect(executor).openPosition(
          CONDITION_ID_1,
          TOKEN_ID_YES,
          THOUSAND_USDC,
          THOUSAND_USDC,
          true
        )
      )
        .to.emit(positionManager, "PositionOpened")
        .withArgs(CONDITION_ID_1, TOKEN_ID_YES, THOUSAND_USDC, THOUSAND_USDC);
    });

    it("Should track position in active positions", async function () {
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_1,
        TOKEN_ID_YES,
        THOUSAND_USDC,
        THOUSAND_USDC,
        true
      );

      expect(await positionManager.activePositionCount()).to.equal(1);

      const positions = await positionManager.getActivePositions();
      expect(positions.length).to.equal(1);
      expect(positions[0].conditionId).to.equal(CONDITION_ID_1);
    });

    it("Should add to existing position", async function () {
      // First open
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_1,
        TOKEN_ID_YES,
        THOUSAND_USDC,
        THOUSAND_USDC,
        true
      );

      // Add to position
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_1,
        TOKEN_ID_YES,
        THOUSAND_USDC,
        THOUSAND_USDC,
        true
      );

      const position = await positionManager.getPosition(CONDITION_ID_1);
      expect(position.amount).to.equal(THOUSAND_USDC * 2n);
      expect(position.costBasis).to.equal(THOUSAND_USDC * 2n);
    });

    it("Should only allow executor to open positions", async function () {
      await expect(
        positionManager.connect(user1).openPosition(
          CONDITION_ID_1,
          TOKEN_ID_YES,
          THOUSAND_USDC,
          THOUSAND_USDC,
          true
        )
      ).to.be.reverted;
    });

    it("Should revert if max positions reached", async function () {
      // Set max positions to 2 for testing
      await positionManager.connect(admin).setLimits(2, 1000, 8000);

      // Open 2 positions
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_1,
        TOKEN_ID_YES,
        HUNDRED_USDC,
        HUNDRED_USDC,
        true
      );
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_2,
        TOKEN_ID_YES,
        HUNDRED_USDC,
        HUNDRED_USDC,
        true
      );

      // Try to open a third
      const conditionId3 = ethers.keccak256(ethers.toUtf8Bytes("TEST_MARKET_3"));
      await expect(
        positionManager.connect(executor).openPosition(
          conditionId3,
          TOKEN_ID_YES,
          HUNDRED_USDC,
          HUNDRED_USDC,
          true
        )
      ).to.be.revertedWithCustomError(positionManager, "MaxPositionsReached");
    });

    it("Should revert with zero amount", async function () {
      await expect(
        positionManager.connect(executor).openPosition(
          CONDITION_ID_1,
          TOKEN_ID_YES,
          0,
          0,
          true
        )
      ).to.be.revertedWithCustomError(positionManager, "ZeroAmount");
    });
  });

  describe("Close Position", function () {
    beforeEach(async function () {
      // Open a position first
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_1,
        TOKEN_ID_YES,
        THOUSAND_USDC,
        THOUSAND_USDC,
        true
      );
    });

    it("Should close entire position", async function () {
      await positionManager.connect(executor).closePosition(
        CONDITION_ID_1,
        THOUSAND_USDC,
        THOUSAND_USDC
      );

      const position = await positionManager.getPosition(CONDITION_ID_1);
      expect(position.amount).to.equal(0);
    });

    it("Should emit PositionClosed event", async function () {
      await expect(
        positionManager.connect(executor).closePosition(
          CONDITION_ID_1,
          THOUSAND_USDC,
          THOUSAND_USDC
        )
      )
        .to.emit(positionManager, "PositionClosed")
        .withArgs(CONDITION_ID_1, THOUSAND_USDC, THOUSAND_USDC);
    });

    it("Should partially close position", async function () {
      const closeAmount = HUNDRED_USDC;
      await positionManager.connect(executor).closePosition(
        CONDITION_ID_1,
        closeAmount,
        closeAmount
      );

      const position = await positionManager.getPosition(CONDITION_ID_1);
      expect(position.amount).to.equal(THOUSAND_USDC - closeAmount);
    });

    it("Should remove from active positions when fully closed", async function () {
      await positionManager.connect(executor).closePosition(
        CONDITION_ID_1,
        THOUSAND_USDC,
        THOUSAND_USDC
      );

      expect(await positionManager.activePositionCount()).to.equal(0);
    });

    it("Should revert if position not found", async function () {
      await expect(
        positionManager.connect(executor).closePosition(
          CONDITION_ID_2,
          THOUSAND_USDC,
          THOUSAND_USDC
        )
      ).to.be.revertedWithCustomError(positionManager, "PositionNotFound");
    });

    it("Should revert if insufficient position", async function () {
      await expect(
        positionManager.connect(executor).closePosition(
          CONDITION_ID_1,
          TEN_THOUSAND_USDC, // More than position size
          THOUSAND_USDC
        )
      ).to.be.revertedWithCustomError(positionManager, "InsufficientPosition");
    });

    it("Should only allow executor to close positions", async function () {
      await expect(
        positionManager.connect(user1).closePosition(
          CONDITION_ID_1,
          THOUSAND_USDC,
          THOUSAND_USDC
        )
      ).to.be.reverted;
    });
  });

  describe("Position Value", function () {
    beforeEach(async function () {
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_1,
        TOKEN_ID_YES,
        THOUSAND_USDC,
        THOUSAND_USDC,
        true
      );
    });

    it("Should calculate position value", async function () {
      const value = await positionManager.getPositionValue(CONDITION_ID_1);
      // With default price of 0.50 (500000), value = amount * price / 1e6
      // 1000 * 500000 / 1000000 = 500
      expect(value).to.equal(THOUSAND_USDC / 2n);
    });

    it("Should return zero for non-existent position", async function () {
      const value = await positionManager.getPositionValue(CONDITION_ID_2);
      expect(value).to.equal(0);
    });

    it("Should calculate total position value", async function () {
      // Open second position
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_2,
        TOKEN_ID_NO,
        THOUSAND_USDC,
        THOUSAND_USDC,
        false
      );

      const totalValue = await positionManager.totalPositionValue();
      // Two positions at 0.50 price = 500 + 500 = 1000
      expect(totalValue).to.equal(THOUSAND_USDC);
    });
  });

  describe("Admin Functions", function () {
    it("Should allow admin to set vault", async function () {
      const newVault = ethers.Wallet.createRandom().address;
      await positionManager.connect(admin).setVault(newVault);
      expect(await positionManager.vault()).to.equal(newVault);
    });

    it("Should emit VaultSet event", async function () {
      const newVault = ethers.Wallet.createRandom().address;
      await expect(positionManager.connect(admin).setVault(newVault))
        .to.emit(positionManager, "VaultSet")
        .withArgs(newVault);
    });

    it("Should allow admin to set limits", async function () {
      await positionManager.connect(admin).setLimits(10, 2000, 9000);

      expect(await positionManager.maxPositions()).to.equal(10);
      expect(await positionManager.maxPositionSizeBps()).to.equal(2000);
      expect(await positionManager.maxTotalExposureBps()).to.equal(9000);
    });

    it("Should emit LimitsUpdated event", async function () {
      await expect(positionManager.connect(admin).setLimits(10, 2000, 9000))
        .to.emit(positionManager, "LimitsUpdated")
        .withArgs(10, 2000, 9000);
    });

    it("Should allow admin to set price oracle", async function () {
      const oracle = ethers.Wallet.createRandom().address;
      await positionManager.connect(admin).setPriceOracle(oracle);
      expect(await positionManager.priceOracle()).to.equal(oracle);
    });

    it("Should emit PriceOracleSet event", async function () {
      const oracle = ethers.Wallet.createRandom().address;
      await expect(positionManager.connect(admin).setPriceOracle(oracle))
        .to.emit(positionManager, "PriceOracleSet")
        .withArgs(oracle);
    });

    it("Should only allow admin to update settings", async function () {
      const newVault = ethers.Wallet.createRandom().address;
      await expect(
        positionManager.connect(user1).setVault(newVault)
      ).to.be.reverted;
    });
  });

  describe("Active Positions", function () {
    it("Should return all active positions", async function () {
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_1,
        TOKEN_ID_YES,
        THOUSAND_USDC,
        THOUSAND_USDC,
        true
      );

      await positionManager.connect(executor).openPosition(
        CONDITION_ID_2,
        TOKEN_ID_NO,
        HUNDRED_USDC,
        HUNDRED_USDC,
        false
      );

      const positions = await positionManager.getActivePositions();
      expect(positions.length).to.equal(2);

      // Check first position
      const pos1 = positions.find(p => p.conditionId === CONDITION_ID_1);
      expect(pos1).to.not.be.undefined;
      expect(pos1?.isYes).to.be.true;

      // Check second position
      const pos2 = positions.find(p => p.conditionId === CONDITION_ID_2);
      expect(pos2).to.not.be.undefined;
      expect(pos2?.isYes).to.be.false;
    });

    it("Should return active position count", async function () {
      expect(await positionManager.activePositionCount()).to.equal(0);

      await positionManager.connect(executor).openPosition(
        CONDITION_ID_1,
        TOKEN_ID_YES,
        THOUSAND_USDC,
        THOUSAND_USDC,
        true
      );

      expect(await positionManager.activePositionCount()).to.equal(1);
    });
  });

  describe("Average Entry Price", function () {
    it("Should calculate average entry price correctly", async function () {
      // First buy: 1000 USDC for 1000 tokens (price = 1.0)
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_1,
        TOKEN_ID_YES,
        THOUSAND_USDC,
        THOUSAND_USDC,
        true
      );

      const position1 = await positionManager.getPosition(CONDITION_ID_1);
      // avgEntryPrice = costBasis * 1e6 / amount = 1000 * 1e6 / 1000 = 1e6
      expect(position1.avgEntryPrice).to.equal(1000000n);

      // Second buy: 1000 USDC for 1000 tokens
      await positionManager.connect(executor).openPosition(
        CONDITION_ID_1,
        TOKEN_ID_YES,
        THOUSAND_USDC,
        THOUSAND_USDC,
        true
      );

      const position2 = await positionManager.getPosition(CONDITION_ID_1);
      // avgEntryPrice = 2000 * 1e6 / 2000 = 1e6
      expect(position2.avgEntryPrice).to.equal(1000000n);
      expect(position2.costBasis).to.equal(THOUSAND_USDC * 2n);
      expect(position2.amount).to.equal(THOUSAND_USDC * 2n);
    });
  });
});
