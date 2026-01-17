import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { AccessController, Timelock } from "../typechain-types";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("AccessController", function () {
  let accessController: AccessController;
  let timelock: Timelock;
  let admin: HardhatEthersSigner;
  let executor: HardhatEthersSigner;
  let guardian: HardhatEthersSigner;
  let strategist: HardhatEthersSigner;
  let user1: HardhatEthersSigner;

  const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
  const EXECUTOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("EXECUTOR_ROLE"));
  const GUARDIAN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GUARDIAN_ROLE"));
  const STRATEGIST_ROLE = ethers.keccak256(ethers.toUtf8Bytes("STRATEGIST_ROLE"));

  const TWO_DAYS = 48 * 60 * 60;

  beforeEach(async function () {
    [admin, executor, guardian, strategist, user1] = await ethers.getSigners();

    // Deploy Timelock first
    const TimelockFactory = await ethers.getContractFactory("Timelock");
    timelock = await TimelockFactory.deploy(admin.address, TWO_DAYS);
    await timelock.waitForDeployment();

    // Deploy AccessController
    const AccessControllerFactory = await ethers.getContractFactory("AccessController");
    accessController = await AccessControllerFactory.deploy(
      admin.address,
      await timelock.getAddress()
    );
    await accessController.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set admin correctly", async function () {
      expect(await accessController.isAdmin(admin.address)).to.be.true;
    });

    it("Should set timelock correctly", async function () {
      expect(await accessController.timelock()).to.equal(await timelock.getAddress());
    });

    it("Should revert with zero admin address", async function () {
      const AccessControllerFactory = await ethers.getContractFactory("AccessController");
      await expect(
        AccessControllerFactory.deploy(
          ethers.ZeroAddress,
          await timelock.getAddress()
        )
      ).to.be.revertedWithCustomError(AccessControllerFactory, "ZeroAddress");
    });

    it("Should revert with zero timelock address", async function () {
      const AccessControllerFactory = await ethers.getContractFactory("AccessController");
      await expect(
        AccessControllerFactory.deploy(
          admin.address,
          ethers.ZeroAddress
        )
      ).to.be.revertedWithCustomError(AccessControllerFactory, "ZeroAddress");
    });
  });

  describe("Role Management", function () {
    it("Should allow admin to grant guardian role", async function () {
      await accessController.connect(admin).grantGuardianRole(guardian.address);
      expect(await accessController.isGuardian(guardian.address)).to.be.true;
    });

    it("Should allow admin to revoke guardian role", async function () {
      await accessController.connect(admin).grantGuardianRole(guardian.address);
      await accessController.connect(admin).revokeGuardianRole(guardian.address);
      expect(await accessController.isGuardian(guardian.address)).to.be.false;
    });

    it("Should allow admin to grant strategist role", async function () {
      await accessController.connect(admin).grantStrategistRole(strategist.address);
      expect(await accessController.isStrategist(strategist.address)).to.be.true;
    });

    it("Should allow admin to revoke strategist role", async function () {
      await accessController.connect(admin).grantStrategistRole(strategist.address);
      await accessController.connect(admin).revokeStrategistRole(strategist.address);
      expect(await accessController.isStrategist(strategist.address)).to.be.false;
    });

    it("Should allow admin to revoke executor role immediately", async function () {
      // First grant executor role through timelock simulation
      // For simplicity, we'll directly grant using admin role
      const DEFAULT_ADMIN_ROLE = await accessController.DEFAULT_ADMIN_ROLE();
      await accessController.connect(admin).grantRole(EXECUTOR_ROLE, executor.address);

      // Now revoke
      await accessController.connect(admin).revokeExecutorRole(executor.address);
      expect(await accessController.isExecutor(executor.address)).to.be.false;
    });

    it("Should not allow non-admin to grant roles", async function () {
      await expect(
        accessController.connect(user1).grantGuardianRole(guardian.address)
      ).to.be.reverted;
    });
  });

  describe("Timelock Functions", function () {
    it("Should only allow timelock to grant executor role", async function () {
      await expect(
        accessController.connect(admin).grantExecutorRole(executor.address)
      ).to.be.revertedWithCustomError(accessController, "OnlyTimelock");
    });

    it("Should only allow timelock to update timelock address", async function () {
      const newTimelock = ethers.Wallet.createRandom().address;
      await expect(
        accessController.connect(admin).setTimelock(newTimelock)
      ).to.be.revertedWithCustomError(accessController, "OnlyTimelock");
    });
  });

  describe("Role Checks", function () {
    beforeEach(async function () {
      await accessController.connect(admin).grantGuardianRole(guardian.address);
      await accessController.connect(admin).grantStrategistRole(strategist.address);
    });

    it("Should correctly report admin status", async function () {
      expect(await accessController.isAdmin(admin.address)).to.be.true;
      expect(await accessController.isAdmin(user1.address)).to.be.false;
    });

    it("Should correctly report guardian status", async function () {
      expect(await accessController.isGuardian(guardian.address)).to.be.true;
      expect(await accessController.isGuardian(user1.address)).to.be.false;
    });

    it("Should correctly report strategist status", async function () {
      expect(await accessController.isStrategist(strategist.address)).to.be.true;
      expect(await accessController.isStrategist(user1.address)).to.be.false;
    });
  });
});

