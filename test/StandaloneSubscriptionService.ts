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

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

function getUtcTimestamp() {
    return Math.floor(Date.now() / 1000);
}

describe("StandaloneSubscriptionService", () => {
    async function deployTest() {
        const [owner, user1, user2] = await ethers.getSigners();
        const ServiceFactory = await ethers.getContractFactory("TestStandaloneSubscriptionService");
        const service = await ServiceFactory.deploy();

        return { service, owner, user1, user2 };
    }

    describe("Plan operations", () => {
        let service: TestStandaloneSubscriptionService;
        let owner: SignerWithAddress;
        let user1: SignerWithAddress;

        beforeEach(async () => {
            const deployment = await loadFixture(deployTest);
            service = deployment.service;
            owner = deployment.owner;
            user1 = deployment.user1;
        });

        describe("addPlan()", () => {

            it("should revert when caller is not an owner", async () => {
                await expect(
                    service.connect(user1).addPlan(1, 1, 1, 0)
                ).to.be.revertedWith("Ownable: caller is not the owner");
            });

            describe("if data is correct", () => {
                it("should add a plan", async () => {
                    const period = 30 * 24 * 60 * 60;
                    const trial = 24 * 60 * 60;
                    const rate = 100;
                    const chargeDiscount = 5;

                    await service.addPlan(period, trial, rate, chargeDiscount);

                    const plan = await service.getPlan(0);

                    expect(plan.period).to.equal(period);
                    expect(plan.trial).to.equal(trial);
                    expect(plan.rate).to.equal(rate);
                    expect(plan.chargeDiscount).to.equal(chargeDiscount);
                    expect(plan.closed).to.equal(false);
                    expect(plan.disabledAt).to.equal(0);
                });

                it("should emits PlanAdded event with correct planIdx", async () => {
                    await service.addPlan(30 * 24 * 60 * 60, 24 * 60 * 60, 100, 5);
                    await expect(
                        service.addPlan(30 * 24 * 60 * 60, 24 * 60 * 60, 100, 5)
                    ).to.emit(service, "PlanAdded").withArgs(1);
                });
            });

            describe("if data is not correct", () => {
                it("should revert when period is 0", async () => {
                    await expect(
                        service.addPlan(0, 100, 100, 5)
                    ).to.be.revertedWith("period cannot be zero");
                });
                it("should revert when rate is 0", async () => {
                    await expect(
                        service.addPlan(30 * 24 * 60 * 60, 100, 0, 5)
                    ).to.be.revertedWith("rate cannot be zero");
                });
                it("should revert when chargeDiscount is greater than 100", async () => {
                    await expect(
                        service.addPlan(30 * 24 * 60 * 60, 100, 100, 101)
                    ).to.be.revertedWith("charge discount must be in range [0;100]");
                });
            });
        });

        describe("internal functions", () => {
            beforeEach(async () => {
                await service.addPlan(30 * 24 * 60 * 60, 24 * 60 * 60, 100, 5);
            });

            describe("_planClosed()", async() => {
                it("should return false when plan is not closed", async () => {
                    expect(await service.testPlanClosed(0)).to.equal(false);
                });
                it("should return true when plan is closed", async () => {
                    await service.closePlan(0);
                    expect(await service.testPlanClosed(0)).to.equal(true);
                });
            });

            describe("_planDisabled()", async() => {
                it("should return false when plan is not disabled", async () => {
                    expect(await service.testPlanDisabled(0)).to.equal(false);
                });
                it("should return true when plan is disabled", async () => {
                    await service.disablePlan(0);
                    expect(await service.testPlanDisabled(0)).to.equal(true);
                });
            });
        });

        describe("disablePlan()", () => {
            beforeEach(async () => {
                await service.addPlan(30 * 24 * 60 * 60, 24 * 60 * 60, 100, 5);
            });

            it("should revert when caller is not an owner", async () => {
                await expect(
                    service.connect(user1).disablePlan(0)
                ).to.be.revertedWith("Ownable: caller is not the owner");
            });

            it("should revert when plan is already disabled", async () => {
                await service.disablePlan(0);
                await expect(
                    service.disablePlan(0)
                ).to.be.revertedWith("plan already disabled");
            });

            it("should disable a plan", async () => {
                await service.disablePlan(0);
                expect(await service.testPlanDisabled(0)).to.equal(true);
            });

            it("should emit PlanDisabled event with correct planIdx", async () => {
                await expect(
                    service.disablePlan(0)
                ).to.emit(service, "PlanDisabled").withArgs(0);
            });
        });

        describe("closePlan()", () => {
            beforeEach(async () => {
                await service.addPlan(30 * 24 * 60 * 60, 24 * 60 * 60, 100, 5);
            });

            it("should revert when caller is not an owner", async () => {
                await expect(
                    service.connect(user1).closePlan(0)
                ).to.be.revertedWith("Ownable: caller is not the owner");
            });

            it("should revert when plan is already closed", async () => {
                await service.closePlan(0);
                await expect(
                    service.closePlan(0)
                ).to.be.revertedWith("plan already closed");
            });

            it("should close a plan", async () => {
                await service.closePlan(0);
                expect(await service.testPlanClosed(0)).to.equal(true);
            });

            it("should emit PlanClosed event with correct planIdx", async () => {
                await expect(
                    service.closePlan(0)
                ).to.emit(service, "PlanClosed").withArgs(0);
            });
        });

        describe("openPlan()", () => {
            beforeEach(async () => {
                await service.addPlan(30 * 24 * 60 * 60, 24 * 60 * 60, 100, 5);
                await service.closePlan(0);
            });

            it("should revert when caller is not an owner", async () => {
                await expect(
                    service.connect(user1).openPlan(0)
                ).to.be.revertedWith("Ownable: caller is not the owner");
            });

            it("should revert when plan is already open", async () => {
                await service.openPlan(0);
                await expect(
                    service.openPlan(0)
                ).to.be.revertedWith("plan not closed");
            });

            it("should open a plan", async () => {
                await service.openPlan(0);
                expect(await service.testPlanClosed(0)).to.equal(false);
            });

            it("should emit PlanOpened event with correct planIdx", async () => {
                await expect(
                    service.openPlan(0)
                ).to.emit(service, "PlanOpened").withArgs(0);
            });
        });
    });

    describe("Subscription operations", () => {
        let service: TestStandaloneSubscriptionService;
        let owner: SignerWithAddress;
        let user1: SignerWithAddress;
        
        beforeEach(async () => {
            const deployment = await loadFixture(deployTest);
            service = deployment.service;
            owner = deployment.owner;
            user1 = deployment.user1;
        });

        describe("internal functions", () => {
            describe("_subscribe()", () => {
                it("should subscribe without trial period", async () => {
                    const timestamp = getUtcTimestamp() + 1;
                    const [account, planIdx, trial] = [user1.address, 1, 0];

                    await time.setNextBlockTimestamp(timestamp);
                    await service.testSubscribe(account, planIdx, trial);

                    const subscription = await service.subscriptionOf(account);

                    expect(subscription.planIdx).to.equal(planIdx);
                    expect(subscription.createdAt).to.equal(timestamp);
                    expect(subscription.startedAt).to.equal(timestamp);
                    expect(subscription.chargedPeriods).to.equal(0);
                    expect(subscription.cancelledAt).to.equal(0);
                });

                it("should subscribe with trial period", async () => {
                    const timestamp = getUtcTimestamp() + 1;
                    const [account, planIdx, trial] = [user1.address, 1, 24 * 60 * 60];

                    await time.setNextBlockTimestamp(timestamp);
                    await service.testSubscribe(account, planIdx, trial);

                    const subscription = await service.subscriptionOf(account);

                    expect(subscription.planIdx).to.equal(planIdx);
                    expect(subscription.createdAt).to.equal(timestamp);
                    expect(subscription.startedAt).to.equal(timestamp + trial);
                    expect(subscription.chargedPeriods).to.equal(0);
                    expect(subscription.cancelledAt).to.equal(0);
                });
            });

            describe("state functions", () => {
                describe("when not subscribed", () => {
                    describe("_subscribed()", () => {
                        it("should return false", async () => {
                            expect(await service.testSubscribed(user1.address)).to.equal(false);
                        });
                    });
                });

                describe("when subscribed", () => {
                    let account: string;

                    beforeEach(async () => {
                        account = user1.address;
                        await service.testSubscribe(account, 0, 0);
                    });

                    describe("_subscribed()", () => {
                        it("should return true", async () => {
                            expect(await service.testSubscribed(account)).to.equal(true);
                        });
                    });

                    describe("_cancelled()", () => {
                        it("should return false when not cancelled", async () => {
                            expect(await service.testCancelled(account)).to.equal(false);
                        });

                        it("should return true when cancelled", async () => {
                            await service.dummyCancel(account, getUtcTimestamp());
                            expect(await service.testCancelled(account)).to.equal(true);
                        });
                    });
                });
            });

            describe("calculate functions", () => {
                describe("_calcCompletePeriods()", async () => {
                    const timestamp = getUtcTimestamp();
                    const period = 24 * 60 * 60;

                    it("should return 0 when subscription is not started", async () => {
                        expect(await service.testCalcCompletePeriods(timestamp, timestamp - 100, 0, 0, period, false)).to.equal(0);
                    });

                    it("should return 1 when passsed less than a period", async () => {
                        expect(await service.testCalcCompletePeriods(timestamp, timestamp, 0, 0, period, false)).to.equal(1);
                    });

                    // it("should return 0 when subscription is cancelled", async () => {
                    //     expect(await service.testCalcCompletePeriods(createdAt, startedAt, period, chargedPeriods, cancelledAt + 1)).to.equal(0);
                    // });

                    // it("should return 0 when subscription is not charged", async () => {
                    //     expect(await service.testCalcCompletePeriods(createdAt, startedAt, period, chargedPeriods + 1, cancelledAt)).to.equal(0);
                    // });

                    // it("should return 0 when subscription is charged but not completed", async () => {
                    //     expect(await service.testCalcCompletePeriods(createdAt, startedAt, period, chargedPeriods + 1, cancelledAt)).to.equal(0);
                    // });

                    // it("should return 1 when subscription is charged and completed", async () => {
                    //     expect(await service.testCalcCompletePeriods(createdAt, startedAt, period, chargedPeriods + 1, cancelledAt)).to.equal(0);
                    // });
                });
            });
        });
    });
});