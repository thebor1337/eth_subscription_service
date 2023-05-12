import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { TestStandaloneSubscriptionService } from "../typechain-types";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

// TODO больше тестов для калькуляции

function getUtcTimestamp() {
    return Math.floor(Date.now() / 1000);
}

const DAY = 24 * 60 * 60;

describe("StandaloneSubscriptionService", () => {
    async function deploy() {
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
            const deployment = await loadFixture(deploy);
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
            const deployment = await loadFixture(deploy);
            service = deployment.service;
        });

        describe("_calcCountedPeriods()", () => {
            const startedAt = getUtcTimestamp();
            const period = 7 * DAY;

            describe("when subscription is not started", () => {
                it("should be 0 (+1 if countNext)", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, startedAt - DAY, 0, 0, period)).to.equal(0);
                });
            });

            describe("while the 1st period", () => {
                const periodStartedAt = startedAt;

                it("should be 1 when subscription's not interrupted (subscription not cancelled and plan not disabled)", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 0, period)).to.equal(1);
                });

                it("should be 1 when subscription's interrupted in the current period", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, startedAt + 3 * DAY, period)).to.equal(1);
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, startedAt + 3 * DAY, 0, period)).to.equal(1);
                });

                it("should be 0 when subscription's interrupted the previous period", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, startedAt - DAY, period)).to.equal(0);
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, startedAt - DAY, 0, period)).to.equal(0);
                });
            });

            describe("while the 2nd period", () => {
                const periodStartedAt = startedAt + period;

                it("should be 2 when subscription's not interrupted", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, 0, period)).to.equal(2);
                });

                // TODO проверить когда maxUntilAt = periodStartedAt (без добавочных)

                it("should be 2 when subscription's interrupted in the current period", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, periodStartedAt + 3 * DAY, period)).to.equal(2);
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, periodStartedAt + 3 * DAY, 0, period)).to.equal(2);
                });

                it("should be 1 when subscription's interrupted in the previous period", async () => {
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, 0, startedAt + 3 * DAY, period)).to.equal(1);
                    expect(await service.testCalcCountedPeriods(startedAt, periodStartedAt + 5 * DAY, startedAt + 3 * DAY, 0, period)).to.equal(1);
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
            const deployment = await loadFixture(deploy);
            service = deployment.service;
            owner = deployment.owner;
            user1 = deployment.user1;
        });

        describe("_increaseBalance()", () => {
            it("should increase balance of not deposited account", async () => {
                await service.testIncreaseBalance(user1.address, 100);
                expect(await service.balanceOf(user1.address)).to.equal(100);
            });

            it("should increase balance of deposited account", async () => {
                await service.testIncreaseBalance(user1.address, 100);
                await service.testIncreaseBalance(user1.address, 200);
                expect(await service.balanceOf(user1.address)).to.equal(300);
            });
        });

        describe("_decreaseBalance()", () => {
            beforeEach(async () => {
                await service.testIncreaseBalance(user1.address, 100);
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
            let account: SignerWithAddress;

            beforeEach(async () => {
                account = user1;
                await service.connect(account).dummyDeposit({ value: 100 });
            });

            it("should transfer from contract to the given address", async () => {
                const tx = await service.testTransfer(account.address, 70);
                expect(tx).to.changeEtherBalances([service, account], [-70, 70]);
            });

            it("should dummy revert when failed", async () => {
                await expect(service.testTransfer(account.address, 101)).to.be.reverted;
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
        let user2: SignerWithAddress;
        
        beforeEach(async () => {
            const deployment = await loadFixture(deploy);
            service = deployment.service;
            owner = deployment.owner;
            user1 = deployment.user1;
            user2 = deployment.user2;
        });

        describe("internal functions", () => {
            describe("_subscribe()", () => {
                it("should subscribe without trial period", async () => {
                    const timestamp = getUtcTimestamp() + 1;
                    const [account, planIdx, trial] = [user1.address, 1, 0];

                    await service.testSubscribe(account, timestamp, planIdx, trial);

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

                    await service.testSubscribe(account, timestamp, planIdx, trial);

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
                    let account: SignerWithAddress;

                    beforeEach(async () => {
                        account = user1;
                        await service.testSubscribe(account.address, getUtcTimestamp(), 0, 0);
                    });

                    describe("_subscribed()", () => {
                        it("should return true", async () => {
                            expect(await service.testSubscribed(account.address)).to.equal(true);
                        });
                    });

                    describe("_cancelled()", () => {
                        it("should return false when not cancelled", async () => {
                            expect(await service.testCancelled(account.address)).to.equal(false);
                        });

                        it("should return true when cancelled", async () => {
                            await service.testCancel(account.address, getUtcTimestamp(), 0);
                            expect(await service.testCancelled(account.address)).to.equal(true);
                        });
                    });
                });
            });

            describe("_cancel()", () => {
                let account: SignerWithAddress;

                beforeEach(async () => {
                    account = user1;
                    await service.testSubscribe(account.address, getUtcTimestamp(), 0, 0);
                });

                it("should cancel subscription", async () => {
                    const timestamp = getUtcTimestamp() + 10;
                    await service.testCancel(account.address, timestamp, 0);
                    const subscription = await service.subscriptionOf(account.address);
                    expect(subscription.cancelledAt).to.equal(timestamp);
                });

                it("should emit 'Cancelled' event", async () => {
                    await expect(service.testCancel(account.address, getUtcTimestamp() + 10, 0))
                    .to.emit(service, "Cancelled")
                    .withArgs(account.address, 0);
                });
            });

            describe("_restore()", () => {
                let account: SignerWithAddress;
                const subscribeTimestamp = getUtcTimestamp();

                beforeEach(async () => {
                    account = user1;
                    await service.testSubscribe(account.address, subscribeTimestamp, 0, 0);
                });

                it("should restore subscription", async () => {
                    const restoreTimestamp = subscribeTimestamp + 100;
                    await service.testCancel(user1.address, subscribeTimestamp + 50, 0);
                    await service.testRestore(user1.address, restoreTimestamp, 0);

                    const subscription = await service.subscriptionOf(user1.address);
                    expect(subscription.cancelledAt).to.equal(0);
                    expect(subscription.startedAt).to.equal(restoreTimestamp);
                    expect(subscription.chargedPeriods).to.equal(0);
                });
            });

            describe("_charge()", () => {
                let account: SignerWithAddress;
                const rate = 30;
                const initialBalance = 100;

                beforeEach(async () => {
                    account = user1;
                    await service.addPlan(DAY, 0, rate, 0);
                    await service.connect(account).dummyDeposit({value: initialBalance});
                    await service.testSubscribe(account.address, getUtcTimestamp(), 0, 0);
                });

                describe("have enough balance", () => {
                    it("should charge with paying", async () => {
                        const periodsToCharge = 2;
                        const amountToCharge = rate * periodsToCharge;

                        await service.testCharge(account.address, owner.address, 0, amountToCharge, periodsToCharge, true);
                        expect(await service.balanceOf(account.address)).to.equal(initialBalance - amountToCharge);
                        expect(await service.paidAmount()).to.equal(amountToCharge);

                        const subscription = await service.subscriptionOf(account.address);
                        expect(subscription.chargedPeriods).to.equal(periodsToCharge);
                    });

                    it("should charge without paying", async () => {
                        await service.testCharge(account.address, owner.address, 0, rate * 2, 2, false);
                        expect(await service.paidAmount()).to.equal(0);
                    });

                    it("should emits Charged event", async () => {
                        const periodsToCharge = 2;
                        const amountToCharge = rate * periodsToCharge;

                        await expect(service.testCharge(account.address, owner.address, 0, amountToCharge, periodsToCharge, true))
                        .to.emit(service, "Charged")
                        .withArgs(account.address, owner.address, 0, periodsToCharge, amountToCharge);
                    });
                });

                describe("have not enough balance", () => {
                    it("should revert", async () => {
                        const periodsToCharge = 4;
                        const amountToCharge = rate * 4;
                        await expect(service.testCharge(account.address, owner.address, 0, amountToCharge, periodsToCharge, true))
                        .to.be.revertedWithCustomError(service, "InsufficientBalance")
                        .withArgs(initialBalance, amountToCharge);
                    });
                });
            });
        });

        describe("subscriptionOf()", () => {
            describe("when not subscribed", () => {
                it("should revert", async () => {
                    await expect(service.subscriptionOf(user1.address))
                    .to.be.revertedWithCustomError(service, "NotSubscribed");
                });
            });
        });

        describe("subscribe()", () => {
            let account: SignerWithAddress;
            const rate = 30;

            beforeEach(async () => {
                account = user1;
            });

            describe("when plan unavailable", () => {
                beforeEach(async () => {
                    await service.addPlan(DAY, 0, rate, 0);
                });

                it("should revert if plan is closed", async () => {
                    await service.closePlan(0);
                    await expect(service.connect(account).subscribe(0))
                    .to.be.revertedWithCustomError(service, "PlanUnavailable");
                });

                it("should revert if plan is disabled", async () => {
                    await service.disablePlan(0);
                    await expect(service.connect(account).subscribe(0))
                    .to.be.revertedWithCustomError(service, "PlanUnavailable");
                });
            });

            describe("when not subscribed yet", () => {
                describe("when have enough balance", () => {
                    beforeEach(async () => {
                        await service.connect(account).dummyDeposit({value: 100});
                    });

                    describe("when plan has no trial period", () => {
                        beforeEach(async () => {
                            await service.addPlan(DAY, 0, rate, 0);
                        });

                        it("should subscribe and charge", async () => {
                            const oldBalance = await service.balanceOf(account.address);
                            const timestamp = getUtcTimestamp() + 10;
    
                            await time.setNextBlockTimestamp(timestamp);
                            await service.connect(account).subscribe(0);
    
                            const subscription = await service.subscriptionOf(account.address);
                            expect(subscription.planIdx).to.equal(0);
                            expect(subscription.createdAt).to.equal(timestamp);
                            expect(subscription.startedAt).to.equal(timestamp);
                            expect(subscription.chargedPeriods).to.equal(1);
                            expect(subscription.cancelledAt).to.equal(0);
    
                            expect(await service.balanceOf(account.address)).to.equal(oldBalance.sub(rate));
                        });

                        it("should emit Subscribed event", async () => {
                            const timestamp = getUtcTimestamp() + 10;
                            await time.setNextBlockTimestamp(timestamp);
    
                            await expect(service.connect(account).subscribe(0))
                            .to.emit(service, "Subscribed")
                            .withArgs(account.address, 0);
                        });

                        it("should emit Charged event", async () => {
                            const timestamp = getUtcTimestamp() + 10;
                            await time.setNextBlockTimestamp(timestamp);
    
                            await expect(service.connect(account).subscribe(0))
                            .to.emit(service, "Charged")
                            .withArgs(account.address, account.address, 0, 1, rate);
                        });
                    });

                    describe("when plan has trial period", () => {
                        const trial = DAY;

                        beforeEach(async () => {
                            await service.addPlan(2 * DAY, trial, rate, 0);
                        });

                        it("should subscribe", async () => {
                            const oldBalance = await service.balanceOf(account.address);
                            const timestamp = getUtcTimestamp() + 10;
    
                            await time.setNextBlockTimestamp(timestamp);
                            await service.connect(account).subscribe(0);
    
                            const subscription = await service.subscriptionOf(account.address);
                            expect(subscription.planIdx).to.equal(0);
                            expect(subscription.createdAt).to.equal(timestamp);
                            expect(subscription.startedAt).to.equal(timestamp + trial);
                            expect(subscription.chargedPeriods).to.equal(0);
                            expect(subscription.cancelledAt).to.equal(0);
    
                            expect(await service.balanceOf(account.address)).to.equal(oldBalance);
                        });

                        it("should emit Subscribed event", async () => {
                            const timestamp = getUtcTimestamp() + 10;
                            await time.setNextBlockTimestamp(timestamp);
    
                            await expect(service.connect(account).subscribe(0))
                            .to.emit(service, "Subscribed")
                            .withArgs(account.address, 0);
                        });
    
                        it("should not emit Charged event", async () => {
                            const timestamp = getUtcTimestamp() + 10;
                            await time.setNextBlockTimestamp(timestamp);
    
                            await expect(service.connect(account).subscribe(0))
                            .to.not.emit(service, "Charged");
                        });
                    });
                });

                describe("when have not enough balance", () => {
                    const balance = rate - 1;
                    beforeEach(async () => {
                        await service.connect(account).dummyDeposit({value: balance});
                    });

                    describe("when plan has no trial period", () => {
                        it("should revert", async () => {
                            await service.addPlan(DAY, 0, rate, 0);
                            await expect(service.connect(account).subscribe(0))
                            .to.be.revertedWithCustomError(service, "InsufficientBalance")
                            .withArgs(balance, rate);
                        });
                    });

                    describe("when plan has trial period", () => {
                        it("should revert", async () => {
                            await service.addPlan(2 * DAY, DAY, rate, 0);
                            await expect(service.connect(account).subscribe(0))
                            .to.be.revertedWithCustomError(service, "InsufficientBalance")
                            .withArgs(balance, rate);
                        });
                    });
                });
            });

            describe("when already subscribed", () => {
                beforeEach(async () => {
                    await service.connect(account).dummyDeposit({ value: 100 });
                });

                describe("to the same plan", () => {
                    it("should revert", async () => {
                        await service.addPlan(DAY, 0, rate, 0);
                        await service.connect(account).subscribe(0);
                        await expect(service.connect(account).subscribe(0))
                        .to.be.revertedWithCustomError(service, "AlreadySubscribed");
                    });
                });

                describe("to another plan", () => {
                    beforeEach(async () => {
                        await service.addPlan(DAY, 0, rate, 0);
                        await service.connect(account).subscribe(0);
                        await service.addPlan(DAY, 0, rate, 0);
                    });

                    describe("not cancelled", () => {
                        it("should revert", async () => {
                            await expect(service.connect(account).subscribe(1))
                            .to.be.revertedWithCustomError(service, "AlreadySubscribed");
                        });
                    });

                    // describe("cancelled", () => {
                    //     it("should subscribe", async () => {
                    //         await service.dummyCancel(user1.address, getUtcTimestamp() - 10);
                    //         const timestamp = getUtcTimestamp() + 10;
    
                    //         await time.setNextBlockTimestamp(timestamp);
                    //         await service.connect(user1).subscribe(1);
    
                    //         const subscription = await service.subscriptionOf(user1.address);
                    //         expect(subscription.planIdx).to.equal(1);
                    //         expect(subscription.createdAt).to.equal(timestamp);
                    //         expect(subscription.startedAt).to.equal(timestamp);
                    //         expect(subscription.cancelledAt).to.equal(0);
                    //     });
                    // });
                });
            });
        });

        describe("previewCharge", () => {
            let account: SignerWithAddress;
            const initialBalance = 100
            const period = DAY;
            const rate = 30;

            beforeEach(async () => {
                account = user1;
                await service.connect(account).dummyDeposit({value: initialBalance});
            });

            describe("when not subscribed", () => {
                it("should return blank data", async () => {
                    expect(await service.previewCharge(account.address, false))
                    .to.deep.equal([0, 0, 0]);
                });
            });

            describe("when subscribed", () => {
                describe("when plan has no discount", () => {
                    beforeEach(async () => {
                        await service.addPlan(period, 0, rate, 0);
                    });

                    describe("when no uncharged periods", () => {
                        it("should return blank data", async () => {
                            await service.connect(account).subscribe(0);
                            expect(await service.previewCharge(account.address, false))
                            .to.deep.equal([0, 0, 0]);
                        });
                    });

                    // TODO проверить везде где использовал setNextBlockTimestamp

                    describe("when have uncharged periods", () => {
                        const subscribeTimestamp = getUtcTimestamp() + 10;

                        beforeEach(async () => {
                            await time.setNextBlockTimestamp(subscribeTimestamp);
                            await service.connect(account).subscribe(0);
                        });

                        describe("exact 2 uncharged periods", () => {
                            it("should return correct data", async () => {
                                const numUnchargedPeriods = 2;
                                await time.increaseTo(subscribeTimestamp + numUnchargedPeriods * period + 10);
                                expect(await service.previewCharge(account.address, false))
                                .to.deep.equal([numUnchargedPeriods * rate, numUnchargedPeriods, rate]);
                            });
                        });
    
                        describe("more uncharged periods that balance can afford", () => {
                            it("should return correct data", async () => {
                                const currentBalance = (await service.balanceOf(account.address)).toNumber();
                                const periodsToCharge = Math.floor(currentBalance / rate);
                                const numUnchargedPeriods = periodsToCharge + 1;
                                await time.increaseTo(subscribeTimestamp + numUnchargedPeriods * period + 10);
                                expect(await service.previewCharge(account.address, false))
                                .to.deep.equal([periodsToCharge * rate, periodsToCharge, rate]);
                            });
                        });

                        describe("when try to make a discount", () => {
                            it("should not apply discount", async () => {
                                const numUnchargedPeriods = 2;
                                await time.increaseTo(subscribeTimestamp + numUnchargedPeriods * period + 10);
                                expect(await service.previewCharge(account.address, true))
                                .to.deep.equal([numUnchargedPeriods * rate, numUnchargedPeriods, rate]);
                            });
                        });
                    });
                });

                describe("when plan has a discount", () => {
                    const subscribeTimestamp = getUtcTimestamp() + 10;
                    const discount = 7;

                    beforeEach(async () => {
                        await service.addPlan(period, 0, rate, discount);
                        await time.setNextBlockTimestamp(subscribeTimestamp);
                        await service.connect(account).subscribe(0);
                    });

                    it("should apply discount", async () => {
                        const numUnchargedPeriods = 2;
                        const adjustedRate = Math.floor(rate * (100 - discount) / 100);
                        await time.increaseTo(subscribeTimestamp + numUnchargedPeriods * period + 10);
                        expect(await service.previewCharge(account.address, true))
                        .to.deep.equal([
                            Math.floor(numUnchargedPeriods * adjustedRate), 
                            numUnchargedPeriods, 
                            adjustedRate
                        ]);
                    });
                });
            });
        });

        describe("charge()", () => {
            let account: SignerWithAddress;
            const period = DAY;
            const rate = 30;
            
            beforeEach(async () => {
                account = user1;
                await service.connect(account).dummyDeposit({value: 100});
            });
            
            describe("when not subscribed", () => {
                it("should revert", async () => {
                    await expect(service.charge(account.address))
                    .to.be.revertedWithCustomError(service, "NotSubscribed");
                });
            });

            describe("when subscribed", () => {
                const subscribeTimestamp = getUtcTimestamp() + 10;

                describe("when caller is a contract owner", () => {

                    beforeEach(async () => {
                        await service.addPlan(period, 0, rate, 0);
                        await time.setNextBlockTimestamp(subscribeTimestamp);
                        await service.connect(account).subscribe(0);
                    });

                    describe("when no uncharged periods", () => {
                        it("should revert", async () => {
                            await expect(service.charge(account.address))
                            .to.be.revertedWithCustomError(service, "NothingToCharge");
                        });
                    });
    
                    describe("when have uncharged periods", () => {
                        it("should charge and emits 'Charged' event", async () => {
                            await time.increaseTo(subscribeTimestamp + period + 10);
                            await expect(service.charge(account.address))
                            .to.emit(service, "Charged")
                            .withArgs(account.address, owner.address, 0, 1, rate);
                        });
                    });
                });

                describe("when caller is not the subscription owner", () => {
                    it("should charge with discount if specified by the plan and emits correct 'Charged'", async () => {
                        const discount = 9;
                        await service.addPlan(period, 0, rate, discount);
                        await time.setNextBlockTimestamp(subscribeTimestamp);
                        await service.connect(account).subscribe(0);
                        await time.increaseTo(subscribeTimestamp + period + 10);
                        await expect(service.connect(account).charge(account.address))
                        .to.emit(service, "Charged")
                        .withArgs(account.address, account.address, 0, 1, Math.floor(rate * (100 - discount) / 100));
                    });
                });
            });
        });

        describe("charge[]", () => {
            const period = DAY;
            const rate = 30;
            
            beforeEach(async () => {
                await service.addPlan(period, 0, rate, 0);    
            });
            
            it("should revert if no accounts subscribed", async () => {
                await expect(service.chargeMany([user1.address, user2.address]))
                .to.be.revertedWithCustomError(service, "NothingToCharge");
            });

            it("should charge only uncharged accounts", async () => {
                await service.connect(user1).dummyDeposit({value: 100});
                await service.connect(user1).subscribe(0);

                await service.connect(user2).dummyDeposit({value: 100});
                await service.connect(user2).subscribe(0);

                await time.increase(period + 10);

                await service.connect(user2).charge(user2.address);

                await expect(service.chargeMany([user1.address, user2.address]))
                .to.emit(service, "Charged")
                .withArgs(user1.address, owner.address, 0, 1, rate)
            });
        });

        describe("cancel()", () => {
            let account: SignerWithAddress;
            const initialBalance = 100;

            beforeEach(async () => {
                account = user1;
                await service.connect(account).dummyDeposit({value: initialBalance});
            });

            describe("when not subscribed", () => {
                it("should revert", async () => {
                    await expect(service.connect(account).cancel())
                    .to.be.revertedWithCustomError(service, "NotSubscribed");
                });
            });

            describe("when subscribed", () => {
                const period = DAY;
                const rate = 30;
                const discount = 4;

                beforeEach(async () => {
                    await service.addPlan(period, 0, rate, discount);
                    await service.connect(account).subscribe(0);
                });

                describe("when not cancelled", () => {
                    describe("when no uncharged periods", () => {
                        it("should cancel and emits 'Cancelled' event", async () => {
                            await expect(service.connect(account).cancel())
                            .to.emit(service, "Cancelled")
                            .withArgs(account.address, 0);
                        });

                        it("should cancel and not charge", async () => {
                            await expect(service.connect(account).cancel())
                            .to.not.emit(service, "Charged");
                        });
                    });
                    
                    describe("when have uncharged periods", () => {
                        it("should cancel and emits 'Cancelled' event", async () => {
                            await time.increase(period + 10);
                            await expect(service.connect(account).cancel())
                            .to.emit(service, "Cancelled")
                            .withArgs(account.address, 0);
                        });

                        it("should cancel and charge with discount", async () => {
                            await time.increase(period + 10);
                            await expect(service.connect(account).cancel())
                            .to.emit(service, "Charged")
                            .withArgs(account.address, account.address, 0, 1, Math.floor(rate * (100 - discount) / 100));
                        });
                    });
                });

                describe("when already cancelled", () => {
                    it("should revert", async () => {
                        await service.connect(account).cancel();
                        await expect(service.connect(account).cancel())
                        .to.be.revertedWithCustomError(service, "AlreadyCancelled");
                    });
                });
            });
        });

        describe("restore()", () => {
            let account: SignerWithAddress;

            beforeEach(async () => {
                account = user1;
            });

            describe("when not subscribed", () => {
                it("should revert", async () => {
                    await expect(service.connect(account).restore())
                    .to.be.revertedWithCustomError(service, "NotSubscribed");
                });
            });

            describe("when subscribed", () => {
                const initialBalance = 30;
                const rate = 30;
                const period = DAY;

                beforeEach(async () => {
                    await service.connect(account).dummyDeposit({value: initialBalance});
                    await service.addPlan(period, 0, rate, 0);
                    await service.connect(account).subscribe(0);
                });

                describe("when not cancelled", () => {
                    it("should revert", async () => {
                        await expect(service.connect(account).restore())
                        .to.be.revertedWithCustomError(service, "NotCancelled");
                    });
                });
    
                describe("when cancelled", () => {
                    beforeEach(async () => {
                        await service.connect(account).cancel();
                    });

                    it("should revert if plan is disabled", async () => {
                        await service.disablePlan(0);
                        await expect(service.connect(account).restore())
                        .to.be.revertedWithCustomError(service, "PlanUnavailable");
                    });

                    describe("when not enough balance", () => {
                        it("should revert", async () => {
                            await expect(service.connect(account).restore())
                            .to.be.revertedWithCustomError(service, "InsufficientBalance");
                        });
                    });

                    describe("when enough balance", () => {
                        beforeEach(async () => {
                            await service.connect(account).dummyDeposit({value: 100});
                        });

                        it("should restore and emits 'Restored' event", async () => {
                            await expect(service.connect(account).restore())
                            .to.emit(service, "Restored")
                            .withArgs(account.address, 0);
                        });

                        it("should restore and charge", async () => {
                            await expect(service.connect(account).restore())
                            .to.emit(service, "Charged")
                            .withArgs(account.address, account.address, 0, 1, rate);
                        });
                    });
                });
            });
        });

        describe("reservedOf()", () => {
            let account: SignerWithAddress;
            const initialBalance = 100;

            beforeEach(async () => {
                account = user1;
                await service.connect(account).dummyDeposit({value: initialBalance});
            });

            describe("when not subscribed", () => {
                it("should return 0", async () => {
                    expect(await service.reservedOf(account.address)).to.equal(0);
                });
            });

            describe("when subscribed", () => {
                const period = DAY;
                const rate = 30;

                beforeEach(async () => {
                    await service.addPlan(period, 0, rate, 0);
                    await service.connect(account).subscribe(0);
                });

                it("should return 0 if there're no uncharged periods", async () => {
                    expect(await service.reservedOf(account.address)).to.equal(0);
                });

                it("should return correct amount if there's an uncharged period", async () => {
                    await time.increase(period + 10);
                    expect(await service.reservedOf(account.address)).to.equal(rate);
                });
            });
        });

        describe("availableBalanceOf()", () => {
            let account: SignerWithAddress;
            const initialBalance = 100;

            beforeEach(async () => {
                account = user1;
                await service.connect(account).dummyDeposit({value: initialBalance});
            });

            describe("when not subscribed", () => {
                it("should return full balance", async () => {
                    expect(await service.availableBalanceOf(account.address)).to.equal(initialBalance);
                });
            });

            describe("when subscribed", () => {
                const period = DAY;
                const rate = 30;
                const currentBalance = initialBalance - rate;

                beforeEach(async () => {
                    await service.addPlan(period, 0, rate, 0);
                    await service.connect(account).subscribe(0);
                });

                it("should return full balance if there're no uncharged periods", async () => {
                    expect(await service.availableBalanceOf(account.address)).to.equal(currentBalance);
                });

                describe("when enough balance for all uncharged periods", () => {
                    it("should return substracted amount if there's an uncharged period", async () => {
                        await time.increase(period + 10);
                        expect(await service.availableBalanceOf(account.address)).to.equal(currentBalance - rate);
                    });
                })

                describe("when not enough balance for all uncharged periods", () => {
                    const unchargedPeriods = 10;
                    const remainingBalance = currentBalance - Math.floor(currentBalance / rate) * rate;

                    it("should return correct balance a part of balance remains after charging", async () => {
                        await time.increase(unchargedPeriods * period + 10);
                        expect(await service.availableBalanceOf(account.address)).to.equal(remainingBalance);
                    });

                    it("should return 0 if there's no balance remains after charging", async () => {
                        await service.connect(account).dummyDeposit({value: rate - remainingBalance});
                        await time.increase(unchargedPeriods * period + 10);
                        expect(await service.availableBalanceOf(account.address)).to.equal(0);
                    });
                });
            });
        });

        describe("validUntil()", () => {
            let account: SignerWithAddress;
            const initialBalance = 100;

            beforeEach(async () => {
                account = user1;
                await service.connect(account).dummyDeposit({value: initialBalance});
            });

            describe("when not subscribed", () => {
                it("should revert", async () => {
                    await expect(service.validUntil(account.address))
                    .to.be.revertedWithCustomError(service, "NotSubscribed");
                });
            });

            describe("when subscribed", () => {
                const subscribeTimestamp = getUtcTimestamp() + 10;
                const period = DAY;
                const rate = 30;

                beforeEach(async () => {
                    await service.addPlan(period, 0, rate, 0);
                    await time.setNextBlockTimestamp(subscribeTimestamp);
                    await service.connect(account).subscribe(0);
                });

                describe("when subscription is interrupted", () => {
                    it("should return correct timestamp when plan is disabled", async () => {
                        await time.increase(Math.floor(period / 2));
                        await service.disablePlan(0);
                        expect(await service.validUntil(account.address)).to.equal(subscribeTimestamp + period);
                    });
    
                    it("should return correct timestamp when the subscription is cancelled", async () => {
                        await time.increase(Math.floor(period / 2));
                        await service.connect(account).cancel();
                        expect(await service.validUntil(account.address)).to.equal(subscribeTimestamp + period);
                    });
                });

                describe("when subscription is not interrupted", () => {
                    it("should return correct timestamp based on balance", async () => {
                        const currentBalance = initialBalance - rate;
                        const balanceInPeriods = Math.floor(currentBalance / rate);
                        expect(await service.validUntil(account.address))
                        .to.equal(subscribeTimestamp + period + balanceInPeriods * period);
                    });
                });
            });
        });

        describe("isValid()", () => {
            let account: SignerWithAddress;
            const initialBalance = 100;

            beforeEach(async () => {
                account = user1;
                await service.connect(account).dummyDeposit({value: initialBalance});
            });

            describe("when not subscribed", () => {
                it("should revert", async () => {
                    await expect(service.isValid(account.address))
                    .to.be.revertedWithCustomError(service, "NotSubscribed");
                });
            });

            describe("when subscribed", () => {
                const subscribeTimestamp = getUtcTimestamp() + 10;
                const period = DAY;
                const rate = 30;

                beforeEach(async () => {
                    await service.addPlan(period, 0, rate, 0);
                    await time.setNextBlockTimestamp(subscribeTimestamp);
                    await service.connect(account).subscribe(0);
                });

                describe("when subscription is interrupted", () => {

                    describe("when plan is disabled", () => {
                        it("should return true if a period when plan was disabled is not over", async () => {
                            await time.increase(Math.floor(period / 2));
                            await service.disablePlan(0);
                            await time.increase(Math.floor(period / 4));
                            expect(await service.isValid(account.address)).to.equal(true);
                        });

                        it("should return false if the period is over", async () => {
                            await time.increase(Math.floor(period / 2));
                            await service.disablePlan(0);
                            await time.increase(period);
                            expect(await service.isValid(account.address)).to.equal(false);
                        });
                    });

                    describe("when subscription is cancelled", () => {
                        it("should return true if a period when the subscription was cancelled is not over", async () => {
                            await time.increase(Math.floor(period / 2));
                            await service.connect(account).cancel();
                            await time.increase(Math.floor(period / 4));
                            expect(await service.isValid(account.address)).to.equal(true);
                        });

                        it("should return false if the period is over", async () => {
                            await time.increase(Math.floor(period / 2));
                            await service.connect(account).cancel();
                            await time.increase(period);
                            expect(await service.isValid(account.address)).to.equal(false);
                        });
                    });
                });

                describe("when subscription is not interrupted", () => {
                    it("should return true if balance is enough at the time", async () => {
                        await time.increase(period * 2 + 10);
                        expect(await service.isValid(account.address))
                        .to.equal(true);
                    });

                    it("should return false if balance is not enough at the time", async () => {
                        await time.increase(period * 5);
                        expect(await service.isValid(account.address))
                        .to.equal(false);
                    });
                });
            });
        });

        describe("nextAvailableChargeAt()", () => {
            let account: SignerWithAddress;
            const initialBalance = 100;

            beforeEach(async () => {
                account = user1;
                await service.connect(account).dummyDeposit({value: initialBalance});
            });

            describe("when not subscribed", () => {
                it("should revert", async () => {
                    await expect(service.nextAvailableChargeAt(account.address))
                    .to.be.revertedWithCustomError(service, "NotSubscribed");
                });
            });

            describe("when subscribed", () => {
                const subscribeTimestamp = getUtcTimestamp() + 10;
                const period = DAY;
                const rate = 30;

                beforeEach(async () => {
                    await service.addPlan(period, 0, rate, 0);
                    await time.setNextBlockTimestamp(subscribeTimestamp);
                    await service.connect(account).subscribe(0);
                });

                it("should return 0 if there're uncharged periods", async () => {
                    await time.increase(period);
                    expect(await service.nextAvailableChargeAt(account.address)).to.equal(0);
                });

                it("should return correct timestamp if there're no uncharged periods", async () => {
                    await time.increase(Math.floor(period / 2));
                    expect(await service.nextAvailableChargeAt(account.address))
                    .to.equal(subscribeTimestamp + period);
                });
            });
        });
    });

    describe("Deposit", () => {
        let service: TestStandaloneSubscriptionService;
        let owner: SignerWithAddress;
        let user1: SignerWithAddress;

        beforeEach(async () => {
            const deployment = await loadFixture(deploy);
            service = deployment.service;
            owner = deployment.owner;
            user1 = deployment.user1;
        });

        describe("_beforeDeposit()", () => {
            let account: SignerWithAddress;
            const initialBalance = 90;
            const period = DAY;
            const rate = 30;

            beforeEach(async () => {
                account = user1;
                await service.addPlan(period, 0, rate, 0);
                await service.connect(account).dummyDeposit({value: initialBalance});
            });
            
            describe("when not subscribed", () => {
                it("should do nothing when not subscribed", async () => {
                    await service.testBeforeDeposit(account.address, 30);
                    expect(await service.balanceOf(account.address)).to.equal(initialBalance);
                });
            });
            
            describe("when subscribed", () => {
                beforeEach(async () => {
                    await service.connect(account).subscribe(0);
                });

                it("should do nothing when subscription is cancelled", async () => {
                    await service.connect(account).cancel();
                    const currentBalance = await service.balanceOf(account.address);
                    const currentSubscriptionData = await service.subscriptionOf(account.address);
                    await service.testBeforeDeposit(account.address, 30);
                    expect(await service.balanceOf(account.address)).to.equal(currentBalance);
                    expect(await service.subscriptionOf(account.address)).to.deep.equal(currentSubscriptionData);
                });

                it("should not charge if there're no uncharged periods", async () => {
                    await time.increase(10);
                    await expect(service.testBeforeDeposit(account.address, 30))
                    .to.not.emit(service, "Charged");
                });

                it("should charge if there're uncharged periods", async () => {
                    await time.increase(period + 10);
                    await expect(service.testBeforeDeposit(account.address, 30))
                    .to.emit(service, "Charged")
                    .withArgs(account.address, account.address, 0, 1, rate);
                });

                describe("when plan is not disabled", () => {
                    it("should not restore if subscription is still funded", async () => {
                        await time.increase(period + 10);
                        await expect(service.testBeforeDeposit(account.address, 30))
                        .to.not.emit(service, "Restored");
                    });

                    it("should not restore if subscription is not funded but deposit amount is not enough", async () => {
                        await time.increase(5 * period + 10);
                        await expect(service.testBeforeDeposit(account.address, 29))
                        .to.not.emit(service, "Restored");
                    });

                    it("should restore if subscription is not funded and deposit amount is enough", async () => {
                        await time.increase(5 * period + 10);
                        await expect(service.testBeforeDeposit(account.address, 30))
                        .to.emit(service, "Restored")
                        .withArgs(account.address, 0);
                    });
                });

                describe("when plan is disabled", () => {
                    it("should not restore even if it's required", async () => {
                        await service.disablePlan(0);
                        await time.increase(5 * period + 10);
                        await expect(service.testBeforeDeposit(account.address, 30))
                        .to.not.emit(service, "Restored")
                    });
                });
            });
        });

        describe("_afterDeposit()", () => {
            it("should do nothing", async () => {
                await expect(service.testAfterDeposit(user1.address, 100));
            });
        });

        describe("deposit()", () => {
            let account: SignerWithAddress;

            beforeEach(async () => {
                account = user1;
            });

            describe("when not subscribed", () => {
                it("should deposit and emits 'Deposited' event", async () => {
                    const amount = 100;
                    await expect(service.connect(account).deposit({value: amount}))
                    .to.emit(service, "Deposit")
                    .withArgs(account.address, amount);
                    expect(await service.balanceOf(account.address)).to.equal(amount);
                });
            });

            describe("when subscribed", () => {
                const period = DAY;
                const initialBalance = 100;
                const rate = 30;

                beforeEach(async () => {
                    await service.connect(account).deposit({value: initialBalance});
                    await service.addPlan(period, 0, rate, 0);
                    await service.connect(account).subscribe(0);
                });

                describe("when have no uncharged periods", () => {
                    it("should not charge", async () => {
                        await time.increase(Math.floor(period / 2));
                        await expect(service.connect(account).deposit({value: 30}))
                        .to.not.emit(service, "Charged");
                    });
                });

                describe("when have uncharged periods", () => {
                    it("should charge", async () => {
                        await time.increase(period);
                        await expect(service.connect(account).deposit({value: 30}))
                        .to.emit(service, "Charged")
                        .withArgs(account.address, account.address, 0, 1, 30);
                    });
                });
            });
        });
    });

    describe("Withdraw", () => {
        let service: TestStandaloneSubscriptionService;
        let owner: SignerWithAddress;
        let user1: SignerWithAddress;

        beforeEach(async () => {
            const deployment = await loadFixture(deploy);
            service = deployment.service;
            owner = deployment.owner;
            user1 = deployment.user1;
        });

        describe("withdraw()", () => {
            let account: SignerWithAddress;
            const initialBalance = 100;
            
            beforeEach(async () => {
                account = user1;
                await service.connect(account).dummyDeposit({value: initialBalance});
            });

            describe("when not subscribed", () => {
                it("can withdraw from contract and emit 'Withdraw' event", async () => {
                    const amount = 10;
                    await expect(service.connect(account).withdraw(amount))
                    .to.emit(service, "Withdraw")
                    .withArgs(account.address, amount);
                    expect(await service.balanceOf(account.address)).to.equal(initialBalance - amount);
                });

                it("can withdraw full balance", async () => {
                    await expect(() => service.connect(account).withdraw(initialBalance))
                    .to.changeEtherBalance(account, initialBalance);
                    expect(await service.balanceOf(account.address)).to.equal(0);
                });
    
                it("should revert if amount is greater than balance", async () => {
                    await expect(service.connect(account).withdraw(initialBalance + 1))
                    .to.be.revertedWithCustomError(service, "InsufficientBalance")
                    .withArgs(initialBalance, initialBalance + 1);
                });
            });

            describe("when subscribed", () => {
                const subscribeTimestamp = getUtcTimestamp() + 10;
                const period = DAY;
                const rate = 30;

                beforeEach(async () => {
                    await service.addPlan(period, 0, rate, 0);
                    await time.setNextBlockTimestamp(subscribeTimestamp);
                    await service.connect(account).subscribe(0);
                });

                it("should allow to withdraw all remaining balance if there're no uncharged periods", async () => {
                    await time.increase(10);
                    const remainingBalance = initialBalance - rate;
                    await expect(() => service.connect(account).withdraw(remainingBalance))
                    .to.changeEtherBalance(account, remainingBalance);
                    expect(await service.balanceOf(account.address)).to.equal(0);
                });

                it("should allow to withdraw all remaining balance which not reserved for uncharged periods", async () => {
                    await time.increase(5 * period);
                    const currentBalance = initialBalance - rate;
                    const availableBalance = currentBalance - Math.floor(currentBalance / rate) * rate;
                    await expect(() => service.connect(account).withdraw(availableBalance))
                    .to.changeEtherBalance(account, availableBalance);
                    expect(await service.balanceOf(account.address)).to.equal(currentBalance - availableBalance);
                });

                it("should revert if amount is greater than not reserved balance", async () => {
                    await time.increase(5 * period);
                    const currentBalance = initialBalance - rate;
                    const availableBalance = currentBalance - Math.floor(currentBalance / rate) * rate;
                    await expect(service.connect(account).withdraw(availableBalance + 1))
                    .to.be.revertedWithCustomError(service, "InsufficientBalance")
                    .withArgs(availableBalance, availableBalance + 1);
                });
            });
        });

        describe("withdrawPayments()", () => {
            describe("when no payments", () => {
                it("should revert", async () => {
                    await expect(service.withdrawPayments(owner.address))
                    .to.be.rejectedWith("nothing to withdraw");
                });
            });

            it("should revert if caller is not a contract owner", async () => {
                await expect(service.connect(user1).withdrawPayments(user1.address))
                .to.be.rejectedWith("caller is not the owner");
            });

            describe("when there're non withdrew payments", () => {
                const rate = 30;

                beforeEach(async () => {
                    await service.connect(user1).dummyDeposit({value: 100});
                    await service.addPlan(DAY, 0, rate, 0);
                    await service.connect(user1).subscribe(0);
                });

                it("should revert if receiver is zero address", async () => {
                    await expect(service.withdrawPayments(ethers.constants.AddressZero))
                    .to.be.rejectedWith("receiver is zero address");
                });

                it("should withdraw and reset 'paidAmount'", async () => {
                    await expect(service.withdrawPayments(owner.address)).to.changeEtherBalance(owner, rate);
                    expect(await service.paidAmount()).to.equal(0);
                });
            });
        });
    });
});