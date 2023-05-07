// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/**
 * @dev
 */
interface IStandaloneSubscriptionService {
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
    }

    struct Subscription {
        uint planIdx;
        uint createdAt;
        uint startedAt;
        uint chargedPeriods;
        uint cancelledAt;
    }

    /**
     * @notice Deposit ETH to the contract
     * @dev executes to deposit ETH to the contract even if it's unsafe. 
     * Unsafe indicates that there are uncharged subscription periods for the account. 
     * This function of depositing permits the owner to charge for all past periods, even if the subscription was inactive.
     * To avoid this, the user should call safeDeposit() that restricts depositing if there's a debt.
     * In this case, the user has following options:
     * - should call charge() to pay for all uncharged periods when the subscription was active
     * - should cancel the current subscription (cancel() will pay for all uncharged periods when the subcription was active)
     * and then subscribe again (or restore)
     */
    function deposit() external payable;
    function withdraw(uint amount) external;

    function balanceOf(address account) external view returns (uint);
    function reservedOf(address account) external view returns (uint);
    function maxWithdrawAmount(address account) external view returns (uint);
    function subscriptionOf(address account) external view returns (Subscription memory);

    function isValid(address account) external view returns (bool);
    function validUntil(address account) external view returns (uint);
    function nextAvailableChargeAt(address account) external view returns (uint);
    
    function subscribe(uint planIdx) external;
    function cancel() external;
    function restore() external;

    function charge(address account) external;
    function charge(address[] calldata accounts) external;

    function getPlan(uint planIdx) external view returns (Plan memory);
    function addPlan(
        uint period,
        uint trial,
        uint rate,
        uint chargeDiscount
    ) external;
    function disablePlan(uint planIdx) external;
    function closePlan(uint planIdx) external;

    function changeRecipient(address newRecipient) external;
}