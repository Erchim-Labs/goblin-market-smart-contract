import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { CopyVault, MockUSDC, PositionManager, MockConditionalTokens } from "../typechain-types";
import { parseUnits } from "ethers";

describe("CopyVault", function () {
  let copyVault: CopyVault;
  let usdc: MockUSDC;
  let positionManager: PositionManager;
  let mockCTF: MockConditionalTokens;
  let owner: HardhatEthersSigner;
  let admin: HardhatEthersSigner;
  let executor: HardhatEthersSigner;
  let guardian: HardhatEthersSigner;
  let strategist: HardhatEthersSigner;
  let user1: HardhatEthersSigner;
  let user2: HardhatEthersSigner;

  const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
  const EXECUTOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("EXECUTOR_ROLE"));
  const GUARDIAN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GUARDIAN_ROLE"));
  const STRATEGIST_ROLE = ethers.keccak256(ethers.toUtf8Bytes("STRATEGIST_ROLE"));

  // USDC amounts (6 decimals)
  const ONE_USDC = parseUnits("1", 6);
  const TEN_USDC = parseUnits("10", 6);
  const HUNDRED_USDC = parseUnits("100", 6);
  const THOUSAND_USDC = parseUnits("1000", 6);
  const TEN_THOUSAND_USDC = parseUnits("10000", 6);
  const HUNDRED_THOUSAND_USDC = parseUnits("100000", 6);
  const MILLION_USDC = parseUnits("1000000", 6);

  beforeEach(async function () {
    [owner, admin, executor, guardian, strategist, user1, user2] = await ethers.getSigners();

    // Deploy mock USDC
    const MockUSDCFactory = await ethers.getContractFactory("MockUSDC");
    usdc = await MockUSDCFactory.deploy();
    await usdc.waitForDeployment();

    // Deploy mock CTF
    const MockCTFFactory = await ethers.getContractFactory("MockConditionalTokens");
    mockCTF = await MockCTFFactory.deploy();
    await mockCTF.waitForDeployment();

    // Deploy CopyVault
    const CopyVaultFactory = await ethers.getContractFactory("CopyVault");
    copyVault = await CopyVaultFactory.deploy(
      await usdc.getAddress(),
      "Goblin Copy Vault",
      "gcvUSDC",
      admin.address
    );
    await copyVault.waitForDeployment();

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
    await copyVault.connect(admin).grantRole(EXECUTOR_ROLE, executor.address);
    await copyVault.connect(admin).grantRole(GUARDIAN_ROLE, guardian.address);
    await copyVault.connect(admin).grantRole(STRATEGIST_ROLE, strategist.address);

    // Set position manager
    await copyVault.connect(admin).setPositionManager(await positionManager.getAddress());

    // Setup position manager
    await positionManager.connect(admin).setVault(await copyVault.getAddress());
    await positionManager.connect(admin).grantRole(EXECUTOR_ROLE, executor.address);

    // Mint USDC to users
    await usdc.mint(user1.address, MILLION_USDC);
    await usdc.mint(user2.address, MILLION_USDC);
    await usdc.mint(admin.address, MILLION_USDC);
  });

  describe("Deployment", function () {
    it("Should set the correct asset", async function () {
      expect(await copyVault.asset()).to.equal(await usdc.getAddress());
    });

    it("Should set the correct name and symbol", async function () {
      expect(await copyVault.name()).to.equal("Goblin Copy Vault");
      expect(await copyVault.symbol()).to.equal("gcvUSDC");
    });

    it("Should set the correct admin", async function () {
      expect(await copyVault.hasRole(ADMIN_ROLE, admin.address)).to.be.true;
    });

    it("Should set default parameters", async function () {
      expect(await copyVault.maxTotalDeposits()).to.equal(parseUnits("10000000", 6)); // $10M
      expect(await copyVault.maxDepositPerUser()).to.equal(parseUnits("100000", 6)); // $100k
      expect(await copyVault.minDeposit()).to.equal(parseUnits("10", 6)); // $10
    });

    it("Should revert with zero admin address", async function () {
      const CopyVaultFactory = await ethers.getContractFactory("CopyVault");
      await expect(
        CopyVaultFactory.deploy(
          await usdc.getAddress(),
          "Test Vault",
          "tVault",
          ethers.ZeroAddress
        )
      ).to.be.revertedWithCustomError(CopyVaultFactory, "ZeroAddress");
    });
  });

  describe("Deposits", function () {
    beforeEach(async function () {
      await usdc.connect(user1).approve(await copyVault.getAddress(), MILLION_USDC);
    });

    it("Should allow deposits above minimum", async function () {
      const depositAmount = HUNDRED_USDC;
      await copyVault.connect(user1).deposit(depositAmount, user1.address);

      expect(await copyVault.totalAssets()).to.equal(depositAmount);
      expect(await copyVault.balanceOf(user1.address)).to.be.gt(0);
    });

    it("Should update user deposits tracking", async function () {
      const depositAmount = HUNDRED_USDC;
      await copyVault.connect(user1).deposit(depositAmount, user1.address);

      expect(await copyVault.userDeposits(user1.address)).to.equal(depositAmount);
    });

    it("Should update totalIdleAssets", async function () {
      const depositAmount = HUNDRED_USDC;
      await copyVault.connect(user1).deposit(depositAmount, user1.address);

      expect(await copyVault.totalIdleAssets()).to.equal(depositAmount);
    });

    it("Should emit Deposit event", async function () {
      const depositAmount = HUNDRED_USDC;
      await expect(copyVault.connect(user1).deposit(depositAmount, user1.address))
        .to.emit(copyVault, "Deposit");
    });

    it("Should revert if deposit below minimum", async function () {
      const depositAmount = ONE_USDC; // Below $10 minimum
      await expect(
        copyVault.connect(user1).deposit(depositAmount, user1.address)
      ).to.be.revertedWithCustomError(copyVault, "BelowMinimumDeposit");
    });

    it("Should revert if deposit exceeds user cap", async function () {
      // Max per user is $100k
      const depositAmount = parseUnits("150000", 6);
      await expect(
        copyVault.connect(user1).deposit(depositAmount, user1.address)
      ).to.be.revertedWithCustomError(copyVault, "ExceedsUserCap");
    });

    it("Should revert if deposit exceeds vault cap", async function () {
      // Set a small vault cap for testing
      await copyVault.connect(admin).setParameters(
        THOUSAND_USDC, // maxTotalDeposits
        HUNDRED_THOUSAND_USDC, // maxDepositPerUser
        TEN_USDC // minDeposit
      );

      const depositAmount = TEN_THOUSAND_USDC;
      await expect(
        copyVault.connect(user1).deposit(depositAmount, user1.address)
      ).to.be.revertedWithCustomError(copyVault, "ExceedsVaultCap");
    });

    it("Should revert when paused", async function () {
      await copyVault.connect(guardian).pause();
      await expect(
        copyVault.connect(user1).deposit(HUNDRED_USDC, user1.address)
      ).to.be.revertedWithCustomError(copyVault, "EnforcedPause");
    });
  });

  describe("Withdrawals", function () {
    beforeEach(async function () {
      await usdc.connect(user1).approve(await copyVault.getAddress(), MILLION_USDC);
      await copyVault.connect(user1).deposit(TEN_THOUSAND_USDC, user1.address);
    });

    it("Should allow withdrawals", async function () {
      const shares = await copyVault.balanceOf(user1.address);
      const balanceBefore = await usdc.balanceOf(user1.address);

      await copyVault.connect(user1).redeem(shares, user1.address, user1.address);

      const balanceAfter = await usdc.balanceOf(user1.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should update totalIdleAssets on withdrawal", async function () {
      const shares = await copyVault.balanceOf(user1.address);
      await copyVault.connect(user1).redeem(shares, user1.address, user1.address);

      expect(await copyVault.totalIdleAssets()).to.equal(0);
    });

    it("Should allow withdrawals even when paused", async function () {
      await copyVault.connect(guardian).pause();

      const shares = await copyVault.balanceOf(user1.address);
      // Should not revert
      await copyVault.connect(user1).redeem(shares, user1.address, user1.address);
    });

    it("Should emit Withdraw event", async function () {
      const shares = await copyVault.balanceOf(user1.address);
      await expect(copyVault.connect(user1).redeem(shares, user1.address, user1.address))
        .to.emit(copyVault, "Withdraw");
    });

    it("Should revert if insufficient liquidity", async function () {
      // Have two users deposit
      await usdc.connect(user2).approve(await copyVault.getAddress(), TEN_THOUSAND_USDC);
      await copyVault.connect(user2).deposit(TEN_THOUSAND_USDC, user2.address);
      // Now vault has $20,000

      // Grant executor role to admin for this test
      await copyVault.connect(admin).grantRole(EXECUTOR_ROLE, admin.address);

      // Increase max trade size to 100% for this test
      await copyVault.connect(admin).setMaxTradeSizeBps(10000);

      // Allocate almost all funds (leave only $100)
      const allocateAmount = TEN_THOUSAND_USDC + TEN_THOUSAND_USDC - HUNDRED_USDC;
      await copyVault.connect(admin).allocateForTrade(allocateAmount);

      // User1's shares are worth ~$10,000 but only $100 is liquid
      // Try to withdraw with assets amount greater than liquidity
      const withdrawAmount = THOUSAND_USDC; // Try to withdraw $1000
      await expect(
        copyVault.connect(user1).withdraw(withdrawAmount, user1.address, user1.address)
      ).to.be.revertedWithCustomError(copyVault, "InsufficientLiquidity");
    });
  });

  describe("Share Calculation", function () {
    beforeEach(async function () {
      await usdc.connect(user1).approve(await copyVault.getAddress(), MILLION_USDC);
      await usdc.connect(user2).approve(await copyVault.getAddress(), MILLION_USDC);
    });

    it("Should calculate shares correctly for first depositor", async function () {
      const depositAmount = HUNDRED_USDC;
      await copyVault.connect(user1).deposit(depositAmount, user1.address);

      // With decimals offset of 3, first depositor gets amount + 1000 shares
      const shares = await copyVault.balanceOf(user1.address);
      expect(shares).to.be.gt(0);
    });

    it("Should maintain proportional shares for multiple depositors", async function () {
      // First deposit
      await copyVault.connect(user1).deposit(HUNDRED_USDC, user1.address);
      const shares1 = await copyVault.balanceOf(user1.address);

      // Second deposit of same amount
      await copyVault.connect(user2).deposit(HUNDRED_USDC, user2.address);
      const shares2 = await copyVault.balanceOf(user2.address);

      // Shares should be approximately equal (within rounding)
      const diff = shares1 > shares2 ? shares1 - shares2 : shares2 - shares1;
      expect(diff).to.be.lt(1000); // Allow small rounding difference
    });

    it("Should preview deposit correctly", async function () {
      const depositAmount = HUNDRED_USDC;
      const previewShares = await copyVault.previewDeposit(depositAmount);

      await copyVault.connect(user1).deposit(depositAmount, user1.address);
      const actualShares = await copyVault.balanceOf(user1.address);

      expect(previewShares).to.equal(actualShares);
    });
  });

  describe("Trade Allocation", function () {
    beforeEach(async function () {
      await usdc.connect(user1).approve(await copyVault.getAddress(), MILLION_USDC);
      await copyVault.connect(user1).deposit(TEN_THOUSAND_USDC, user1.address);
    });

    it("Should allow executor to allocate funds for trade", async function () {
      const allocateAmount = HUNDRED_USDC;
      await copyVault.connect(executor).allocateForTrade(allocateAmount);

      expect(await copyVault.totalIdleAssets()).to.equal(TEN_THOUSAND_USDC - allocateAmount);
    });

    it("Should emit TradeAllocated event", async function () {
      const allocateAmount = HUNDRED_USDC;
      await expect(copyVault.connect(executor).allocateForTrade(allocateAmount))
        .to.emit(copyVault, "TradeAllocated")
        .withArgs(allocateAmount);
    });

    it("Should revert if not executor", async function () {
      await expect(
        copyVault.connect(user1).allocateForTrade(HUNDRED_USDC)
      ).to.be.reverted;
    });

    it("Should revert if exceeds max trade size", async function () {
      // Max trade size is 5% = 500 bps
      // 10000 USDC * 5% = 500 USDC max
      const allocateAmount = THOUSAND_USDC;
      await expect(
        copyVault.connect(executor).allocateForTrade(allocateAmount)
      ).to.be.revertedWithCustomError(copyVault, "ExceedsMaxTradeSize");
    });

    it("Should revert if exceeds idle assets", async function () {
      const allocateAmount = TEN_THOUSAND_USDC + ONE_USDC;
      await expect(
        copyVault.connect(executor).allocateForTrade(allocateAmount)
      ).to.be.revertedWithCustomError(copyVault, "InsufficientIdleAssets");
    });

    it("Should revert when paused", async function () {
      await copyVault.connect(guardian).pause();
      await expect(
        copyVault.connect(executor).allocateForTrade(HUNDRED_USDC)
      ).to.be.revertedWithCustomError(copyVault, "EnforcedPause");
    });
  });

  describe("Leader Management", function () {
    const leader1 = ethers.Wallet.createRandom().address;
    const leader2 = ethers.Wallet.createRandom().address;

    it("Should allow strategist to add leader", async function () {
      await copyVault.connect(strategist).addLeader(leader1);
      expect(await copyVault.approvedLeaders(leader1)).to.be.true;
    });

    it("Should emit LeaderAdded event", async function () {
      await expect(copyVault.connect(strategist).addLeader(leader1))
        .to.emit(copyVault, "LeaderAdded")
        .withArgs(leader1);
    });

    it("Should add leader to list", async function () {
      await copyVault.connect(strategist).addLeader(leader1);
      await copyVault.connect(strategist).addLeader(leader2);

      const leaders = await copyVault.getLeaders();
      expect(leaders.length).to.equal(2);
      expect(leaders).to.include(leader1);
      expect(leaders).to.include(leader2);
    });

    it("Should allow strategist to remove leader", async function () {
      await copyVault.connect(strategist).addLeader(leader1);
      await copyVault.connect(strategist).removeLeader(leader1);

      expect(await copyVault.approvedLeaders(leader1)).to.be.false;
    });

    it("Should emit LeaderRemoved event", async function () {
      await copyVault.connect(strategist).addLeader(leader1);
      await expect(copyVault.connect(strategist).removeLeader(leader1))
        .to.emit(copyVault, "LeaderRemoved")
        .withArgs(leader1);
    });

    it("Should revert if not strategist", async function () {
      await expect(
        copyVault.connect(user1).addLeader(leader1)
      ).to.be.reverted;
    });

    it("Should revert if leader already approved", async function () {
      await copyVault.connect(strategist).addLeader(leader1);
      await expect(
        copyVault.connect(strategist).addLeader(leader1)
      ).to.be.revertedWithCustomError(copyVault, "LeaderAlreadyApproved");
    });

    it("Should revert if leader not approved when removing", async function () {
      await expect(
        copyVault.connect(strategist).removeLeader(leader1)
      ).to.be.revertedWithCustomError(copyVault, "LeaderNotApproved");
    });
  });

  describe("Emergency Functions", function () {
    it("Should allow guardian to pause", async function () {
      await copyVault.connect(guardian).pause();
      expect(await copyVault.paused()).to.be.true;
    });

    it("Should only allow admin to unpause", async function () {
      await copyVault.connect(guardian).pause();
      await expect(
        copyVault.connect(guardian).unpause()
      ).to.be.reverted;

      await copyVault.connect(admin).unpause();
      expect(await copyVault.paused()).to.be.false;
    });

    it("Should not allow non-guardian to pause", async function () {
      await expect(
        copyVault.connect(user1).pause()
      ).to.be.reverted;
    });
  });

  describe("Parameter Updates", function () {
    it("Should allow admin to update parameters", async function () {
      const newMaxTotal = MILLION_USDC;
      const newMaxUser = TEN_THOUSAND_USDC;
      const newMinDeposit = HUNDRED_USDC;

      await copyVault.connect(admin).setParameters(newMaxTotal, newMaxUser, newMinDeposit);

      expect(await copyVault.maxTotalDeposits()).to.equal(newMaxTotal);
      expect(await copyVault.maxDepositPerUser()).to.equal(newMaxUser);
      expect(await copyVault.minDeposit()).to.equal(newMinDeposit);
    });

    it("Should emit ParametersUpdated event", async function () {
      await expect(
        copyVault.connect(admin).setParameters(MILLION_USDC, TEN_THOUSAND_USDC, HUNDRED_USDC)
      )
        .to.emit(copyVault, "ParametersUpdated")
        .withArgs(MILLION_USDC, TEN_THOUSAND_USDC, HUNDRED_USDC);
    });

    it("Should only allow admin to update parameters", async function () {
      await expect(
        copyVault.connect(user1).setParameters(MILLION_USDC, TEN_THOUSAND_USDC, HUNDRED_USDC)
      ).to.be.reverted;
    });
  });

  describe("Fee Configuration", function () {
    it("Should allow admin to set fee parameters", async function () {
      await copyVault.connect(admin).setFeeParameters(
        2000, // 20% performance fee
        300,  // 3% management fee
        user1.address
      );

      expect(await copyVault.performanceFee()).to.equal(2000);
      expect(await copyVault.managementFee()).to.equal(300);
      expect(await copyVault.feeRecipient()).to.equal(user1.address);
    });

    it("Should revert if performance fee exceeds maximum", async function () {
      await expect(
        copyVault.connect(admin).setFeeParameters(
          3500, // 35% - exceeds 30% max
          200,
          admin.address
        )
      ).to.be.revertedWithCustomError(copyVault, "FeeExceedsMaximum");
    });

    it("Should revert if management fee exceeds maximum", async function () {
      await expect(
        copyVault.connect(admin).setFeeParameters(
          1000,
          600, // 6% - exceeds 5% max
          admin.address
        )
      ).to.be.revertedWithCustomError(copyVault, "FeeExceedsMaximum");
    });
  });

  describe("View Functions", function () {
    beforeEach(async function () {
      await usdc.connect(user1).approve(await copyVault.getAddress(), MILLION_USDC);
      await copyVault.connect(user1).deposit(TEN_THOUSAND_USDC, user1.address);
    });

    it("Should return correct maxDeposit", async function () {
      const maxDeposit = await copyVault.maxDeposit(user1.address);
      // User cap is $100k, user deposited $10k, so max is $90k
      expect(maxDeposit).to.equal(parseUnits("90000", 6));
    });

    it("Should return 0 maxDeposit when paused", async function () {
      await copyVault.connect(guardian).pause();
      expect(await copyVault.maxDeposit(user1.address)).to.equal(0);
    });

    it("Should return correct maxWithdraw (limited by liquidity)", async function () {
      const maxWithdraw = await copyVault.maxWithdraw(user1.address);
      // All funds are idle, so should be close to deposited amount
      expect(maxWithdraw).to.be.closeTo(TEN_THOUSAND_USDC, parseUnits("1", 6));
    });

    it("Should return isApprovedLeader correctly", async function () {
      const leader = ethers.Wallet.createRandom().address;

      expect(await copyVault.isApprovedLeader(leader)).to.be.false;

      await copyVault.connect(strategist).addLeader(leader);
      expect(await copyVault.isApprovedLeader(leader)).to.be.true;
    });
  });
});
