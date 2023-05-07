// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./ISubscriptionService.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

// ? subscription mining (чем позднее замайнил, тем меньше токенов получил)
// ? может быть выдавать нфт, наличие которой = подписка?
// ? персонализированная подписка (меньше рейт и тд)
// ? подарочные подписки (через нфт)
// ? севрис подписок (вместо одного контракта, через какой-то прокси который содержит в себе общий баланс, занесенный на сервер) + возможность интеграции с существующими проектами
// ? нфт как подписка, в ней указывается оператор (контракт, обрабатывающий подписку) и может использолваться где угодно + коллбеки (посмотреть как устроены нфт на hyphen, где на ней были указаны динамические проценты)

// ! TODO кастомные ошибки
// ! TODO сделать интерфейс
// ! TODO упорядочить функции (external/public + сам порядок)
// ! TODO переименовать нормально
// ! TODO написать комментарии
// TODO переделать проверку существования подписки со startedAt на createdAt
// TODO убрать повторяющиеся модификаторы проверки подписки (в _charge например)
// TODO удаление подписки? (зачем)


contract StandaloneSubscriptionService is IStandaloneSubscriptionService, Ownable {

    using Math for uint;

    address public recipient;
    
    Plan[] private _plans;
    mapping(address => Subscription) private _subscriptions;
    mapping(address => uint) private _balances;

    constructor(address recipient_) {
        recipient = recipient_;
    }

    modifier mustBeSubscribed(address account) {
        require(_subscriptions[account].startedAt != 0, "account is not subscribed");
        _;
    }

    function subscriptionOf(address account) external view mustBeSubscribed(account) returns(Subscription memory) {
        return _subscriptions[account];
    }

    function balanceOf(address account) public view returns(uint) {
        return _balances[account];
    }

    function reservedOf(address account) public view returns(uint) {
        Subscription storage subscription = _subscriptions[account];
        if (subscription.startedAt == 0) return 0;

        Plan storage plan = _plans[subscription.planIdx];
        uint rate = plan.rate;

        uint debtPeriods = _calcDebtPeriods(
            subscription.startedAt, 
            subscription.cancelledAt, 
            subscription.chargedPeriods, 
            plan.disabledAt, 
            plan.period, 
            rate, 
            balanceOf(account)
        );

        return debtPeriods * rate;
    }

    function maxWithdrawAmount(address account) public view returns(uint) {
        uint balance = balanceOf(account);
        uint reserved = reservedOf(account);
        if (reserved >= balance) {
            return 0;
        }
        return balance - reserved;
    }

    function isPlanActive(uint planIdx) public view returns(bool) {
        return _plans[planIdx].disabledAt != 0 || _plans[planIdx].closed;
    }

    function validUntil(address account) public view mustBeSubscribed(account) returns(uint) {
        Subscription storage subscription = _subscriptions[account];
        Plan storage plan = _plans[_subscriptions[account].planIdx];

        uint startedAt = subscription.startedAt;
        uint period = plan.period;
        uint planDisabledAt = plan.disabledAt;
        uint cancelledAt = subscription.cancelledAt;

        // если план отключен, то подписка не действительна, если начался следующий период после момента отключения
        if (planDisabledAt != 0 || cancelledAt != 0) {
            uint maxPeriods = _calcFinitePeriods(startedAt, planDisabledAt, cancelledAt, period, true);
            return startedAt + maxPeriods * period;
        }

        return _calcFundedUntil(
            startedAt, 
            subscription.chargedPeriods, 
            balanceOf(account), 
            plan.rate, 
            period
        );
    }

    function isValid(address account) external view returns(bool) {
        return block.timestamp >= validUntil(account);
    }

    function nextAvailableChargeAt(address account) external view mustBeSubscribed(account) returns(uint) {
        Subscription storage subscription = _subscriptions[account];
        Plan storage plan = _plans[subscription.planIdx];

        uint startedAt = subscription.startedAt;
        uint period = plan.period;

        uint finitePeriods = _calcFinitePeriods(
            startedAt, 
            plan.disabledAt, 
            subscription.cancelledAt, 
            period, 
            false
        );
        uint chargedPeriods = subscription.chargedPeriods;

        if (finitePeriods > chargedPeriods) return 0;
        if (finitePeriods == chargedPeriods) return startedAt + chargedPeriods * period;
        return startedAt + (chargedPeriods + 1) * period;
    }

    function subscribe(uint planIdx) external {
        require(isPlanActive(planIdx), "plan is unavailable");

        Subscription storage subscription = _subscriptions[msg.sender];
        require(subscription.startedAt == 0 || subscription.cancelledAt != 0, "current subscription is still active");

        Plan storage plan = _plans[planIdx];
        uint trial =  _plans[planIdx].trial;

        subscription.createdAt = block.timestamp;
        subscription.planIdx = planIdx;
        subscription.startedAt = block.timestamp + trial;
        subscription.cancelledAt = 0;

        if (trial == 0) {
            _charge(msg.sender, msg.sender, planIdx, 1, plan.rate, true);
        } else {
            require(balanceOf(msg.sender) >= plan.rate, "not enough balance");
            if (subscription.chargedPeriods != 0) {
                subscription.chargedPeriods = 0;
            }
        }

        emit Subscribed(msg.sender, planIdx);
    }

    function restore() external mustBeSubscribed(msg.sender) {
        Subscription storage subscription = _subscriptions[msg.sender];
        require(subscription.cancelledAt != 0, "subscription hasn't been cancelled");

        uint planIdx = subscription.planIdx;

        Plan storage plan = _plans[subscription.planIdx];
        require(plan.disabledAt == 0, "plan is disabled");

        subscription.startedAt = block.timestamp;
        subscription.cancelledAt = 0;
        subscription.chargedPeriods = 0;

        _charge(msg.sender, msg.sender, planIdx, 1, plan.rate, true);

        emit Restored(msg.sender, planIdx);
    }

    function cancel() external mustBeSubscribed(msg.sender) {
        Subscription storage subscription = _subscriptions[msg.sender];
        require(subscription.cancelledAt == 0, "subscription has been cancelled already");

        uint planIdx = subscription.planIdx;

        subscription.cancelledAt = block.timestamp;

        (uint amountToCharge, uint periodsToCharge, ) = _calcCharge(msg.sender, false);
        if (periodsToCharge > 0) {
            _charge(
                msg.sender, 
                msg.sender, 
                planIdx, 
                amountToCharge, 
                periodsToCharge, 
                amountToCharge > 0
            );
        }

        emit Cancelled(msg.sender, planIdx);
    }

    function charge(address account) external mustBeSubscribed(account) {
        (uint amountToCharge, uint periodsToCharge, ) = _calcCharge(account, msg.sender == account);
        require(periodsToCharge > 0, "nothing to charge");
        _charge(
            account, 
            msg.sender, 
            _subscriptions[account].planIdx, 
            amountToCharge, 
            periodsToCharge,
            amountToCharge > 0
        );
    }

    function charge(address[] calldata accounts) external {
        uint amountToTransfer;
        bool charged;

        for (uint i = 0; i < accounts.length; i++) {
            address account = accounts[i];

            if (_subscriptions[account].startedAt == 0) continue;
            
            (uint amountToCharge, uint periodsToCharge, ) = _calcCharge(account, msg.sender == account);
            
            if (periodsToCharge == 0) continue;
            if (!charged) charged = true;

            _charge(
                account, 
                msg.sender, 
                _subscriptions[account].planIdx, 
                amountToCharge, 
                periodsToCharge,
                false
            );

            amountToTransfer += amountToCharge;
        }

        require(charged, "no accounts to charge");

        if (amountToTransfer > 0) {
            _transfer(recipient, amountToTransfer);
        }
    }

    function deposit() external payable {
        _beforeDeposit(msg.sender, msg.value);

        _balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);

        _afterDeposit(msg.sender, msg.value);
    }

    function withdraw(uint amount) external {
        uint maxAmount = maxWithdrawAmount(msg.sender);
        require(amount <= maxAmount, "amount is greater than max withdraw amount");

        _decreaseBalance(msg.sender, amount);
        _transfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function getPlan(uint planIdx) external view returns(Plan memory) {
        return _plans[planIdx];
    }

    function addPlan(
        uint period,
        uint trial,
        uint rate,
        uint chargeDiscount
    ) external onlyOwner {
        require(chargeDiscount <= 100, "charge discount must be in range [0;100]");
        require(rate != 0, "rate cannot be zero");
        require(period != 0, "period cannot be zero");

        _plans.push(Plan({
            period: period,
            trial: trial,
            rate: rate,
            disabledAt: 0,
            chargeDiscount: chargeDiscount,
            closed: false
        }));

        emit PlanAdded(_plans.length - 1);
    }

    function disablePlan(uint planIdx) external onlyOwner {
        _plans[planIdx].disabledAt = block.timestamp;
        emit PlanDisabled(planIdx);
    }

    function closePlan(uint planIdx) external onlyOwner {
        _plans[planIdx].closed = true;
        emit PlanClosed(planIdx);
    }

    function changeRecipient(address newRecipient) external onlyOwner {
        address oldRecipient = recipient;
        recipient = newRecipient;
        emit RecipientChanged(oldRecipient, newRecipient);
    }

    function _charge(
        address account, 
        address operator, 
        uint planIdx, 
        uint amountToCharge,
        uint periodsToCharge,
        bool makeTransfer
    ) internal {
        _decreaseBalance(account, amountToCharge);

        _subscriptions[account].chargedPeriods += periodsToCharge;

        if (makeTransfer) {
            _transfer(recipient, amountToCharge);
        }

        emit Charged(account, operator, planIdx, amountToCharge);
    }

    /// @dev account MUST be subscribed
    function _calcCharge(address account, bool makeDiscount) internal view returns (
        uint amountToCharge, 
        uint periodsToCharge,
        uint rate
    ) {
        Subscription storage subscription = _subscriptions[account];
        Plan storage plan = _plans[subscription.planIdx];

        rate = plan.rate;

        periodsToCharge = _calcDebtPeriods(
            subscription.startedAt, 
            subscription.cancelledAt, 
            subscription.chargedPeriods, 
            plan.disabledAt, 
            plan.period, 
            rate, 
            balanceOf(account)
        );

        if (periodsToCharge > 0) {
            if (makeDiscount) {
                uint ratio;
                unchecked {
                    // will never overflow, plan.chargeDiscount is restricted to 0-100
                    ratio = 100 - plan.chargeDiscount;
                }
                rate = rate.mulDiv(ratio, 100);
            }
            amountToCharge = periodsToCharge * rate;
        }
    }

    function _decreaseBalance(address account, uint amount) internal {
        uint balance = balanceOf(account);
        require(amount <= balance, "not enough balance");
        unchecked {
            _balances[account] = balance - amount;
        }
    }

    function _transfer(address to, uint amount) internal {
        (bool success, ) = to.call{value: amount}("");
        require(success, "transfer failed");
    }

    function _beforeDeposit(address account, uint amount) internal virtual {
        Subscription storage subscription = _subscriptions[account];
        if (subscription.startedAt == 0 || subscription.cancelledAt != 0) return;

        Plan storage plan = _plans[subscription.planIdx];
        if (plan.disabledAt != 0) return;

        uint fundedUntil = _calcFundedUntil(
            subscription.startedAt, 
            subscription.chargedPeriods, 
            balanceOf(account), 
            plan.rate, 
            plan.period
        );

        if (block.timestamp <= fundedUntil) return;

        fundedUntil += (amount / plan.rate) * plan.period;

        if (block.timestamp <= fundedUntil) {
            subscription.startedAt = block.timestamp;
            emit Restored(account, subscription.planIdx);
        }
    }

    function _afterDeposit(address account, uint amount) internal virtual {}

    function _calcDebtPeriods(
        uint startedAt,
        uint cancelledAt,
        uint chargedPeriods,
        uint planDisabledAt,
        uint period,
        uint rate,
        uint balance
    ) internal view returns(uint) {
        uint finitePeriods = _calcFinitePeriods(
            startedAt,
            planDisabledAt,
            cancelledAt,
            period,
            false
        );

        if (finitePeriods <= chargedPeriods) {
            return 0;
        }

        uint unchargedPeriods;
        unchecked {
            unchargedPeriods = finitePeriods - chargedPeriods;
        }

        return unchargedPeriods.min(balance / rate);
    }

    function _calcFinitePeriods(
        uint startedAt,
        uint planDisabledAt,
        uint cancelledAt,
        uint period,
        bool roundUp
    ) internal view returns(uint) {

        uint endsAt = Math.min(
            planDisabledAt == 0 ? block.timestamp : planDisabledAt,
            cancelledAt == 0 ? block.timestamp : cancelledAt
        );

        if (endsAt < startedAt) return 0;

        uint timePassed;
        unchecked {
            timePassed = endsAt - startedAt;
        }

        if (roundUp) return timePassed.ceilDiv(period);
        return timePassed / period;
    }

    function _calcFundedUntil(
        uint startedAt, 
        uint chargedPeriods, 
        uint balance, 
        uint rate, 
        uint period
    ) internal pure returns(uint) {
        return startedAt + (chargedPeriods + balance / rate) * period;
    }
}