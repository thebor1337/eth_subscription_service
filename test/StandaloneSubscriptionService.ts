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

const DAY = 24 * 60 * 60;

describe("StandaloneSubscriptionService", () => {
    async function deployTest() {
        const [owner, user1, user2] = await ethers.getSigners();
        const ServiceFactory = await ethers.getContractFactory("TestStandaloneSubscriptionService");
        const service = await ServiceFactory.deploy();

        return { service, owner, user1, user2 };
    }

    describe("Plan", () => {
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

    describe("Math", () => {
        let service: TestStandaloneSubscriptionService;
        
        beforeEach(async () => {
            const deployment = await loadFixture(deployTest);
            service = deployment.service;
        });

        describe("_calcCountedPeriods()", () => {
            const startedAt = getUtcTimestamp();
            const period = 7 * DAY;

            describe("when subscription is not started", () => {
                it("should be 0 (+1 if countNext)", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, startedAt - DAY, 0, 0, period, false)).to.equal(0);
                    expect(await service.testCalcCountedPeriods(startedAt, startedAt - DAY, 0, 0, period, true)).to.equal(1);
                });
            });

            describe("while the 1st period", () => {
                const periodStartedAt = startedAt;

                it("should be 1 when subscription's not interrupted (subscription not cancelled and plan not disabled)", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 0, period, false)).to.equal(1);
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 0, period, true)).to.equal(2);
                });

                it("should be 1 when subscription's interrupted in the current period", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, startedAt + 3 * DAY, period, false)).to.equal(1);
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, startedAt + 3 * DAY, 0, period, false)).to.equal(1);
                });

                it("should be 0 when subscription's interrupted the previous period", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, startedAt - DAY, period, false)).to.equal(0);
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, startedAt - DAY, 0, period, false)).to.equal(0);
                });
            });

            describe("while the 2nd period", () => {
                const periodStartedAt = startedAt + period;

                it("should be 2 when subscription's not interrupted", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 0, period, false)).to.equal(2);
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 0, period, true)).to.equal(3);
                });

                // TODO проверить когда maxUntilAt = periodStartedAt (без добавочных)

                it("should be 2 when subscription's interrupted in the current period", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, periodStartedAt + 3 * DAY, period, false)).to.equal(2);
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, periodStartedAt + 3 * DAY, 0, period, false)).to.equal(2);
                });

                it("should be 1 when subscription's interrupted in the previous period", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, startedAt + 3 * DAY, period, false)).to.equal(1);
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, startedAt + 3 * DAY, 0, period, false)).to.equal(1);
                });
            });
        });

        describe("_calcDebtPeriods()", () => {
            const startedAt = getUtcTimestamp();
            const period = 7 * DAY;
            const rate = 100;

            describe("when subscription is not started", () => {
                it("should be 0", async () => {
                    expect(await service.testCalcDebtPeriods(startedAt, startedAt - DAY, 0, 0, 0, period, rate, 0)).to.equal(0);
                });
            });

            describe("while the 1st period", () => {
                const periodStartedAt = startedAt;
                it("should be 0 when charged", async () => {
                    expect(await service.testCalcDebtPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 1, 0, period, rate, 0)).to.equal(0);
                });

                it("should 1 when not charged and have enough balance", async () => {
                    expect(await service.testCalcDebtPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 0, 0, period, rate, rate)).to.equal(1);
                });

                it("should be 0 when not charged and have not enough balance", async () => {
                    expect(await service.testCalcDebtPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 0, 0, period, rate, rate - 1)).to.equal(0);
                });
            });

            describe("while the 2nd period", () => {
                const periodStartedAt = startedAt + period;
                it("should be 0 when charged for two periods", async () => {
                    expect(await service.testCalcDebtPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 2, 0, period, rate, 0)).to.equal(0);
                });

                it("should be 1 when not charged for the current period and have enough balance", async () => {
                    expect(await service.testCalcDebtPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 1, 0, period, rate, rate)).to.equal(1);
                });

                it("should be 0 when not charged for the current period and have not enough balance", async () => {
                    expect(await service.testCalcDebtPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 1, 0, period, rate, rate - 1)).to.equal(0);
                });

                it("should be 2 when not charged for both periods and have enough balance", async () => {
                    expect(await service.testCalcDebtPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 0, 0, period, rate, rate * 2)).to.equal(2);
                });

                it("should be 1 when not charged for both periods and have balance enough only for 1 period", async () => {
                    expect(await service.testCalcDebtPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 0, 0, period, rate, rate)).to.equal(1);
                });

                it("should be 0 when not charged for both periods and have not enough balance", async () => {
                    expect(await service.testCalcDebtPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 0, 0, period, rate, rate - 1)).to.equal(0);
                });
            });
        });

        describe("_calcFundedUntil()", () => {
            const startedAt = getUtcTimestamp();
            const period = 7 * DAY;
            const rate = 100;

            describe("have no charged periods", () => {
                it("should be {startedAt} when balance is not enough for 1 period", async () => {
                    expect(await service.testCalcFundedUntil(startedAt, 0, rate - 1, rate, period)).to.equal(startedAt);
                });

                it("should be {startedAt + 1 period} period when balance is enough exact for 1 period", async () => {
                    expect(await service.testCalcFundedUntil(startedAt, 0, rate, rate, period)).to.equal(startedAt + period);
                });

                it("should be {startedAt + 1 period} period when balance is enough for 1 period + extra", async () => {
                    expect(await service.testCalcFundedUntil(startedAt, 0, rate + 1, rate, period)).to.equal(startedAt + period);
                });

                it("should be {startedAt + 2 periods} when balance is enough for 2 periods", async () => {
                    expect(await service.testCalcFundedUntil(startedAt, 0, rate * 2, rate, period)).to.equal(startedAt + 2 * period);
                });

                it("should be {startedAt + 10 periods} when balance is enough for 10 periods", async () => {
                    expect(await service.testCalcFundedUntil(startedAt, 0, rate * 10, rate, period)).to.equal(startedAt + 10 * period);
                });
            });

            describe("have charged periods", () => {
                it("should be {startedAt + 1 period} when charged for 1 period and have no enough balance for extra periods", async () => {
                    expect(await service.testCalcFundedUntil(startedAt, 1, rate - 1, rate, period)).to.equal(startedAt + period);
                });

                it("should be {startedAt + 5 charged periods + 3 period} when charged for 5 periods and have enough balance for 3 periods", async () => {
                    expect(await service.testCalcFundedUntil(startedAt, 5, rate * 3, rate, period)).to.equal(startedAt + 5 * period + 3 * period);
                });
            });
        });

        describe("_calcCharge()", () => {
            const rate = 101;

            describe("without discount", () => {
                it("should no charge when no periods", async () => {
                    const [amountToCharge, adjustedRate] = await service.testCalcCharge(0, 0, rate);
                    expect(amountToCharge).to.equal(0);
                    expect(adjustedRate).to.equal(rate);
                });

                it("should charge for 1 period correctly", async () => {
                    const [amountToCharge, adjustedRate] = await service.testCalcCharge(1, 0, rate);
                    expect(amountToCharge).to.equal(rate);
                    expect(adjustedRate).to.equal(rate);
                });

                it("should charge for 2 periods correctly", async () => {
                    const [amountToCharge, adjustedRate] = await service.testCalcCharge(2, 0, rate);
                    expect(amountToCharge).to.equal(rate * 2);
                    expect(adjustedRate).to.equal(rate);
                });
            });

            describe("with discount", () => {
                it("should charge for 1 period correctly with 10% discount", async () => {
                    const [amountToCharge, adjustedRate] = await service.testCalcCharge(1, 10, rate);
                    const desiredRate = Math.floor(rate * 0.9);
                    expect(amountToCharge).to.equal(desiredRate);
                    expect(adjustedRate).to.equal(desiredRate);
                });

                it("should charge for 2 periods correctly with 7% discount", async () => {
                    const [amountToCharge, adjustedRate] = await service.testCalcCharge(2, 7, rate);
                    const desiredRate = Math.floor(rate * 0.93);
                    expect(amountToCharge).to.equal(desiredRate * 2);
                    expect(adjustedRate).to.equal(desiredRate);
                });
            });
        });
    });

    describe("Funds managing", () => {
        let service: TestStandaloneSubscriptionService;
        let owner: SignerWithAddress;
        let user1: SignerWithAddress;

        beforeEach(async () => {
            const deployment = await loadFixture(deployTest);
            service = deployment.service;
            owner = deployment.owner;
            user1 = deployment.user1;
        });

        describe("balanceOf()", () => {
            beforeEach(async () => {
                await service.dummyDeposit(user1.address, 100);
            });

            it("should return 0 for not deposited account", async () => {
                expect(await service.balanceOf(owner.address)).to.equal(0);
            });

            it("should return balance for deposited account", async () => {
                expect(await service.balanceOf(user1.address)).to.equal(100);
            });
        });

        describe("_decreaseBalance()", () => {
            beforeEach(async () => {
                await service.dummyDeposit(user1.address, 100);
            });

            it("should decrease balance of deposited account", async () => {
                await service.testDecreaseBalance(user1.address, 70);
                expect(await service.balanceOf(user1.address)).to.equal(30);
            });

            it("should revert when balance is not enough", async () => {
                await expect(service.testDecreaseBalance(user1.address, 101))
                .to.be.revertedWithCustomError(service, "InsufficientBalance")
                .withArgs(100, 101);
            });
        });

        describe("_transfer()", () => {
            beforeEach(async () => {
                await service.connect(user1).dummyDeposit(user1.address, 100, {value: 100});
            });

            it("should transfer from contract to the given address", async () => {
                const tx = await service.testTransfer(owner.address, 70);
                expect(tx).to.changeEtherBalances([service, owner], [-70, 70]);
            });

            it("should dummy revert when failed", async () => {
                await expect(service.testTransfer(owner.address, 101)).to.be.reverted;
            });
        });

        describe("_pay()", () => {
            it("should increase 'paidAmount'", async () => {
                await service.testPay(100);
                expect(await service.paidAmount()).to.equal(100);
                await service.testPay(200);
                expect(await service.paidAmount()).to.equal(300);
            });
        });
    });

    describe("Subscription", () => {
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
        });
    });

    describe("Deposit", () => {
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

        });
    });

    describe("Withdraw", () => {
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

        });
    });
});