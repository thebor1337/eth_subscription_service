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
// ? это нфт будет брать данные по истечению и тд с контракта-оператора
// ? RentalNFT привязать к стандарту подписок

// ! TODO проверить невозможность ситуации, когда кол-во chargedPeriods больше, чем finitePeriods

contract StandaloneSubscriptionService is IStandaloneSubscriptionService, Ownable {
    using Math for uint;

    uint public paidAmount;
    
    Plan[] private _plans;
    mapping(address => Subscription) private _subscriptions;
    mapping(address => uint) private _balances;

    modifier mustBeSubscribed(address account) {
        if (!_subscribed(account)) {
            revert NotSubscribed();
        }
        _;
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function subscriptionOf(address account) external view mustBeSubscribed(account) returns(Subscription memory) {
        return _subscriptions[account];
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function balanceOf(address account) public view returns(uint) {
        return _balances[account];
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function reservedOf(address account) public view returns(uint) {
        if (!_subscribed(account)) return 0;

        Subscription storage subscription = _subscriptions[account];

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

    /// @inheritdoc IStandaloneSubscriptionService
    function availableBalance(address account) public view returns(uint) {
        uint balance = balanceOf(account);
        uint reserved = reservedOf(account);
        if (reserved >= balance) {
            return 0;
        }
        return balance - reserved;
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function validUntil(address account) public view mustBeSubscribed(account) returns(uint) {
        Subscription storage subscription = _subscriptions[account];

        uint planIdx = _subscriptions[account].planIdx;
        Plan storage plan = _plans[planIdx];

        // если план отключен, то подписка не действительна, если начался следующий период после момента отключения
        if (_planDisabled(planIdx) || _cancelled(account)) {
            uint period = plan.period;
            uint startedAt = subscription.startedAt;
            uint maxPeriods = _calcCompletePeriods(
                startedAt, 
                block.timestamp,
                plan.disabledAt, 
                subscription.cancelledAt, 
                period, 
                true
            );
            return startedAt + maxPeriods * period;
        }

        return _calcFundedUntil(
            subscription.startedAt, 
            subscription.chargedPeriods, 
            balanceOf(account), 
            plan.rate, 
            plan.period
        );
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function isValid(address account) external view returns(bool) {
        return block.timestamp >= validUntil(account);
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function nextAvailableChargeAt(address account) external view mustBeSubscribed(account) returns(uint) {
        Subscription storage subscription = _subscriptions[account];
        Plan storage plan = _plans[subscription.planIdx];

        uint startedAt = subscription.startedAt;
        uint period = plan.period;

        uint completePeriods = _calcCompletePeriods(
            startedAt, 
            block.timestamp,
            plan.disabledAt, 
            subscription.cancelledAt, 
            period, 
            false
        );

        if (completePeriods > subscription.chargedPeriods) return 0;
        return startedAt + completePeriods * period;
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function subscribe(uint planIdx) external {
        if (_planClosed(planIdx) || _planDisabled(planIdx)) revert PlanUnavailable();

        if (_subscribed(msg.sender) && !_cancelled(msg.sender)) {
            uint oldPlanIdx = _subscriptions[msg.sender].planIdx;
            if (!_planDisabled(oldPlanIdx)) {
                revert NotCancelled();
            }
            emit Cancelled(msg.sender, oldPlanIdx);
        }

        Plan storage plan = _plans[planIdx];
        uint rate = plan.rate;
        uint trial =  plan.trial;

        _subscribe(msg.sender, planIdx, trial);

        if (trial == 0) {
            _charge(msg.sender, msg.sender, planIdx, 1, rate, true);
        } else {
            if (balanceOf(msg.sender) < rate) {
                revert InsufficientBalance(balanceOf(msg.sender), rate);
            }
        }
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function restore() external mustBeSubscribed(msg.sender) {
        if (!_cancelled(msg.sender)) revert NotCancelled();

        Subscription storage subscription = _subscriptions[msg.sender];
        uint planIdx = subscription.planIdx;

        if (_planDisabled(planIdx)) revert PlanUnavailable();

        subscription.startedAt = block.timestamp;
        subscription.cancelledAt = 0;
        subscription.chargedPeriods = 0;

        _charge(msg.sender, msg.sender, planIdx, 1, _plans[planIdx].rate, true);

        emit Restored(msg.sender, planIdx);
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function cancel() external mustBeSubscribed(msg.sender) {
        if (_cancelled(msg.sender)) revert AlreadyCancelled();

        Subscription storage subscription = _subscriptions[msg.sender];
        uint planIdx = subscription.planIdx;

        subscription.cancelledAt = block.timestamp;

        (uint amountToCharge, uint periodsToCharge, ) = _calcCharge(msg.sender, true);
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

    /// @inheritdoc IStandaloneSubscriptionService
    function charge(address account) external mustBeSubscribed(account) {
        (uint amountToCharge, uint periodsToCharge, ) = _calcCharge(account, msg.sender == account);
        if (periodsToCharge == 0) revert NothingToCharge();
        _charge(
            account, 
            msg.sender, 
            _subscriptions[account].planIdx, 
            amountToCharge, 
            periodsToCharge,
            amountToCharge > 0
        );
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function charge(address[] calldata accounts) external {
        uint amountToTransfer;
        bool charged;

        for (uint i = 0; i < accounts.length; i++) {
            address account = accounts[i];

            if (!_subscribed(account)) continue;
            
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

        if (!charged) revert NothingToCharge();

        if (amountToTransfer > 0) {
            _pay(amountToTransfer);
        }
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function deposit() external payable {
        _beforeDeposit(msg.sender, msg.value);

        _balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);

        _afterDeposit(msg.sender, msg.value);
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function withdraw(uint amount) external {
        uint maxAmount = availableBalance(msg.sender);
        require(amount <= maxAmount, "amount is greater than max withdraw amount");

        _decreaseBalance(msg.sender, amount);

        require(_transfer(msg.sender, amount), "transfer failed");

        emit Withdraw(msg.sender, amount);
    }

    /// @inheritdoc IStandaloneSubscriptionService
    function getPlan(uint planIdx) external view returns(Plan memory) {
        return _plans[planIdx];
    }

    /// @inheritdoc IStandaloneSubscriptionService
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

    /**
     * @dev See {IStandaloneSubscriptionService-disablePlan}
     */
    function disablePlan(uint planIdx) external onlyOwner {
        require(!_planDisabled(planIdx), "plan already disabled");
        _plans[planIdx].disabledAt = block.timestamp;
        emit PlanDisabled(planIdx);
    }

    /**
     * @dev See {IStandaloneSubscriptionService-closePlan}
     */
    function closePlan(uint planIdx) external onlyOwner {
        require(!_planDisabled(planIdx), "plan disabled");
        require(!_planClosed(planIdx), "plan already closed");
        _plans[planIdx].closed = true;
        emit PlanClosed(planIdx);
    }

    /**
     * @dev See {IStandaloneSubscriptionService-openPlan}
     */
    function openPlan(uint planIdx) external onlyOwner {
        require(!_planDisabled(planIdx), "plan disabled");
        require(_planClosed(planIdx), "plan not closed");
        _plans[planIdx].closed = false;
        emit PlanOpened(planIdx);
    }

    function withdrawPayments(address receiver) external onlyOwner {
        require(paidAmount > 0, "nothing to withdraw");
        require(receiver != address(0), "receiver is zero address");
        paidAmount = 0;
        require(_transfer(receiver, paidAmount), "failed transfer");
    }

    /**
     * @param account Account's address to check
     * @return bool Is the account's subscribed
     */
    function _subscribed(address account) internal view returns(bool) {
        return _subscriptions[account].createdAt != 0;
    }

    /**
     * @param account Account's address to check
     * @return bool Is the account's subscription cancelled
     */
    function _cancelled(address account) internal view returns(bool) {
        return _subscriptions[account].cancelledAt != 0;
    }

    function _planClosed(uint planIdx) internal view returns(bool) {
        return _plans[planIdx].closed;
    }

    function _planDisabled(uint planIdx) internal view returns(bool) {
        return _plans[planIdx].disabledAt != 0;
    }

    function _subscribe(address account, uint planIdx, uint trial) internal {
        _subscriptions[account] = Subscription({
            createdAt: block.timestamp,
            planIdx: planIdx,
            startedAt: block.timestamp + trial,
            cancelledAt: 0,
            chargedPeriods: 0
        });

        emit Subscribed(msg.sender, planIdx);
    }

    /**
     * @notice Process the charging
     * @dev Emits {Charged} event
     * Throws if the balance is not enough to charge {amountToCharge}
     * @param account The address of the account
     *        MUST be subscribed
     * @param operator The address of the operator, who performs the charging
     * @param planIdx The index of the plan
     * @param amountToCharge The amount ETH to charge
     * @param periodsToCharge The number of periods to charge
     * @param pay Whether to pay the charged amount to the recipient
     */
    function _charge(
        address account, 
        address operator, 
        uint planIdx, 
        uint amountToCharge,
        uint periodsToCharge,
        bool pay
    ) internal {
        _decreaseBalance(account, amountToCharge);
        _subscriptions[account].chargedPeriods += periodsToCharge;
        if (pay) _pay(amountToCharge);
        emit Charged(account, operator, planIdx, periodsToCharge, amountToCharge);
    }

    /**
     * @dev Decrease the balance of {account} by {amount}
     * @param account Address of the account
     * @param amount Amount to decrease the balance
     */
    function _decreaseBalance(address account, uint amount) internal {
        uint balance = balanceOf(account);
        if (amount > balance) {
            revert InsufficientBalance(balance, amount);
        }
        unchecked {
            // never overflows, checked above
            _balances[account] = balance - amount;
        }
    }

    /**
     * @dev a hook, called before executing deposit
     * Executes if the user has a subscription and it has not been cancelled. 
     * If the plan associated with the current subscription is active and the subscription was inactive due to insufficient balance, 
     * it will be restored. Since the restoring process involves overwriting {startedAt}, 
     * data on previous debts will be lost. Therefore the hook charges debt periods before updating the subscription's data.
     * @param account Address of the account
     * @param amount Amount to deposit
     */
    function _beforeDeposit(address account, uint amount) internal virtual {
        if (!_subscribed(account) || _cancelled(account)) return;

        Subscription storage subscription = _subscriptions[account];
        uint planIdx = subscription.planIdx;

        // Charge debt since current "startedAt" will be updated to prevent the contract owner from charging for inactive periods
        // So if don't charge now, the debt data will be lost
        (uint amountToCharge, uint periodsToCharge, ) = _calcCharge(msg.sender, true);
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

        if (_planDisabled(planIdx)) return;

        Plan storage plan = _plans[planIdx];

        uint fundedUntil = _calcFundedUntil(
            subscription.startedAt, 
            subscription.chargedPeriods, 
            balanceOf(account), 
            plan.rate, 
            plan.period
        );

        // Don't restore if the subscription is still active
        if (block.timestamp <= fundedUntil) return;

        fundedUntil += (amount / plan.rate) * plan.period;

        // Restore if the subscription will be activated after adding the deposit to the balance
        // Otherwise the contract owner will be able to abuse by charging for inactive periods
        if (block.timestamp <= fundedUntil) {
            subscription.startedAt = block.timestamp;
            emit Restored(account, subscription.planIdx);
        }
    }

    /**
     * @dev a hook, called after executing deposit
     * @param account Address of the account
     * @param amount Amount to deposit
     */
    function _afterDeposit(address account, uint amount) internal virtual {}

    /**
     * @dev Called after charging to store the charged amount and makes it possible to withdraw it by the contract owner
     * @param amount Amount to pay
     */
    function _pay(uint amount) internal {
        paidAmount += amount;
    }

    /**
     * @dev Transfer {amount} ETH from the contract to {to}
     * @param to Address of the recipient
     * @param amount Amount to transfer
     */
    function _transfer(address to, uint amount) internal returns(bool) {
        (bool success, ) = to.call{value: amount}("");
        return success;
    }

    /**
     * @param account Address of the account 
     *        MUST be subscribed
     * @param makeDiscount Whether to make discount according to the plan's discount value
     * @return amountToCharge Total ETH amount to charge for all considered periods (taking into account the discount)
     * @return periodsToCharge Total number of periods to charge
     * @return rate Rate to charge for the period
     */
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

    /**
     * @dev Calculates the number of periods that have not been charged (debt periods)
     * @param startedAt Timestamp at which the subscription started
     * @param cancelledAt Timestamp at which the subscription was cancelled
     *        MUST be 0 if the subscription has not been cancelled
     * @param chargedPeriods Number of periods that have been charged
     * @param planDisabledAt Timestamp at which the plan was disabled
     *        MUST be 0 if the plan is active
     * @param period Period of the plan
     * @param rate Amount of ETH to charge for each period
     * @param balance Current balance of the account
     */
    function _calcDebtPeriods(
        uint startedAt,
        uint cancelledAt,
        uint chargedPeriods,
        uint planDisabledAt,
        uint period,
        uint rate,
        uint balance
    ) internal view returns(uint) {
        // Calculates the number of complete periods that have passed since the subscription started
        uint completePeriods = _calcCompletePeriods(
            startedAt,
            block.timestamp,
            planDisabledAt,
            cancelledAt,
            period,
            false
        );

        // Debt periods are 0 if there has been charged as many periods as have passed
        if (completePeriods <= chargedPeriods) return 0;

        uint unchargedPeriods;
        unchecked {
            // never overflows, checked above
            unchargedPeriods = completePeriods - chargedPeriods;
        }

        // Debt periods are minimum of uncharged periods and periods that can be paid with the current balance.
        // Account cannot pay more than the current balance in terms of periods
        return unchargedPeriods.min(balance / rate);
    }

    /**
     * @dev Calculates the number of complete periods that have passed since {startedAt}
     * @param startedAt Timestamp at which the subscription started
     * @param planDisabledAt Timestamp at which the plan was disabled
     *        MUST be 0 if the plan is active
     * @param cancelledAt Timestamp at which the subscription was cancelled
     *        MUST be 0 if the subscription has not been cancelled
     * @param period Period of the plan
     * @param roundUp If true, rounds up the result (useful when need to include the current period)
     */
    function _calcCompletePeriods(
        uint startedAt,
        uint maxUntilAt,
        uint planDisabledAt,
        uint cancelledAt,
        uint period,
        bool roundUp
    ) internal pure returns(uint) {

        // Calculates timestamp at which the subscription possibly ends
        // due to the plan being disabled or the subscription being cancelled
        // If subscription is still active, it's possible to take the current timestamp
        // since we calculate the number of COMPLETE periods (which have fully already passed)
        uint untilAt = Math.min(
            planDisabledAt == 0 ? maxUntilAt : planDisabledAt,
            cancelledAt == 0 ? maxUntilAt : cancelledAt
        );

        // Case when the subscription has not started yet (for example, the plan has a trial period)
        if (untilAt < startedAt) return 0;

        uint timePassed;
        unchecked {
            // never overflows, checked above
            timePassed = untilAt - startedAt;
        }

        if (roundUp) return timePassed.ceilDiv(period);
        return timePassed / period;
    }

    /**
     * @dev Calculates how long the subscription will be active based on the balance
     * @param startedAt Timestamp at which the subscription started
     * @param chargedPeriods Number of periods that have been charged
     * @param balance Current balance of the account
     * @param rate Amount of ETH to charge for each period
     * @param period Period of the plan
     */
    function _calcFundedUntil(
        uint startedAt, 
        uint chargedPeriods, 
        uint balance, 
        uint rate, 
        uint period
    ) internal pure returns(uint) {
        // {balance / rate} can be interpreted as the number of periods that can be paid with the current balance
        return startedAt + (chargedPeriods + balance / rate) * period;
    }
}