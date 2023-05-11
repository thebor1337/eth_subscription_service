// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// TODO пометить что throws (какие кастомные ошибки)

interface IStandaloneSubscriptionService {

    /**
     * @dev The plan is a set of parameters that define the conditions for creating a subscription,
     * recognizing a subscription as valid, and charging for a subscription.
     * @param period The duration of the interval after which a subscription can change its state depending on different conditions
     *        MUST be greater than 0
     * @param trial The duration of the period when a subscription is considered active, but ETH for its use cannot be charged
     *        If not trial period is needed, set to 0
     * @param rate The amount of ETH that will be charged for each period.
     *        MUST be greater than 0
     * @param disabledAt The timestamp after which the plan will be considered disabled.
     *        Disabled state means that the plan is no longer available for new subscriptions
     *        and all active subscriptions will expire automatically from the end of the period 
     *        following the time at which the plan was disabled
     *        Default: 0 (not disabled)
     * @param chargeDiscount The discount that will be applied to the amount of ETH that will be charged for each period,
     *        if the charge operator is the same as the subscription owner
     *        MUST be in the range from 0 to 100 (0% to 100%)
     * @param closed The flag that indicates whether the plan is closed.
     *        Closed state means that the plan is no longer available for new subscriptions
     */
    struct Plan {
        uint period;
        uint trial;
        uint rate;
        uint disabledAt;
        uint chargeDiscount;
        bool closed;
    }

    /**
     * @dev A subscription is a set of parameters that define the state of a subscription and regulates the charging rules
     * @param planIdx The index of the plan in the plans array
     * @param createdAt The timestamp at which the subscription was created
     *        MUST NOT be 0. 0 means that the subscription does not exist
     * @param startedAt The timestamp at which the subscription was started to use, or restored
     *        MUST NOT be 0. The value is used to calculate the number of periods that have passed since the start of the subscription
     *        and how much ETH should be charged for the subscription
     * @param chargedPeriods The number of periods that have been charged for the subscription
     *        Default: 0 (no periods charged)
     *        The value can be reset to 0 if the subscription is restored
     * @param cancelledAt The timestamp at which the subscription was cancelled
     *        Default: 0 (not cancelled)
     */
    struct Subscription {
        uint planIdx;
        uint createdAt;
        uint startedAt;
        uint chargedPeriods;
        uint cancelledAt;
    }

    /**
     * @dev Emitted when an account deposits ETH to the contract
     * @param account The address of the account
     * @param amount The amount of ETH that was deposited
     */
    event Deposit(address indexed account, uint amount);

    /** 
     * @dev Emitted when an account withdraws ETH from the contract
     * @param account The address of the account
     * @param amount The amount of ETH that was withdrawn
     */
    event Withdraw(address indexed account, uint amount);

    /**
     * @dev Emitted when an account subscribes to a plan
     * @param account The address of the account
     * @param planIdx The index of the plan in the plans array
     */
    event Subscribed(address indexed account, uint indexed planIdx);

    /**
     * @dev Emitted when a subscription was canceled
     * @param account The address of the account
     * @param planIdx The index of the plan in the plans array
     */
    event Cancelled(address indexed account, uint indexed planIdx);

    /**
     * @dev Emitted when a subscription was restored
     * @param account The address of the account
     * @param planIdx The index of the plan in the plans array
     */
    event Restored(address indexed account, uint indexed planIdx);

    /**
     * @dev Emitted when an account was charged
     * @param account The address of the account
     * @param operator The address of the operator that charged the account
     * @param planIdx The index of the plan in the plans array
     * @param periods The number of periods that were charged
     * @param amount The amount of ETH that was charged
     */
    event Charged(address indexed account, address indexed operator, uint indexed planIdx, uint periods, uint amount);

    /**
     * @dev Emitted when a new plan is added
     * @param planIdx The index of the plan in the plans array
     */
    event PlanAdded(uint indexed planIdx);

    /**
     * @dev Emitted when a plan at index {planIdx} is disabled
     * @param planIdx The index of the plan in the plans array
     */
    event PlanDisabled(uint indexed planIdx);
    
    /**
     * @dev Emitted when a plan at index {planIdx} is closed
     * @param planIdx The index of the plan in the plans array
     */
    event PlanClosed(uint indexed planIdx);

    /**
     * @dev Emitted when a plan at index {planIdx} is opened
     * @param planIdx The index of the plan in the plans array
     */
    event PlanOpened(uint indexed planIdx);

