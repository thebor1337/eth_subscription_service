// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./SubscriptionService.sol";

contract TestSubscriptionService is SubscriptionService {

    function testSubscribed(address account) external view returns(bool) {
        return _subscribed(account);
    }

    function testCancelled(address account) external view returns(bool) {
        return _cancelled(account);
    }

    function testPlanExists(uint planIdx) external view returns(bool) {
        return _planExists(planIdx);
    }

    function testPlanClosed(uint planIdx) external view returns(bool) {
        return _planClosed(planIdx);
    }

    function testPlanDisabled(uint planIdx) external view returns(bool) {
        return _planDisabled(planIdx);
    }

    function testSubscribe(address account, uint timestamp, uint planIdx, uint trial) external {
        _subscribe(account, timestamp, planIdx, trial);
    }

    function testCancel(address account, uint timestamp, uint planIdx) external {
        _cancel(account, timestamp, planIdx);
    }

    function testRestore(address account, uint timestamp, uint planIdx) external {
        _restore(account, timestamp, planIdx);
    }

    function testCharge(
        address account, 
        address operator, 
        uint planIdx, 
        uint amountToCharge,
        uint periodsToCharge,
        bool pay
    ) external {
        _charge(account, operator, planIdx, amountToCharge, periodsToCharge, pay);
    }

    function testIncreaseBalance(address account, uint value) external payable {
        _increaseBalance(account, value);
    }

    function testDecreaseBalance(address account, uint amount) external {
        _decreaseBalance(account, amount);
    }

    function testBeforeDeposit(address account, uint amount) external {
        _beforeDeposit(account, amount);
    }

    function testAfterDeposit(address account, uint amount) external {
        _afterDeposit(account, amount);
    }

    function testPay(uint amount) external {
        _pay(amount);
    }

    function testTransfer(address to, uint amount) external {
        require(_transfer(to, amount));
    }

    function testCalcCharge(
        uint periodsToCharge,
        uint discountPercent,
        uint rate
    ) external pure returns(
        uint amountToCharge,
        uint adjustedRate
    ) {
        return _calcCharge(
            periodsToCharge,
            discountPercent,
            rate
        );
    }

    function testCalcDebtPeriods(
        uint startedAt,
        uint maxUntilAt,
        uint cancelledAt,
        uint chargedPeriods,
        uint planDisabledAt,
        uint period,
        uint rate,
        uint balance
    ) external pure returns(uint) {
        return _calcDebtPeriods(
            startedAt,
            maxUntilAt,
            cancelledAt,
            chargedPeriods,
            planDisabledAt,
            period,
            rate,
            balance
        );
    }

    function testCalcCountedPeriods(
        uint startedAt,
        uint maxUntilAt,
        uint planDisabledAt,
        uint cancelledAt,
        uint period
    ) external pure returns(uint) {
        return _calcCountedPeriods(
            startedAt,
            maxUntilAt,
            planDisabledAt,
            cancelledAt,
            period
        );
    }

    function testCalcFundedUntil(
        uint startedAt, 
        uint chargedPeriods, 
        uint balance, 
        uint rate, 
        uint period
    ) external pure returns(uint) {
        return _calcFundedUntil(
            startedAt, 
            chargedPeriods, 
            balance, 
            rate, 
            period
        );
    }

    function dummyDeposit() external payable {
        _increaseBalance(msg.sender, msg.value);
    }
}