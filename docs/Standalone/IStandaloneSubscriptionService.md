# IStandaloneSubscriptionService









## Methods

### addPlan

```solidity
function addPlan(uint256 period, uint256 trial, uint256 rate, uint256 chargeDiscount) external nonpayable
```

Adds a new plan

*Adds a new plan to the plans array.  Emits {PlanAdded} event Throws, if some of the parameters are not valid*

#### Parameters

| Name | Type | Description |
|---|---|---|
| period | uint256 | The period of the plan in seconds. MUST be not 0 |
| trial | uint256 | The trial period of the plan in seconds. 0, if the plan does not have a trial period |
| rate | uint256 | Amount of ETH to be charged per period. MUST be not 0 |
| chargeDiscount | uint256 | The discount to be applied to the self-charge. MUST be in [0;100] |

### availableBalance

```solidity
function availableBalance(address account) external view returns (uint256)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | amount max(0, {balanceOf} - {reservedOf}) |

### balanceOf

```solidity
function balanceOf(address account) external view returns (uint256)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | amount The balance of the account |

### cancel

```solidity
function cancel() external nonpayable
```

Cancels the current subscription     

*Cancels the current subscription and charges for all debt periods with a self-charge discount applied Emits {Cancelled} event, if the function finished without revert Emits {Charged} event, if there was a debt and it was successfully charged Throws, if there&#39;s no active subscription associated with the account Throws, if the subscription has already been canceled*


### charge

```solidity
function charge(address[] accounts) external nonpayable
```

Charges a batch of accounts for all debt periods

*Do the same as charge(address), but handles a batch of accounts. Can be used to save gas. If any of the specified addresses does not fulfill the conditions of the charge  (not subscribed, the plan is inactive, does not have enough funds, etc.),  the function will not throw, it will skip all non-compliant accounts.  However, if none of the listed accounts qualify, it throws. Emits {Charged} event for all accounts that has been charged successfully Throws, if none of the specified accounts qualify for the charge*

#### Parameters

| Name | Type | Description |
|---|---|---|
| accounts | address[] | The array of addresses of the accounts |

### charge

```solidity
function charge(address account) external nonpayable
```



*Charges for all debt periods.  If the function was called by the owner of the subscription, the charge is executed using the discount specified by the associated plan. Debt periods - periods when the subscription is/was active. The calculation takes into account the following factors: - State of account&#39;s balance.    If the balance is only enough for {N} periods,    the subscription will be active only for these N periods.    If {M} of these periods have already been charged, then {debt period = N - M} - State of the subscription.    If the subscription has been cancelled,    only those periods prior to the time of cancellation count toward debt periods.    For example, if the plan&#39;s period is 1 month, and the subscription was canceled after 6 weeks,    then {debt periods = 2} (for 2 full months, since even if the subscription is canceled not at the end of its expiration,    the user can continue with it use to the end) - State of the plan.    If the plan has been disabled, the subscription will expire automatically    from the end of the period following the time at which the plan was disabled (same as in case of subscription&#39;s cancellation) Emits {Charged} event, if the function finished without revert Throws, if there&#39;s no subscription associated with the account Throws, if there&#39;s no debt periods to charge Throws, if the account does not have enough ETH to charge*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

### closePlan

```solidity
function closePlan(uint256 planIdx) external nonpayable
```

Closes the plan

*Closes the plan at {planIdx} in plans array. Emits {PlanClosed} event  Throws, if the plan has been disabled Throws, if the plan has already been closed*

#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx | uint256 | The array&#39;s index of the required plan |

### deposit

```solidity
function deposit() external payable
```

Deposit ETH to the contract and add it to the balance of the sender.

*Calling this function also adds the following functionality:  if there is an inactive subscription due to insufficient balance,  the subscription will be restored if the deposit amount permits to pay for a new subscription period.  No action will be taken if the subscription has been canceled or the associated plan has been disabled. Emits an {Deposited} event always Emits an {Restored} event if the subscription is restored*


### disablePlan

```solidity
function disablePlan(uint256 planIdx) external nonpayable
```

Disables the plan

