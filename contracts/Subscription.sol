// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

// TODO subscription mining (чем позднее замайнил, тем меньше токенов получил)
// может быть выдавать нфт, наличие которой = подписка?
// персонализированная подписка (меньше рейт и тд)
// TODO подарочные подписки (через нфт)
// ! TODO кастомные ошибки
// TODO сравнить правда ли работает страта со storage поинтерами по сокращению газа или лишняя залупа (и насколько отличается разворчивание контракта при новом подходе)
// ! TODO севрис подписок (вместо одного контракта, через какой-то прокси который содержит в себе общий баланс, занесенный на сервер) + возможность интеграции с существующими проектами
// TODO модификаторы поставить где надо
// TODO restore?
// TODO нфт как подписка, в ней указывается оператор (контракт, обрабатывающий подписку) и может использолваться где угодно + коллбеки (посмотреть как устроены нфт на hyphen, где на ней были указаны динамические проценты)


contract SubscriptionContract is Ownable {

    using Math for uint;

    event Deposit(address indexed account, uint amount);
    event Withdraw(address indexed account, uint amount);

    event Subscribed(address indexed account, uint indexed planIdx);
    event Cancelled(address indexed account, uint indexed planIdx);
    event Restored(address indexed account, uint indexed planIdx);
    event Charged(address indexed account, address indexed operator, uint indexed planIdx, uint amount);

    event PlanAdded(uint indexed planIdx);
    event PlanDisabled(uint indexed planIdx);
    event PlanClosed(uint indexed planIdx);

    event RecipientChanged(address indexed oldRecipient, address indexed newRecipient);

    struct Plan {
        uint period;
        uint trial;
        uint rate;
        uint disabledAt;
        uint chargeDiscount;
        bool closed;
        bytes data;
    }

    struct Subscription {
        uint planIdx;
        uint startedAt;
        // TODO нужно?
        uint chargedPeriods;
        uint cancelledAt;
    }

    // TODO мб сделать паблик переменные?
    address private _recipient;
    Plan[] private _plans;
    mapping(address => Subscription) private _subscriptions;
    mapping(address => uint) private _balances;

    constructor(address recipient_) {
        _recipient = recipient_;
    }

    function addPlan(
        uint period,
        uint trial,
        uint rate,
        uint chargeDiscount,
        bytes calldata data
    ) external onlyOwner {
        require(chargeDiscount <= 100, "charge discount must be in range [0;100]");

        _plans.push(Plan({
            period: period,
            trial: trial,
            rate: rate,
            disabledAt: 0,
            chargeDiscount: chargeDiscount,
            closed: false,
            data: data
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
        address oldRecipient = _recipient;
        _recipient = newRecipient;
        emit RecipientChanged(oldRecipient, newRecipient);
    }

    function isPlanActive(uint planIdx) public view returns(bool) {
        return _plans[planIdx].disabledAt != 0 || _plans[planIdx].closed;
    }

    function balanceOf(address account) public view returns(uint) {
        return _balances[account];
    }

    function lockedOf(address account) public view returns(uint) {
        Subscription storage subscription = _subscriptions[account];
        if (subscription.startedAt == 0) {
            return 0;
        }

        Plan storage plan = _plans[subscription.planIdx];

        uint planDisabledAt = plan.disabledAt;
        uint cancelledAt = subscription.cancelledAt;
        uint rate = plan.rate;

        uint countablePeriods = _countablePeriods(
            subscription.startedAt, 
            planDisabledAt, 
            cancelledAt, 
            plan.period, 
            false
        );

        uint debtPeriods = _calcDebtPeriods(
            countablePeriods, 
            subscription.chargedPeriods, 
            rate, 
            balanceOf(account)
        );

        return debtPeriods * rate;
    }

    function maxWithdrawAmount(address account) public view returns(uint) {
        uint balance = balanceOf(account);
        uint locked = lockedOf(account);
        if (locked >= balance) {
            return 0;
        }
        return balance - locked;
    }

    function deposit() external payable {
        _deposit(msg.sender, msg.value);
    }

    function safeDeposit() external payable {
        uint balance = balanceOf(msg.sender);
        uint locked = lockedOf(msg.sender);
        require(balance >= locked, "lock is greater than current balance");
        _deposit(msg.sender, msg.value);
    }

    function withdraw(uint amount) external {
        uint maxAmount = maxWithdrawAmount(msg.sender);
        require(amount <= maxAmount, "amount is greater than max withdraw amount");

        _decreaseBalance(msg.sender, amount);
        _transfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function hasSubscription(address account) public view returns(bool) {
        return _subscriptions[account].startedAt != 0;
    }

    function getSubscription(address account) external view returns(Subscription memory) {
        require(hasSubscription(account), "no subscription");
        return _subscriptions[account];
    }

    function getPlan(uint planIdx) external view returns(Plan memory) {
        return _plans[planIdx];
    }

    function isSubscriptionActive(address account) external view returns(bool) {
        return block.timestamp >= expiresAt(account);
    }

    function expiresAt(address account) public view returns(uint) {
        require(hasSubscription(account), "no subscription");

        Subscription storage subscription = _subscriptions[account];
        Plan storage plan = _plans[_subscriptions[account].planIdx];

        uint startedAt = subscription.startedAt;
        uint period = plan.period;
        uint planDisabledAt = plan.disabledAt;
        uint cancelledAt = subscription.cancelledAt;

        // если план отключен, то подписка не действительна, если начался следующий период после момента отключения
        if (planDisabledAt != 0 || cancelledAt != 0) {
            uint maxPeriods = _countablePeriods(startedAt, planDisabledAt, cancelledAt, period, true);
            return startedAt + maxPeriods * period;
        }

        uint balanceInPeriods = balanceOf(account) / plan.rate;
        return startedAt + (subscription.chargedPeriods + balanceInPeriods) * period;
    }

    function nextChargeAt(address account) external view returns(uint) {
        require(hasSubscription(account), "no subscription");

        Subscription storage subscription = _subscriptions[account];
        Plan storage plan = _plans[subscription.planIdx];

        uint startedAt = subscription.startedAt;
        uint period = plan.period;

        uint countablePeriods = _countablePeriods({
            startedAt: startedAt,
            planDisabledAt: plan.disabledAt,
            cancelledAt: subscription.cancelledAt,
            period: period,
            roundUp: false
        });

        uint chargedPeriods = subscription.chargedPeriods;

        if (countablePeriods > chargedPeriods) return 0;
        if (countablePeriods == chargedPeriods) return startedAt + countablePeriods * period;
        return startedAt + (chargedPeriods + 1) * period;
    }

    function subscribe(uint planIdx) external {
        require(isPlanActive(planIdx), "plan is unavailable");

        Subscription storage subscription = _subscriptions[msg.sender];
        require(subscription.startedAt == 0 || subscription.cancelledAt != 0, "current subscription is still active");

        Plan storage plan = _plans[planIdx];
        uint trial =  _plans[planIdx].trial;

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

    function restore() external {
        require(hasSubscription(msg.sender), "no subscription");
        
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

    function charge(address account) external {
        (uint amountToCharge, uint periodsToCharge, ) = _calcCharge(msg.sender, account);
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
            
            (uint amountToCharge, uint periodsToCharge, ) = _calcCharge(msg.sender, account);
            
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
            _transfer(_recipient, amountToTransfer);
        }
    }

    function cancel() external {
        // TODO списывать сразу весь долг как самочардж
        require(hasSubscription(msg.sender), "no subscription");
        
        Subscription storage subscription = _subscriptions[msg.sender];
        require(subscription.cancelledAt == 0, "subscription has been cancelled already");

        uint planIdx = subscription.planIdx;

        subscription.cancelledAt = block.timestamp;

        (uint amountToCharge, uint periodsToCharge, ) = _calcCharge(msg.sender, msg.sender);
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

        // TODO проверить, что после чарджа lockedOf = 0

        emit Cancelled(msg.sender, planIdx);
    }

    function _calcCharge(address operator, address account) internal view returns(
        uint amountToCharge, 
        uint periodsToCharge,
        uint rate
    ) {
        require(hasSubscription(account), "no subscription");

        Subscription storage subscription = _subscriptions[account];
        Plan storage plan = _plans[subscription.planIdx];

        rate = plan.rate;

        uint countablePeriods = _countablePeriods({
            startedAt: subscription.startedAt,
            planDisabledAt: plan.disabledAt,
            cancelledAt: subscription.cancelledAt,
            period: plan.period,
            roundUp: false
        });

        periodsToCharge = _calcDebtPeriods(
            countablePeriods, 
            subscription.chargedPeriods, 
            rate, 
            balanceOf(account)
        );

        if (periodsToCharge > 0) {
            if (operator == account) {
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

    // TODO делать скидку за самочардж или нет определять отдельным аргументом, ибо скидка будет шо при кенселе, шо при сабскрайбе
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
            _transfer(_recipient, amountToCharge);
        }

        emit Charged(account, operator, planIdx, amountToCharge);
    }

    function _decreaseBalance(address account, uint amount) internal {
        uint balance = balanceOf(account);
        require(amount <= balance, "not enough balance");
        unchecked {
            _balances[account] = balance - amount;
        }
    }

    function _deposit(address account, uint amount) internal {
        _balances[account] += amount;
        emit Deposit(account, amount);
    }

    function _transfer(address to, uint amount) internal {
        (bool success, ) = to.call{value: amount}("");
        require(success, "transfer failed");
    }

    function _calcDebtPeriods(
        uint countablePeriods,
        uint chargedPeriods,
        uint balance,
        uint rate
    ) internal pure returns(uint) {
        if (countablePeriods <= chargedPeriods) {
            return 0;
        }

        uint unchargedPeriods;
        unchecked {
            unchargedPeriods = countablePeriods - chargedPeriods;
        }

        return unchargedPeriods.min(balance / rate);
    }

    // TODO переименовать, ибо это не засчитанные периоды, это кол-во всех в теории возможных периодов, типа totalPeriods
    function _countablePeriods(
        uint startedAt,
        uint planDisabledAt,
        uint cancelledAt,
        uint period,
        bool roundUp
    ) internal view returns(uint) {
        return _calcPeriods({
            start: startedAt, 
            end: Math.min(
                planDisabledAt == 0 ? block.timestamp : planDisabledAt,
                cancelledAt == 0 ? block.timestamp : cancelledAt
            ),
            period: period,
            roundUp: roundUp
        });
    }

    function _calcPeriods(uint start, uint end, uint period, bool roundUp) internal pure returns(uint) {
        if (end < start) return 0;

        uint timePassed;
        unchecked {
            timePassed = end - start;
        }

        if (roundUp) return timePassed.ceilDiv(period);
        return timePassed / period;
    }
}