describe("Timelock", function () {
  let timelock: Timelock;
  let admin: HardhatEthersSigner;
  let user1: HardhatEthersSigner;

  const TWO_DAYS = 48 * 60 * 60;
  const PROPOSER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("PROPOSER_ROLE"));
  const EXECUTOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("EXECUTOR_ROLE"));
  const CANCELLER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("CANCELLER_ROLE"));

  beforeEach(async function () {
    [admin, user1] = await ethers.getSigners();

    const TimelockFactory = await ethers.getContractFactory("Timelock");
    timelock = await TimelockFactory.deploy(admin.address, TWO_DAYS);
    await timelock.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set correct delay", async function () {
      expect(await timelock.delay()).to.equal(TWO_DAYS);
    });

    it("Should grant roles to admin", async function () {
      expect(await timelock.hasRole(PROPOSER_ROLE, admin.address)).to.be.true;
      expect(await timelock.hasRole(EXECUTOR_ROLE, admin.address)).to.be.true;
      expect(await timelock.hasRole(CANCELLER_ROLE, admin.address)).to.be.true;
    });

    it("Should revert with delay out of bounds", async function () {
      const TimelockFactory = await ethers.getContractFactory("Timelock");

      // Too short (less than 48 hours)
      await expect(
        TimelockFactory.deploy(admin.address, 1000)
      ).to.be.revertedWithCustomError(TimelockFactory, "DelayOutOfBounds");

      // Too long (more than 30 days)
      const THIRTY_ONE_DAYS = 31 * 24 * 60 * 60;
      await expect(
        TimelockFactory.deploy(admin.address, THIRTY_ONE_DAYS)
      ).to.be.revertedWithCustomError(TimelockFactory, "DelayOutOfBounds");
    });
  });

  describe("Queue Transaction", function () {
    const target = ethers.Wallet.createRandom().address;
    const value = 0n;
    const data = "0x";

    it("Should queue a transaction", async function () {
      const eta = (await time.latest()) + TWO_DAYS + 100;

      await timelock.connect(admin).queueTransaction(target, value, data, eta);

      const txHash = await timelock.getTransactionHash(target, value, data, eta);
      expect(await timelock.queuedTransactions(txHash)).to.be.true;
    });

    it("Should emit TransactionQueued event", async function () {
      const eta = (await time.latest()) + TWO_DAYS + 100;

      const txHash = await timelock.getTransactionHash(target, value, data, eta);

      await expect(timelock.connect(admin).queueTransaction(target, value, data, eta))
        .to.emit(timelock, "TransactionQueued")
        .withArgs(txHash, target, value, data, eta);
    });

    it("Should revert if ETA too soon", async function () {
      const eta = (await time.latest()) + 1000; // Less than delay

      await expect(
        timelock.connect(admin).queueTransaction(target, value, data, eta)
      ).to.be.revertedWithCustomError(timelock, "ETATooSoon");
    });

    it("Should revert if transaction already queued", async function () {
      const eta = (await time.latest()) + TWO_DAYS + 100;

      await timelock.connect(admin).queueTransaction(target, value, data, eta);

      await expect(
        timelock.connect(admin).queueTransaction(target, value, data, eta)
      ).to.be.revertedWithCustomError(timelock, "TransactionAlreadyQueued");
    });

    it("Should revert if not proposer", async function () {
      const eta = (await time.latest()) + TWO_DAYS + 100;

      await expect(
        timelock.connect(user1).queueTransaction(target, value, data, eta)
      ).to.be.reverted;
    });
  });

  describe("Execute Transaction", function () {
    let mockContract: any;
    const value = 0n;

    beforeEach(async function () {
      // Deploy a simple contract to call
      const MockUSDCFactory = await ethers.getContractFactory("MockUSDC");
      mockContract = await MockUSDCFactory.deploy();
      await mockContract.waitForDeployment();
    });

    it("Should execute a queued transaction", async function () {
      const target = await mockContract.getAddress();
      const data = mockContract.interface.encodeFunctionData("mint", [admin.address, 1000n]);
      const eta = (await time.latest()) + TWO_DAYS + 100;

      // Queue
      await timelock.connect(admin).queueTransaction(target, value, data, eta);

      // Advance time
      await time.increaseTo(eta);

      // Execute
      await timelock.connect(admin).executeTransaction(target, value, data, eta);

      // Verify execution
      expect(await mockContract.balanceOf(admin.address)).to.equal(1000n);
    });

    it("Should emit TransactionExecuted event", async function () {
      const target = await mockContract.getAddress();
      const data = mockContract.interface.encodeFunctionData("mint", [admin.address, 1000n]);
      const eta = (await time.latest()) + TWO_DAYS + 100;

      await timelock.connect(admin).queueTransaction(target, value, data, eta);
      await time.increaseTo(eta);

      const txHash = await timelock.getTransactionHash(target, value, data, eta);

      await expect(timelock.connect(admin).executeTransaction(target, value, data, eta))
        .to.emit(timelock, "TransactionExecuted")
        .withArgs(txHash, target, value, data);
    });

    it("Should revert if transaction not queued", async function () {
      const target = await mockContract.getAddress();
      const data = mockContract.interface.encodeFunctionData("mint", [admin.address, 1000n]);
      const eta = (await time.latest()) + TWO_DAYS + 100;

      // Don't queue, try to execute directly
      await expect(
        timelock.connect(admin).executeTransaction(target, value, data, eta)
      ).to.be.revertedWithCustomError(timelock, "TransactionNotQueued");
    });

    it("Should revert if transaction not ready", async function () {
      const target = await mockContract.getAddress();
      const data = mockContract.interface.encodeFunctionData("mint", [admin.address, 1000n]);
      const eta = (await time.latest()) + TWO_DAYS + 100;

      await timelock.connect(admin).queueTransaction(target, value, data, eta);

      // Don't advance time, try to execute
      await expect(
        timelock.connect(admin).executeTransaction(target, value, data, eta)
      ).to.be.revertedWithCustomError(timelock, "TransactionNotReady");
    });

    it("Should revert if transaction expired", async function () {
      const target = await mockContract.getAddress();
      const data = mockContract.interface.encodeFunctionData("mint", [admin.address, 1000n]);
      const eta = (await time.latest()) + TWO_DAYS + 100;

      await timelock.connect(admin).queueTransaction(target, value, data, eta);

      // Advance past grace period (14 days)
      const GRACE_PERIOD = 14 * 24 * 60 * 60;
      await time.increaseTo(eta + GRACE_PERIOD + 1);

      await expect(
        timelock.connect(admin).executeTransaction(target, value, data, eta)
      ).to.be.revertedWithCustomError(timelock, "TransactionExpired");
    });
  });

  describe("Cancel Transaction", function () {
    const target = ethers.Wallet.createRandom().address;
    const value = 0n;
    const data = "0x";

    it("Should cancel a queued transaction", async function () {
      const eta = (await time.latest()) + TWO_DAYS + 100;

      await timelock.connect(admin).queueTransaction(target, value, data, eta);
      await timelock.connect(admin).cancelTransaction(target, value, data, eta);

      const txHash = await timelock.getTransactionHash(target, value, data, eta);
      expect(await timelock.queuedTransactions(txHash)).to.be.false;
    });

    it("Should emit TransactionCancelled event", async function () {
      const eta = (await time.latest()) + TWO_DAYS + 100;

      await timelock.connect(admin).queueTransaction(target, value, data, eta);

      const txHash = await timelock.getTransactionHash(target, value, data, eta);

      await expect(timelock.connect(admin).cancelTransaction(target, value, data, eta))
        .to.emit(timelock, "TransactionCancelled")
        .withArgs(txHash);
    });

    it("Should revert if transaction not queued", async function () {
      const eta = (await time.latest()) + TWO_DAYS + 100;

      await expect(
        timelock.connect(admin).cancelTransaction(target, value, data, eta)
      ).to.be.revertedWithCustomError(timelock, "TransactionNotQueued");
    });
  });

  describe("Set Delay", function () {
    it("Should only allow self to set delay", async function () {
      const NEW_DELAY = 72 * 60 * 60; // 3 days

      await expect(
        timelock.connect(admin).setDelay(NEW_DELAY)
      ).to.be.revertedWith("Timelock: only self");
    });

    it("Should update delay through queued transaction", async function () {
      const NEW_DELAY = 72 * 60 * 60; // 3 days
      const target = await timelock.getAddress();
      const data = timelock.interface.encodeFunctionData("setDelay", [NEW_DELAY]);
      const value = 0n;
      const eta = (await time.latest()) + TWO_DAYS + 100;

      await timelock.connect(admin).queueTransaction(target, value, data, eta);
      await time.increaseTo(eta);
      await timelock.connect(admin).executeTransaction(target, value, data, eta);

      expect(await timelock.delay()).to.equal(NEW_DELAY);
    });
  });

  describe("Receive ETH", function () {
    it("Should accept ETH", async function () {
      const amount = ethers.parseEther("1");
      await admin.sendTransaction({
        to: await timelock.getAddress(),
        value: amount,
      });

      expect(await ethers.provider.getBalance(await timelock.getAddress())).to.equal(amount);
    });
  });
});