*Disables the plan at {planIdx} in plans array.   Emits {PlanDisabled} event Throws, if the plan has already been disabled*

#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx | uint256 | The array&#39;s index of the required plan |

### getPlan

```solidity
function getPlan(uint256 planIdx) external view returns (struct IStandaloneSubscriptionService.Plan)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx | uint256 | The array&#39;s index of the required plan |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | IStandaloneSubscriptionService.Plan | plan {Plan} object of associated with the index in the plans array |

### isPlanActive

```solidity
function isPlanActive(uint256 planIdx) external view returns (bool)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx | uint256 | The index of the plan in the plans array |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | bool | bool Wheather the plan is active (not disabled and not closed) |

### isValid

```solidity
function isValid(address account) external view returns (bool)
```



*A subscription is considered valid if: - all used periods are charged (including the current) - there is enough ETH on the balance to charge for all used periods (including the current) A subscription is not considered valid if none of the validity conditions are met, or: - the subscription has been canceled - the plan linked to the subscription has been disabled. If one of the invalidation conditions is met, the subscription is still considered valid until the last valid period has expired Throws, if there&#39;s no subscription associated with the account*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | bool | isValid Whether the subscription is valid |

### nextAvailableChargeAt

```solidity
function nextAvailableChargeAt(address account) external view returns (uint256)
```



*Throws if there&#39;s no subscription associated with the account*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | nextAvailableChargeAt If there is a debt, returns 0. Otherwise, returns the timestamp at which the next charge will be available |

### openPlan

```solidity
function openPlan(uint256 planIdx) external nonpayable
```

Opens the plan

*Opens the plan at {planIdx} in plans array.  Emits {PlanOpened} event  Throws, if the plan has been disabled Throws, if the plan has not been closed*

#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx | uint256 | The array&#39;s index of the required plan |

### reservedOf

```solidity
function reservedOf(address account) external view returns (uint256)
```



*The reserved amount is the amount that is reserved to pay for debt periods, or to pay for the current (already started) period*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | amount The reserved amount of the account |

### restore

```solidity
function restore() external nonpayable
```

Restores the current subscription

*Restores the current subscription if all of the following conditions are met: - The subscription was cancelled before - The plan associated with the subscription is still active - The account has enough ETH to charge for the *first* period Emits {Restored} event, if the function finished without revert Emits {Charged} event, it was successfully charged for the *first* period Throws, if there&#39;s no subscription associated with the account Throws, if the subscription has not been canceled before Throws, if the plan associated with the subscription is no longer active Throws, if the account does not have enough ETH to charge for the *first* period P.S. - The first period is a period after the subscription was restored*


### subscribe

```solidity
function subscribe(uint256 planIdx) external nonpayable
```

Subscribes to the plan with the specified index in the plans array

