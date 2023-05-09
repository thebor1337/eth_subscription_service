import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { TestStandaloneSubscriptionService } from "../typechain-types";

import type {
    BaseContract,
    BigNumber,
    BigNumberish,
    BytesLike,
    CallOverrides,
    ContractTransaction,
    Overrides,
    PayableOverrides,
    PopulatedTransaction,
    Signer,
    utils,
} from "ethers";

describe("StandaloneSubscriptionService", () => {
    // async function deploy() {
    //     const [owner, user1, user2] = await ethers.getSigners();
    //     const ServiceFactory = await ethers.getContractFactory("StandaloneSubscriptionService");
    //     const service = await ServiceFactory.deploy();

    //     return { service, owner, user1, user2 };
    // }
    
    async function deployTest() {
        const [owner, user1, user2] = await ethers.getSigners();
        const TestServiceFactory = await ethers.getContractFactory("TestStandaloneSubscriptionService");
        const testService = await TestServiceFactory.deploy();

        return { testService, owner, user1, user2 };
    }

    describe("Plan operations", () => {
        let testService: TestStandaloneSubscriptionService;
        let owner: Signer;
        let user1: Signer;

        beforeEach(async () => {
            const deployment = await loadFixture(deployTest);
            testService = deployment.testService;
            owner = deployment.owner;
            user1 = deployment.user1;
        });

        describe("addPlan()", () => {

            async function testAddPlan(
                caller: Signer,
                period: BigNumberish,
                trial: BigNumberish,
                rate: BigNumberish,
                chargeDiscount: BigNumberish
            ) {
                await testService.addPlan(period, trial, rate, chargeDiscount);
                const plan = await testService.connect(caller).getPlan(0);

                expect(plan.period).to.equal(period);
                expect(plan.trial).to.equal(trial);
                expect(plan.rate).to.equal(rate);
                expect(plan.chargeDiscount).to.equal(chargeDiscount);
                expect(plan.closed).to.equal(false);
                expect(plan.disabledAt).to.equal(0);
            }

            describe("if data is correct", () => {
                it("should add a plan", async () => {
                    await testAddPlan(owner, 30 * 24 * 60 * 60, 24 * 60 * 60, 100, 5);
                });
            });

            describe("if data is not correct", () => {
                it("should revert when period is 0", async () => {
                    await expect(
                        testAddPlan(owner, 0, 100, 100, 5)
                    ).to.be.revertedWith("period cannot be zero");
                });
                it("should revert when rate is 0", async () => {
                    await expect(
                        testAddPlan(owner, 30 * 24 * 60 * 60, 100, 0, 5)
                    ).to.be.revertedWith("rate cannot be zero");
                });
                it("should revert when chargeDiscount is greater than 100", async () => {
                    await expect(
                        testAddPlan(owner, 30 * 24 * 60 * 60, 100, 100, 101)
                    ).to.be.revertedWith("charge discount must be in range [0;100]");
                });
            });
        });
    });
});