    /**
     * @dev Emitted when the recipient is changed
     * Recipient is the address that receives the funds from charges
     * @param oldRecipient The old recipient address
     * @param newRecipient The new recipient address
     */
    event RecipientChanged(address indexed oldRecipient, address indexed newRecipient);

    error InsufficientBalance(uint available, uint required);
    error AlreadySubscribed();
    error NotSubscribed();
    error NotCancelled();
    error AlreadyCancelled();
    error PlanUnavailable();
    error NothingToCharge();

    /**
     * @param account The address of the account
     * @return amount The balance of the account
     */
    function balanceOf(address account) external view returns (uint);

    /**
     * @dev The reserved amount is the amount that is reserved to pay for debt periods,
     * or to pay for the current (already started) period
     * @param account The address of the account
     * @return amount The reserved amount of the account
     */
    function reservedOf(address account) external view returns (uint);

    /**
     * @param account The address of the account
     * @return amount max(0, {balanceOf} - {reservedOf})
     */
    function availableBalanceOf(address account) external view returns (uint);

    /**
     * @dev throws if there's no subscription associated with the account
     * @param account The address of the account
     * @return subscription {Subcription} object associated with the account
     */
    function subscriptionOf(address account) external view returns (Subscription memory);

    /**
     * @dev A subscription is considered valid if:
     * - all used periods are charged (including the current)
     * - there is enough ETH on the balance to charge for all used periods (including the current)
     *
     * A subscription is not considered valid if none of the validity conditions are met, or:
     * - the subscription has been canceled
     * - the plan linked to the subscription has been disabled.
     *
     * If one of the invalidation conditions is met, the subscription is still considered valid until the last valid period has expired
     *
     * Throws, if there's no subscription associated with the account
     * @param account The address of the account
     * @return isValid Whether the subscription is valid
     */
    function isValid(address account) external view returns (bool);

    /**
     * @dev Throws if there's no subscription associated with the account
     * @param account The address of the account
     * @return validUntil The timestamp until which the subscription will be considered valid
     */
    function validUntil(address account) external view returns (uint);

    /** 
     * @dev Throws if there's no subscription associated with the account
     * @param account The address of the account
     * @return nextAvailableChargeAt If there is a debt, returns 0. Otherwise, returns the timestamp at which the next charge will be available
    */
    function nextAvailableChargeAt(address account) external view returns (uint);
    
    /**
     * @notice Deposit ETH to the contract and add it to the balance of the sender.
     * @dev Calling this function also adds the following functionality: 
     * if there is an inactive subscription due to insufficient balance, 
     * the subscription will be restored if the deposit amount permits to pay for a new subscription period. 
     * No action will be taken if the subscription has been canceled or the associated plan has been disabled.
     *
     * Emits an {Deposited} event always
     * Emits an {Restored} event if the subscription is restored
     */
    function deposit() external payable;
    
    /**
     * @notice Withdraw ETH from the contract and subtract it from the balance of the sender.
     * @dev Withdraws {amount} ETH from the contract if {reservedOf} is less than {amount}. 
     * As a result, the user cannot withdraw money that is reserved to pay for debt periods, 
     * or to pay for the current (already started) period
     *
     * Throws, if it's impossible to withdraw the specified amount
     * @param amount The amount of ETH to withdraw
     */
    function withdraw(uint amount) external;

    /**
     * @notice Subscribes to the plan with the specified index in the plans array
     * @dev Subscribes to the specified plan if all of the following conditions are met:
     * - No active (not canceled) subscription
     * - If there is an active subscription, but the plan associated with that subscription is no longer active
     * - If the specified plan is not disabled
     * - If the specified plan is open
     * - If the subscription has a trial period, the account has enough ETH to charge the first period after the trial period expires
     * - If the subscription does not have a trial period, the account has enough ETH to charge the first period
     *
     * In case of a successful subscription, the data on the previous subscription is erased. 
     * If the plan does not have a trial period, it charges the first period instantly without a self-charge discount.
     *
     * Emits {Subscribed} event, if the function finished without revert
     * Emits {Cancelled} event, if there was an active subscription with an inactive plan associated with it
     * Emits {Charged} event, if a charge was made (if there's no trial period)
     *
     * Throws, if the specified plan is not active or not open anymore
     * Throws, if there's already an active subscription associated with the account, 
     *         the subscription is not cancelled and the associated plan is still active
     * @param planIdx The array's index of the required plan
     */
    function subscribe(uint planIdx) external;

    /**
     * @notice Cancels the current subscription     
     * @dev Cancels the current subscription and charges for all debt periods with a self-charge discount applied
     *
     * Emits {Cancelled} event, if the function finished without revert
     * Emits {Charged} event, if there was a debt and it was successfully charged
     *
     * Throws, if there's no active subscription associated with the account
     * Throws, if the subscription has already been canceled
     */
    function cancel() external;

