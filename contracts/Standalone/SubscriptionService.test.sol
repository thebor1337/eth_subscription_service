// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./SubscriptionService.sol";

// TODO вернуть стейт переменным private, поменять здесь получение доступа и перезапись их через assembly

contract TestStandaloneSubscriptionService is StandaloneSubscriptionService {

    uint private constant PLANS_SLOT = 1;
    uint private constant SUBSCRIPTTIONS_SLOT = 3;
    uint private constant BALANCES_SLOT = 4;
    uint private constant CANCELLED_AT_OFFSET_SLOT = 4;

    function testSubscribed(address account) external view returns(bool) {
        return _subscribed(account);
    }

    function testCancelled(address account) external view returns(bool) {
        return _cancelled(account);
    }

    function testPlanClosed(uint planIdx) external view returns(bool) {
        return _planClosed(planIdx);
    }

    function testPlanDisabled(uint planIdx) external view returns(bool) {
        return _planDisabled(planIdx);
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

    function testDecreaseBalance(address account, uint amount) external {
        _decreaseBalance(account, amount);
    }

    function testBeforeDeposit(address account, uint amount) external {
        _beforeDeposit(account, amount);
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
        uint period,
        bool countNext
    ) external pure returns(uint) {
        return _calcCountedPeriods(
            startedAt,
            maxUntilAt,
            planDisabledAt,
            cancelledAt,
            period,
            countNext
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

    function testSubscribe(address account, uint planIdx, uint trial) external {
        _subscribe(account, planIdx, trial);
    }

    function dummyCancel(address account, uint timestamp) external {
        _writeUint(
            uint(keccak256(abi.encode(account, SUBSCRIPTTIONS_SLOT))) + CANCELLED_AT_OFFSET_SLOT, 
            timestamp
        );
    }

    function dummyDeposit(address account, uint amount) external payable {
        _writeUint(
            uint(keccak256(abi.encode(account, BALANCES_SLOT))), 
            amount
        );
    }

    function _writeUint(uint slot, uint value) private {
        assembly {
            sstore(slot, value)
        }
    }
}