// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./ISubscriptionService.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";


contract SubscriptionService is ISubscriptionService, Ownable {
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

    modifier planMustExist(uint planIdx) {
        if (!_planExists(planIdx)) {
            revert PlanNotExists();
        }
        _;
    }

    /// @inheritdoc ISubscriptionService
    function subscriptionOf(address account) external view mustBeSubscribed(account) returns(Subscription memory) {
        return _subscriptions[account];
    }

    /// @inheritdoc ISubscriptionService
    function balanceOf(address account) public view returns(uint) {
        return _balances[account];
    }

    /// @inheritdoc ISubscriptionService
    function reservedOf(address account) public view returns(uint) {
        if (!_subscribed(account)) return 0;

        Subscription storage subscription = _subscriptions[account];

        Plan storage plan = _plans[subscription.planIdx];
        uint rate = plan.rate;

        uint debtPeriods = _calcDebtPeriods(
            subscription.startedAt, 
            block.timestamp,
            subscription.cancelledAt, 
            subscription.chargedPeriods, 
            plan.disabledAt, 
            plan.period, 
            rate, 
            balanceOf(account)
        );

        return debtPeriods * rate;
    }

    /// @inheritdoc ISubscriptionService
    function availableBalanceOf(address account) public view returns(uint) {
        uint balance = balanceOf(account);
        uint reserved = reservedOf(account);
        if (reserved >= balance) {
            return 0;
        }
        return balance - reserved;
    }

    /// @inheritdoc ISubscriptionService
    function validUntil(address account) public view mustBeSubscribed(account) returns(uint) {
        Subscription storage subscription = _subscriptions[account];

        uint planIdx = _subscriptions[account].planIdx;
        Plan storage plan = _plans[planIdx];

        if (_planDisabled(planIdx) || _cancelled(account)) {
            uint period = plan.period;
            uint startedAt = subscription.startedAt;
            uint maxCountedPeriods = _calcCountedPeriods(
                startedAt, 
                block.timestamp,
                plan.disabledAt, 
                subscription.cancelledAt, 
                period
            );
            return startedAt + maxCountedPeriods * period;
        }

        return _calcFundedUntil(
            subscription.startedAt, 
            subscription.chargedPeriods, 
            balanceOf(account), 
            plan.rate, 
            plan.period
        );
    }

    /// @inheritdoc ISubscriptionService
    function isValid(address account) external view returns(bool) {
        return block.timestamp < validUntil(account);
    }

    /// @inheritdoc ISubscriptionService
    function nextAvailableChargeAt(address account) external view mustBeSubscribed(account) returns(uint) {
        Subscription storage subscription = _subscriptions[account];
        Plan storage plan = _plans[subscription.planIdx];

        uint startedAt = subscription.startedAt;
        uint period = plan.period;

        uint countedPeriods = _calcCountedPeriods(
            startedAt, 
            block.timestamp,
            plan.disabledAt, 
            subscription.cancelledAt, 
            period
        );

        if (countedPeriods > subscription.chargedPeriods) return 0;
        return startedAt + countedPeriods * period;
    }

    /// @inheritdoc ISubscriptionService
    function previewCharge(address account, bool makeDiscount) public view returns(
        uint amountToCharge, 
        uint periodsToCharge,
        uint rate
    ) {
        if (!_subscribed(account)) return (0, 0, 0);

        Subscription storage subscription = _subscriptions[account];
        Plan storage plan = _plans[subscription.planIdx];

        periodsToCharge = _calcDebtPeriods(
            subscription.startedAt, 
            block.timestamp,
            subscription.cancelledAt, 
            subscription.chargedPeriods, 
            plan.disabledAt, 
            plan.period, 
            plan.rate, 
            balanceOf(account)
        );
        
        if (periodsToCharge > 0) {
            (amountToCharge, rate) = _calcCharge(
                periodsToCharge, 
                // {plan.chargeDiscount}'s range is restricted by addPlan()
                (makeDiscount) ? plan.chargeDiscount : 0,
                plan.rate
            );
        }
    }

    /// @inheritdoc ISubscriptionService
    function subscribe(uint planIdx) external planMustExist(planIdx) {
        if (_planClosed(planIdx) || _planDisabled(planIdx)) revert PlanUnavailable();

        if (_subscribed(msg.sender)) {
            uint oldPlanIdx = _subscriptions[msg.sender].planIdx;
            if (oldPlanIdx == planIdx) {
                revert AlreadySubscribed();
            }
            if (!_cancelled(msg.sender)) {
                revert AlreadySubscribed();
            }
        }

        Plan storage plan = _plans[planIdx];
        uint rate = plan.rate;
        uint trial =  plan.trial;

        _subscribe(msg.sender, block.timestamp, planIdx, trial);

        if (trial == 0) {
            _charge(msg.sender, msg.sender, planIdx, rate, 1, true);
        } else {
            if (balanceOf(msg.sender) < rate) {
                revert InsufficientBalance(balanceOf(msg.sender), rate);
            }
        }
    }

    /// @inheritdoc ISubscriptionService
    function restore() external mustBeSubscribed(msg.sender) {
        if (!_cancelled(msg.sender)) revert NotCancelled();

        uint planIdx = _subscriptions[msg.sender].planIdx;

        if (_planDisabled(planIdx)) revert PlanUnavailable();

        _restore(msg.sender, block.timestamp, planIdx);

        _charge(msg.sender, msg.sender, planIdx, _plans[planIdx].rate, 1, true);
    }

    /// @inheritdoc ISubscriptionService
    function cancel() external mustBeSubscribed(msg.sender) {
        if (_cancelled(msg.sender)) revert AlreadyCancelled();

        uint planIdx = _subscriptions[msg.sender].planIdx;

        _cancel(msg.sender, block.timestamp, planIdx);

        (uint amountToCharge, uint periodsToCharge, ) = previewCharge(msg.sender, true);
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
    }

    /// @inheritdoc ISubscriptionService
    function charge(address account) external mustBeSubscribed(account) {
        (uint amountToCharge, uint periodsToCharge, ) = previewCharge(account, account == msg.sender);
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

    /// @inheritdoc ISubscriptionService
    function chargeMany(address[] calldata accounts) external {
        uint amountToTransfer;
        bool charged;

        for (uint i = 0; i < accounts.length; i++) {
            address account = accounts[i];

            if (!_subscribed(account)) continue;
            
            (uint amountToCharge, uint periodsToCharge, ) = previewCharge(account, account == msg.sender);
            
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

    /// @inheritdoc ISubscriptionService
    function deposit() external payable {
        _beforeDeposit(msg.sender, msg.value);
        _increaseBalance(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
        _afterDeposit(msg.sender, msg.value);
    }

    /// @inheritdoc ISubscriptionService
    function withdraw(uint amount) external {
        uint maxAmount = availableBalanceOf(msg.sender);
        if (amount > maxAmount) {
            revert InsufficientBalance(maxAmount, amount);
        }
        _decreaseBalance(msg.sender, amount);
        require(_transfer(msg.sender, amount), "transfer failed");
        emit Withdraw(msg.sender, amount);
    }

    /// @inheritdoc ISubscriptionService
    function getPlan(uint planIdx) external view planMustExist(planIdx) returns(Plan memory) {
        return _plans[planIdx];
    }

    /// @inheritdoc ISubscriptionService
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

    /// @inheritdoc ISubscriptionService
    function disablePlan(uint planIdx) external onlyOwner planMustExist(planIdx) {
        require(!_planDisabled(planIdx), "plan already disabled");
        _plans[planIdx].disabledAt = block.timestamp;
        emit PlanDisabled(planIdx);
    }

    /// @inheritdoc ISubscriptionService
    function closePlan(uint planIdx) external onlyOwner planMustExist(planIdx) {
        require(!_planDisabled(planIdx), "plan disabled");
        require(!_planClosed(planIdx), "plan already closed");
        _plans[planIdx].closed = true;
        emit PlanClosed(planIdx);
    }

    /// @inheritdoc ISubscriptionService
    function openPlan(uint planIdx) external onlyOwner planMustExist(planIdx) {
        require(!_planDisabled(planIdx), "plan disabled");
        require(_planClosed(planIdx), "plan not closed");
        _plans[planIdx].closed = false;
        emit PlanOpened(planIdx);
    }

    /**
     * @notice Withdraws an allowed part of the contract's balance to the {receiver}
     * @dev Makes a transfer to the {receiver} of all amount specified at 'paidAmount' state variable.
     * that contains the amount of ETH that was paid by users while charging.
     * Throws if the {receiver} is the zero address
     * Throws if there's nothing to withdraw
     * Throws if the transfer failed     
     * @param receiver The address of the receiver
     */
    function withdrawPayments(address receiver) external onlyOwner {
        uint currentPaidAmount = paidAmount;
        require(currentPaidAmount > 0, "nothing to withdraw");
        require(receiver != address(0), "receiver is zero address");
        paidAmount = 0;
        require(_transfer(receiver, currentPaidAmount), "failed transfer");
    }

    /**
     * @dev Check if the account has a subscription based on 'createdAt' timestamp
     * @param account Account's address to check
     * @return bool Is the account's subscribed
     */
    function _subscribed(address account) internal view returns(bool) {
        return _subscriptions[account].createdAt != 0;
    }

    /**
     * @dev Checks if the account's subscription is cancelled based on 'cancelledAt' timestamp
     * @param account Account's address to check
     *        MUST be subscribed
     * @return bool Is the account's subscription cancelled
     */
    function _cancelled(address account) internal view returns(bool) {
        return _subscriptions[account].cancelledAt != 0;
    }

    /**
     * @dev Checks if the plan is closed based on 'closed' value
     * @param planIdx The index of the plan
     *        MUST be in range [0; _plans.length)
     * @return bool Is the plan closed
     */
    function _planClosed(uint planIdx) internal view returns(bool) {
        return _plans[planIdx].closed;
    }

    /**
     * @dev Checks if the {planIdx} exists based on 'length' of the _plans array
     * @param planIdx The index of the plan
     * @return bool Is the plan exists
     */
    function _planExists(uint planIdx) internal view returns(bool) {
        return planIdx < _plans.length;
    }

    /**
     * @dev Checks if the plan is disabled based on 'disabledAt' timestamp
     * @param planIdx The index of the plan
     *        MUST be in range [0; _plans.length)
     * @return bool Is the plan disabled
     */
    function _planDisabled(uint planIdx) internal view returns(bool) {
        return _plans[planIdx].disabledAt != 0;
    }

    /**
     * @dev erases old subscription data and stores new one
     * Emits {Subscribed} event
     * @param account The address of the account
     * @param timestamp The timestamp when subscription was created
     * @param planIdx The index of the plan
     * @param trial The trial period in seconds
     */
    function _subscribe(address account, uint timestamp, uint planIdx, uint trial) internal {
        _subscriptions[account] = Subscription({
            createdAt: timestamp,
            planIdx: planIdx,
            startedAt: timestamp + trial,
            cancelledAt: 0,
            chargedPeriods: 0
        });

        emit Subscribed(msg.sender, planIdx);
    }

    /**
     * @dev set new subscription's 'startedAt' timestamp, resets chargedPeriods and cancelledAt
     * Emits {Restored} event
     * @param account The address of the account
     *        MUST be subscribed
     * @param timestamp The timestamp to set as new 'startedAt'
     * @param planIdx The index of the plan
     */
    function _restore(address account, uint timestamp, uint planIdx) internal {
        Subscription storage subscription = _subscriptions[account];
        subscription.startedAt = timestamp;
        subscription.cancelledAt = 0;
        subscription.chargedPeriods = 0;

        emit Restored(account, planIdx);
    }

    /**
     * @dev set the subscription's 'cancelledAt' timestamp
     * Emits {Cancelled} event
     * @param account The address of the account
     *        MUST be subscribed
     * @param timestamp The timestamp to set
     * @param planIdx The index of the plan
     */
    function _cancel(address account, uint timestamp, uint planIdx) internal {
        _subscriptions[account].cancelledAt = timestamp;
        emit Cancelled(account, planIdx);
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

    function _increaseBalance(address account, uint value) internal {
        _balances[account] += value;
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
        (uint amountToCharge, uint periodsToCharge, ) = previewCharge(account, true);
        if (periodsToCharge > 0) {
            _charge(
                account, 
                account, 
                planIdx, 
                amountToCharge, 
                periodsToCharge, 
                amountToCharge > 0
            );
        }

        if (_planDisabled(planIdx)) return;

        Plan storage plan = _plans[planIdx];
        uint rate = plan.rate;
        uint period = plan.period;
        uint balance = balanceOf(account);

        uint fundedUntil = _calcFundedUntil(subscription.startedAt, subscription.chargedPeriods, balance, rate, period);

        // Don't restore if the subscription is still active
        if (block.timestamp < fundedUntil) return;

        fundedUntil = _calcFundedUntil(block.timestamp, 0, balance + amount, rate, period);

        // Restore if the subscription will be activated after adding the deposit to the balance
        // Otherwise the contract owner will be able to abuse by charging for inactive periods
        if (block.timestamp < fundedUntil) {
            _restore(account, block.timestamp, planIdx);
        }
    }

    /**
     * @dev a hook, called after executing deposit
     * @param account Address of the account
     * @param amount Amount to deposit
     */
    function _afterDeposit(address account, uint amount) internal virtual {}

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
     * @param periodsToCharge Total number of periods to charge
     * @param discountPercent Discount to apply to the rate
     *        MUST be less than or equal to 100
     * @param rate Desired rate to charge for the period
     * @return amountToCharge Total ETH amount to charge for all considered periods (taking into account the discount)
     * @return adjustedRate Rate to charge for the period
     */
    function _calcCharge(
        uint periodsToCharge,
        uint discountPercent,
        uint rate
    ) internal pure returns(
        uint amountToCharge, 
        uint adjustedRate
    ) {
        if (discountPercent == 0) {
            adjustedRate = rate;
        } else {
            uint percent;
            unchecked {
                // will never overflows, {discountPercent} restricted to 0-100 a-priory
                percent = 100 - discountPercent;
            }
            adjustedRate = rate.mulDiv(percent, 100);
        }
        amountToCharge = periodsToCharge * adjustedRate;
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
        uint maxUntilAt,
        uint cancelledAt,
        uint chargedPeriods,
        uint planDisabledAt,
        uint period,
        uint rate,
        uint balance
    ) internal pure returns(uint) {
        // Calculates the number of complete periods that have passed since the subscription started
        uint countedPeriods = _calcCountedPeriods(
            startedAt,
            maxUntilAt,
            planDisabledAt,
            cancelledAt,
            period
        );

        // Debt periods are 0 if there has been charged as many periods as have passed
        if (countedPeriods <= chargedPeriods) return 0;

        uint unchargedPeriods;
        unchecked {
            // never overflows, checked above
            unchargedPeriods = countedPeriods - chargedPeriods;
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
     */
    function _calcCountedPeriods(
        uint startedAt,
        uint maxUntilAt,
        uint planDisabledAt,
        uint cancelledAt,
        uint period
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

        return (timePassed / period) + 1;
    }

    /**
     * @dev Calculates how long the subscription will be active based on the balance
     * @param startedAt Timestamp at which the subscription started
     * @param chargedPeriods Number of periods that have been charged
     * @param balance Current balance of the account
     * @param rate Amount of ETH to charge for each period
     *        MUST NOT be 0
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