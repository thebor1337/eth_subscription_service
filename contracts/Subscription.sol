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
// ! TODO севрис подписок (вместо одного контракта, через какой-то прокси который содержит в себе общий баланс, занесенный на сервер)


contract SubscriptionContract is Ownable {

    using Math for uint;

    event Deposit(address indexed account, uint amount);
    event Withdraw(address indexed account, uint amount);

    event Subscribed(address indexed account, uint indexed planIdx);
    event Cancelled(address indexed account, uint indexed planIdx);
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
        uint chargedAt;
        uint chargedPeriods;
    }

    address _recipient;
    Plan[] _plans;
    mapping(address => Subscription) _subscriptions;
    mapping(address => uint) _balances;

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
        uint countablePeriods = _periodsPassed(
            subscription.startedAt, 
            plan.disabledAt == 0 ? block.timestamp : plan.disabledAt,
            plan.period, 
            false
        );

        return _calcDebt(
            countablePeriods, 
            subscription.chargedPeriods, 
            plan.rate, 
            balanceOf(account)
        );
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

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");

        emit Withdraw(msg.sender, amount);
    }

    function hasSubscription(address account) public view returns(bool) {
        return _subscriptions[account].startedAt != 0;
    }

    function getSubscription(address account) external view returns(Subscription memory) {
        require(hasSubscription(account), "no subscription");
        return _subscriptions[account];
    }

    function getSubscribedPlanIdx(address account) public view returns(uint) {
        require(hasSubscription(account), "no subscription");
        return _subscriptions[account].planIdx;
    }

    function getPlan(uint planIdx) external view returns(Plan memory) {
        return _plans[planIdx];
    }

    function isSubscriptionActive(address account) external view returns(bool) {
        require(hasSubscription(account), "no subscription");

        Subscription storage subscription = _subscriptions[account];
        Plan storage plan = _plans[_subscriptions[account].planIdx];

        uint countablePeriods = _periodsPassed(subscription.startedAt, block.timestamp, plan.period, false);

        // если план отключен, то подписка не действительна, если начался следующий период после момента отключения
        if (plan.disabledAt != 0 && countablePeriods * plan.period >= plan.disabledAt) {
            return false;
        }

        uint balanceInPeriods = balanceOf(account) / plan.rate;
        return countablePeriods <= subscription.chargedPeriods + balanceInPeriods;
    }

    function nextChargeAt(address account) external view returns(uint) {
        require(hasSubscription(account), "no subscription");

        Subscription storage subscription = _subscriptions[account];
        Plan storage plan = _plans[subscription.planIdx];

        uint startedAt = subscription.startedAt;
        uint chargedPeriods = subscription.chargedPeriods;
        uint planDisabledAt = plan.disabledAt;
        uint period = plan.period;

        uint countablePeriods = _periodsPassed(
            startedAt, 
            (planDisabledAt == 0) ? block.timestamp : planDisabledAt, 
            period, 
            false
        );

        if (countablePeriods > chargedPeriods) {
            return 0;
        }
        if (countablePeriods == chargedPeriods) {
            return startedAt + countablePeriods * period;
        }
        return startedAt + (chargedPeriods + 1) * period;
    }

    function expiresAt(address account) external view returns(uint) {
        require(hasSubscription(account), "no subscription");


    }

    // function expiresAt(address account) external view returns(uint) {
    //     // TODO должно выдавать, когда подписка заканчивается на основе текущего баланса или неактивности плана
    //     // TODO если уже истекла - выдавать ошибку
    //     require(hasSubscription(account), "no subscription");

    //     Subscription storage subscription = _subscriptions[account];
    //     uint startedAt = subscription.startedAt;
    //     uint period = _plans[subscription.planIdx].period;

    //     if (block.timestamp < startedAt) {
    //         return startedAt;
    //     }

    //     uint advancedCountablePeriods = _periodsPassed(startedAt, block.timestamp, period, true);
    //     return startedAt + advancedCountablePeriods * period;
    // }

    function subscribe(uint planIdx) external virtual {
        // TODO что по поводу реентранси?

        require(!hasSubscription(msg.sender), "already subscribed");
        require(isPlanActive(planIdx), "plan is unavailable");

        Plan storage plan = _plans[planIdx];

        uint trial = plan.trial;
        uint rate = plan.rate;

        if (trial == 0) {
            _charge(msg.sender, msg.sender, planIdx, 1, rate, true);
        } else {
            require(balanceOf(msg.sender) >= rate, "not enough balance");
        }

        Subscription storage subscription = _subscriptions[msg.sender];
        subscription.planIdx = planIdx;
        subscription.startedAt = block.timestamp + trial;
    }

    function charge(bool extra) external {
        // TODO что если он будет по кд вызывать extra? сделать ограничение, что продлить через extra можно только на 1 период вперед
        // TODO не давать продлевать в будущее более чем за N секунд до истечения подписки
        (uint amountToCharge, uint periodsToCharge) = _calcCharge(msg.sender, msg.sender, extra);
        _charge(
            msg.sender, 
            msg.sender, 
            _subscriptions[msg.sender].planIdx, 
            amountToCharge, 
            periodsToCharge,
            true
        );
    }

    function charge(address account) external {
        (uint amountToCharge, uint periodsToCharge) = _calcCharge(msg.sender, account, false);
        _charge(
            account, 
            msg.sender, 
            _subscriptions[account].planIdx, 
            amountToCharge, 
            periodsToCharge,
            true
        );
    }

    function charge(address[] calldata accounts) external {
        // TODO все таки подумать об ошибка = похуй, пропускаем просто
        uint amountToTransfer;
        for (uint i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            (uint amountToCharge, uint periodsToCharge) = _calcCharge(msg.sender, account, false);
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

        _transfer(_recipient, amountToTransfer);
    }

    function cancel() external {
        // TODO списывать сразу весь долг как самочардж
        // TODO отмена это когда ты отменяешь следующее списание, а не удаляешь подписку
        require(hasSubscription(msg.sender), "no subscription");
        require(lockedOf(msg.sender) == 0, "locked balance is not zero");

        uint planIdx = _subscriptions[msg.sender].planIdx;
        delete _subscriptions[msg.sender];

        emit Cancelled(msg.sender, planIdx);
    }

    function _calcCharge(
        address operator, 
        address account, 
        bool extra
    ) internal view returns(
        uint amountToCharge, 
        uint periodsToCharge
    ) {
        require(hasSubscription(account), "no subscription");

        Subscription storage subscription = _subscriptions[account];
        
        uint planIdx = subscription.planIdx;
        Plan storage plan = _plans[planIdx];

        uint period = plan.period;
        uint planDisabledAt = plan.disabledAt;
        uint chargedPeriods = subscription.chargedPeriods;

        uint countablePeriods = _periodsPassed(
            subscription.startedAt, 
            (planDisabledAt == 0) ? block.timestamp : planDisabledAt, 
            period, 
            false
        );

        uint rate;
        if (operator == account) {
            if (countablePeriods > chargedPeriods) {
                unchecked {
                    periodsToCharge = countablePeriods - chargedPeriods;
                }
            } else if (extra) {
                require(chargedPeriods == countablePeriods, "cannot charge more than one extra period"); 
            }

            if (extra) {
                require(planDisabledAt == 0, "plan is disabled");
                uint nextPeriodTimestamp = subscription.startedAt + (countablePeriods + 1) * period;
                // TODO задавать в контракте мин колво дней для продления
                require(nextPeriodTimestamp - block.timestamp <= 3 days, "too early to charge in advance");
                periodsToCharge++;
            }

            require(periodsToCharge > 0, "all periods are charged");
            rate = rate.mulDiv(100 - plan.chargeDiscount, 100);
        } else {
            require(countablePeriods > chargedPeriods, "all periods are charged");
            unchecked {
                periodsToCharge = countablePeriods - chargedPeriods;
            }
            rate = plan.rate;
        }

        amountToCharge = (periodsToCharge * rate).min(
            _calcDebt(countablePeriods, chargedPeriods, rate, period)
        );

        require(amountToCharge > 0, "nothing to charge");
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

        _subscriptions[account].chargedAt = block.timestamp;
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

    function _calcDebt(
        uint countablePeriods, 
        uint chargedPeriods, 
        uint rate, 
        uint maxDebt
    ) internal pure returns(uint) {
        return maxDebt.min((countablePeriods - chargedPeriods) * rate);
    }

    function _periodsPassed(uint start, uint end, uint period, bool roundUp) internal pure returns(uint) {
        if (end < start) return 0;

        uint timePassed;
        unchecked {
            timePassed = end - start;
        }

        if (roundUp) {
            return timePassed.ceilDiv(period);
        }

        return timePassed / period;
    }

    function _timePassed(uint start, uint end) internal pure returns(uint) {
        if (end < start) return 0;

        unchecked {
            return end - start;
        }
    }
}