    /**
     * @notice Restores the current subscription
     * @dev Restores the current subscription if all of the following conditions are met:
     * - The subscription was cancelled before
     * - The plan associated with the subscription is still active
     * - The account has enough ETH to charge for the *first* period
     *
     * Emits {Restored} event, if the function finished without revert
     * Emits {Charged} event, it was successfully charged for the *first* period
     *
     * Throws, if there's no subscription associated with the account
     * Throws, if the subscription has not been canceled before
     * Throws, if the plan associated with the subscription is no longer active
     * Throws, if the account does not have enough ETH to charge for the *first* period
     *
     * P.S. - The first period is a period after the subscription was restored
     */
    function restore() external;

    /**
     * @dev Charges for all debt periods. 
     * If the function was called by the owner of the subscription, the charge is executed using the discount specified by the associated plan.
     *
     * Debt periods - periods when the subscription is/was active. The calculation takes into account the following factors:
     * - State of account's balance. 
     *   If the balance is only enough for {N} periods, 
     *   the subscription will be active only for these N periods. 
     *   If {M} of these periods have already been charged, then {debt period = N - M}
     * - State of the subscription. 
     *   If the subscription has been cancelled, 
     *   only those periods prior to the time of cancellation count toward debt periods. 
     *   For example, if the plan's period is 1 month, and the subscription was canceled after 6 weeks, 
     *   then {debt periods = 2} (for 2 full months, since even if the subscription is canceled not at the end of its expiration, 
     *   the user can continue with it use to the end)
     * - State of the plan. 
     *   If the plan has been disabled, the subscription will expire automatically 
     *   from the end of the period following the time at which the plan was disabled (same as in case of subscription's cancellation)
     *
     * Emits {Charged} event, if the function finished without revert
     *
     * Throws, if there's no subscription associated with the account
     * Throws, if there's no debt periods to charge
     * Throws, if the account does not have enough ETH to charge
     * @param account The address of the account
     */
    function charge(address account) external;

    /**
     * @notice Charges a batch of accounts for all debt periods
     * @dev Do the same as charge(address), but handles a batch of accounts. Can be used to save gas.
     * If any of the specified addresses does not fulfill the conditions of the charge 
     * (not subscribed, the plan is inactive, does not have enough funds, etc.), 
     * the function will not throw, it will skip all non-compliant accounts. 
     * However, if none of the listed accounts qualify, it throws.
     *
     * Emits {Charged} event for all accounts that has been charged successfully
     *
     * Throws, if none of the specified accounts qualify for the charge
     * @param accounts The array of addresses of the accounts
     */
    function chargeMany(address[] calldata accounts) external;

    /**
     * @param planIdx The array's index of the required plan
     * @return plan {Plan} object of associated with the index in the plans array
     */
    function getPlan(uint planIdx) external view returns (Plan memory);

    /**
     * @notice Adds a new plan
     * @dev Adds a new plan to the plans array.
     * 
     * Emits {PlanAdded} event
     *
     * Throws, if some of the parameters are not valid
     *
     * @param period The period of the plan in seconds. MUST be not 0
     * @param trial The trial period of the plan in seconds. 0, if the plan does not have a trial period
     * @param rate Amount of ETH to be charged per period. MUST be not 0
     * @param chargeDiscount The discount to be applied to the self-charge. MUST be in [0;100]
     */
    function addPlan(
        uint period,
        uint trial,
        uint rate,
        uint chargeDiscount
    ) external;

    /**
     * @notice Disables the plan
     * @dev Disables the plan at {planIdx} in plans array. 
     * 
     * Emits {PlanDisabled} event
     *
     * Throws, if the plan has already been disabled
     * @param planIdx The array's index of the required plan
     */
    function disablePlan(uint planIdx) external;

    /**
     * @notice Closes the plan
     * @dev Closes the plan at {planIdx} in plans array.
     *
     * Emits {PlanClosed} event
     * 
     * Throws, if the plan has been disabled
     * Throws, if the plan has already been closed
     * @param planIdx The array's index of the required plan
     */
    function closePlan(uint planIdx) external;

    /**
     * @notice Opens the plan
     * @dev Opens the plan at {planIdx} in plans array.
     * 
     * Emits {PlanOpened} event
     * 
     * Throws, if the plan has been disabled
     * Throws, if the plan has not been closed
     * @param planIdx The array's index of the required plan
     */
    function openPlan(uint planIdx) external;
}