*Subscribes to the specified plan if all of the following conditions are met: - No active (not canceled) subscription - If there is an active subscription, but the plan associated with that subscription is no longer active - If the specified plan is not disabled - If the specified plan is open - If the subscription has a trial period, the account has enough ETH to charge the first period after the trial period expires - If the subscription does not have a trial period, the account has enough ETH to charge the first period In case of a successful subscription, the data on the previous subscription is erased.  If the plan does not have a trial period, it charges the first period instantly without a self-charge discount. Emits {Subscribed} event, if the function finished without revert Emits {Cancelled} event, if there was an active subscription with an inactive plan associated with it Emits {Charged} event, if a charge was made (if there&#39;s no trial period) Throws, if the specified plan is not active or not open anymore Throws, if there&#39;s already an active subscription associated with the account,          the subscription is not cancelled and the associated plan is still active*

#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx | uint256 | The array&#39;s index of the required plan |

### subscriptionOf

```solidity
function subscriptionOf(address account) external view returns (struct IStandaloneSubscriptionService.Subscription)
```



*throws if there&#39;s no subscription associated with the account*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | IStandaloneSubscriptionService.Subscription | subscription {Subcription} object associated with the account |

### validUntil

```solidity
function validUntil(address account) external view returns (uint256)
```



*Throws if there&#39;s no subscription associated with the account*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | validUntil The timestamp until which the subscription will be considered valid |

### withdraw

```solidity
function withdraw(uint256 amount) external nonpayable
```

Withdraw ETH from the contract and subtract it from the balance of the sender.

*Withdraws {amount} ETH from the contract if {reservedOf} is less than {amount}.  As a result, the user cannot withdraw money that is reserved to pay for debt periods,  or to pay for the current (already started) period Throws, if it&#39;s impossible to withdraw the specified amount*

#### Parameters

| Name | Type | Description |
|---|---|---|
| amount | uint256 | The amount of ETH to withdraw |



## Events

### Cancelled

```solidity
event Cancelled(address indexed account, uint256 indexed planIdx)
```



*Emitted when a subscription was canceled*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account `indexed` | address | The address of the account |
| planIdx `indexed` | uint256 | The index of the plan in the plans array |

### Charged

```solidity
event Charged(address indexed account, address indexed operator, uint256 indexed planIdx, uint256 periods, uint256 amount)
```



*Emitted when an account was charged*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account `indexed` | address | The address of the account |
| operator `indexed` | address | The address of the operator that charged the account |
| planIdx `indexed` | uint256 | The index of the plan in the plans array |
| periods  | uint256 | The number of periods that were charged |
| amount  | uint256 | The amount of ETH that was charged |

### Deposit

```solidity
event Deposit(address indexed account, uint256 amount)
```



*Emitted when an account deposits ETH to the contract*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account `indexed` | address | The address of the account |
| amount  | uint256 | The amount of ETH that was deposited |

### PlanAdded

```solidity
event PlanAdded(uint256 indexed planIdx)
```



*Emitted when a new plan is added*

#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx `indexed` | uint256 | The index of the plan in the plans array |

### PlanClosed

```solidity
event PlanClosed(uint256 indexed planIdx)
```



*Emitted when a plan at index {planIdx} is closed*

#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx `indexed` | uint256 | The index of the plan in the plans array |

### PlanDisabled

```solidity
event PlanDisabled(uint256 indexed planIdx)
```



*Emitted when a plan at index {planIdx} is disabled*

#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx `indexed` | uint256 | The index of the plan in the plans array |

### PlanOpened

```solidity
event PlanOpened(uint256 indexed planIdx)
```



*Emitted when a plan at index {planIdx} is opened*

#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx `indexed` | uint256 | The index of the plan in the plans array |

### RecipientChanged

```solidity
event RecipientChanged(address indexed oldRecipient, address indexed newRecipient)
```



*Emitted when the recipient is changed Recipient is the address that receives the funds from charges*

#### Parameters

| Name | Type | Description |
|---|---|---|
| oldRecipient `indexed` | address | The old recipient address |
| newRecipient `indexed` | address | The new recipient address |

### Restored

```solidity
event Restored(address indexed account, uint256 indexed planIdx)
```



*Emitted when a subscription was restored*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account `indexed` | address | The address of the account |
| planIdx `indexed` | uint256 | The index of the plan in the plans array |

### Subscribed

```solidity
event Subscribed(address indexed account, uint256 indexed planIdx)
```



*Emitted when an account subscribes to a plan*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account `indexed` | address | The address of the account |
| planIdx `indexed` | uint256 | The index of the plan in the plans array |

### Withdraw

```solidity
event Withdraw(address indexed account, uint256 amount)
```



*Emitted when an account withdraws ETH from the contract*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account `indexed` | address | The address of the account |
| amount  | uint256 | The amount of ETH that was withdrawn |



## Errors

### AlreadyCancelled

```solidity
error AlreadyCancelled()
```






### InsufficientBalance

```solidity
error InsufficientBalance(uint256 available, uint256 required)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| available | uint256 | undefined |
| required | uint256 | undefined |

### NotCancelled

```solidity
error NotCancelled()
```






### NotSubscribed

```solidity
error NotSubscribed()
```






### NothingToCharge

```solidity
error NothingToCharge()
```






### PlanUnavailable

```solidity
error PlanUnavailable()
```







