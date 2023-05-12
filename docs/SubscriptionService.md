# SubscriptionService









## Methods

### addPlan

```solidity
function addPlan(uint256 period, uint256 trial, uint256 rate, uint256 chargeDiscount) external nonpayable
```

Adds a new plan

*Pushes a new plan object to the plans array.  Emits {PlanAdded} event Throws, if some of the parameters are not valid*

#### Parameters

| Name | Type | Description |
|---|---|---|
| period | uint256 | The period of the plan in seconds. MUST be NOT 0 |
| trial | uint256 | The trial period of the plan in seconds. 0, if the plan does not have a trial period |
| rate | uint256 | Amount of ETH to be charged per period. MUST be NOT 0 |
| chargeDiscount | uint256 | The discount to be applied to the self-charge. MUST be IN [0;100] |

### availableBalanceOf

```solidity
function availableBalanceOf(address account) external view returns (uint256)
```

Get the amount of ETH that is available and not reserved for further charging

*Can be used as max amount that is available for withdrawal. Calculates by formula: max(0, {balanceOf} - {reservedOf})*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | uint The available balance of the account |

### balanceOf

```solidity
function balanceOf(address account) external view returns (uint256)
```

Get the current amount of ETH of the {account}

*Calculates as {deposited amount} - {withdrawn amount}*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | uint The balance of the account |

### cancel

```solidity
function cancel() external nonpayable
```

Cancels the current subscription     

*Cancels the current subscription and charges for all debt periods with a self-charge discount applied Emits {Cancelled} event, if the function finished without revert Emits {Charged} event, if there was a debt and it was successfully charged Throws, if there&#39;s no active subscription associated with the account Throws, if the subscription has already been canceled*


### charge

```solidity
function charge(address account) external nonpayable
```

Charges for all uncharged periods

*If the function was called by the owner of the subscription, the charge is executed using the discount specified by the associated plan. Uncharged periods - periods when the subscription considered as active. The calculation takes into account the following factors: 1) State of account&#39;s balance.    If the balance is only enough for {N} periods,    the subscription will be active only for these N periods.    If {M} of these periods have already been charged, then {uncharged periods = N - M} 2) State of the subscription.    If the subscription has been cancelled,    only those periods prior to the time of cancellation count toward uncharged periods.    For example, if the plan&#39;s period is 1 month, and the subscription was canceled after 6 weeks,    then {uncharged periods = 2} (for 2 full months, since even if the subscription is canceled not at the end of its expiration,    the user can continue to use it until the expiration timestamp) 3) State of the plan.    If the plan has been disabled, the subscription will expire automatically    starting from the end of the period following the timestamp at which the plan was disabled (same as in case of subscription&#39;s cancellation) Emits {Charged} event Throws, if there&#39;s no subscription associated with the account Throws, if there&#39;s no uncharged periods*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

### chargeMany

```solidity
function chargeMany(address[] accounts) external nonpayable
```

Charges a batch of accounts for all uncharged periods

*Do the same as charge(address), but handles a batch of accounts. Can be used to save gas. If any of the specified addresses does not fulfill the conditions of the charge  (not subscribed, does not have enough funds, etc.),  the function will not throw, it will skip all non-compliant accounts.  However, if none of the listed accounts qualify, it throws. Emits {Charged} event for all accounts that has been charged successfully Throws, if none of the specified accounts qualify for the charge*

#### Parameters

| Name | Type | Description |
|---|---|---|
| accounts | address[] | The array of addresses of the accounts |

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

*Calling this function also adds the following functionality:  if there is an inactive subscription due to insufficient balance,  the subscription will be restored if the deposited amount permits to pay for a new subscription period.  No action, except depositing to the balance, will be taken if the subscription has been canceled or the associated plan has been disabled. Emits an {Deposited} event Emits an {Restored} event if the subscription is restored*


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
function getPlan(uint256 planIdx) external view returns (struct ISubscriptionService.Plan)
```

Gets the plan at the specified index



#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx | uint256 | The array&#39;s index of the required plan |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | ISubscriptionService.Plan | Plan The plan&#39;s data |

### isValid

```solidity
function isValid(address account) external view returns (bool)
```

Whether the {account}&#39;s subscription is valid (can be considered as active)

*A subscription is considered valid if: - all used periods are charged (including the current) - there is enough ETH on the balance to charge for all used periods (including the current) A subscription is not considered valid if none of the validity conditions are met, or: - the subscription has been canceled - the plan linked to the subscription has been disabled. If one of the invalidation conditions is met, the subscription is still considered valid until the last valid period has expired Throws, if there&#39;s no subscription associated with the account*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | bool | bool Whether the subscription is valid |

### nextAvailableChargeAt

```solidity
function nextAvailableChargeAt(address account) external view returns (uint256)
```

Returns the timestamp at which the next charge will be available

*Throws if there&#39;s no subscription associated with the account*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | uint The timestamp at which the next charge will be available (0, if already available) |

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

### owner

```solidity
function owner() external view returns (address)
```



*Returns the address of the current owner.*


#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | address | undefined |

### paidAmount

```solidity
function paidAmount() external view returns (uint256)
```






#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | undefined |

### previewCharge

```solidity
function previewCharge(address account, bool makeDiscount) external view returns (uint256 amountToCharge, uint256 periodsToCharge, uint256 rate)
```

Calculates the charge data

*Calculates the charge data for the account based on the current state of the subscription and the plan.*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | Address of the account |
| makeDiscount | bool | Whether to apply discount |

#### Returns

| Name | Type | Description |
|---|---|---|
| amountToCharge | uint256 | Total ETH amount to charge for all considered periods (taking into account the discount) |
| periodsToCharge | uint256 | Total number of periods to charge |
| rate | uint256 | Rate to charge for the period (taking into account the discount) |

### renounceOwnership

```solidity
function renounceOwnership() external nonpayable
```



*Leaves the contract without owner. It will not be possible to call `onlyOwner` functions anymore. Can only be called by the current owner. NOTE: Renouncing ownership will leave the contract without an owner, thereby removing any functionality that is only available to the owner.*


### reservedOf

```solidity
function reservedOf(address account) external view returns (uint256)
```

Get amount of ETH that is reserved for further charging

*The reserved amount is the amount that is reserved to pay for uncharged (debt) periods. In other words, it&#39;s the amount that can&#39;t be withdrawn from the contract anymore. Only the contract&#39;s owner can withdraw it after charging the account.*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | uint The reserved amount of the account |

### restore

```solidity
function restore() external nonpayable
```

Restores the current subscription

*Restores the current subscription if all of the following conditions are met: - The subscription was cancelled before - The plan associated with the subscription is still not disabled - The account has enough ETH to charge for the first period Emits {Restored} event, if the function finished without revert Emits {Charged} event, it was successfully charged for the first period Throws, if there&#39;s no subscription associated with the account Throws, if the subscription has not been canceled before Throws, if the plan associated with the subscription is no longer active Throws, if the account does not have enough ETH to charge for the first period P.S. - The first period is a period after the subscription was restored*


### subscribe

```solidity
function subscribe(uint256 planIdx) external nonpayable
```

Subscribes to the plan at the specified index in the plans array

*Subscribes to the specified plan if all of the following conditions are met: 1) No active subscription (means there&#39;s no subscription at all, or the previous subscription must be cancelled first).  If there is an active subscription, it must be cancelled first. 3) If the specified plan is not disabled 4) If the specified plan is open 5) If the subscription has a trial period, the account has enough ETH to charge the first period after the trial period expires 6) If the subscription does not have a trial period, the account has enough ETH to charge the first period In case of a successful subscription, the data on the previous subscription is erased.  If the plan does not have a trial period, it charges the first period instantly without a self-charge discount. Emits {Subscribed} event, if the function finished without revert Emits {Charged} event, if a charge was made (if there&#39;s no trial period) Throws, if the specified plan is not active or not open anymore Throws, if there&#39;s already an active subscription associated with the account*

#### Parameters

| Name | Type | Description |
|---|---|---|
| planIdx | uint256 | The array&#39;s index of the required plan |

### subscriptionOf

```solidity
function subscriptionOf(address account) external view returns (struct ISubscriptionService.Subscription)
```

Get full subscription data associated with the {account}

*throws if there&#39;s no subscription associated with the account*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | ISubscriptionService.Subscription | Subscrition data object associated with the account |

### transferOwnership

```solidity
function transferOwnership(address newOwner) external nonpayable
```



*Transfers ownership of the contract to a new account (`newOwner`). Can only be called by the current owner.*

#### Parameters

| Name | Type | Description |
|---|---|---|
| newOwner | address | undefined |

### validUntil

```solidity
function validUntil(address account) external view returns (uint256)
```

Get timestamp until which the subscription will be considered valid

*Can be used to check when the subscription will expire Can be in the past, if the subscription is not valid anymore Throws if there&#39;s no subscription associated with the account*

#### Parameters

| Name | Type | Description |
|---|---|---|
| account | address | The address of the account |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | uint The timestamp until which the subscription will be considered valid |

### withdraw

```solidity
function withdraw(uint256 amount) external nonpayable
```

Withdraw ETH from the contract.

*Withdraws {amount} ETH from the contract if {reservedOf} is less than {amount}.  As a result, the user cannot withdraw ETH that is reserved to pay for uncharged periods Throws, if it&#39;s impossible to withdraw the specified amount Emits an {Withdrawn} event*

#### Parameters

| Name | Type | Description |
|---|---|---|
| amount | uint256 | The amount of ETH to withdraw |

### withdrawPayments

```solidity
function withdrawPayments(address receiver) external nonpayable
```

Withdraws an allowed part of the contract&#39;s balance to the {receiver}

*Makes a transfer to the {receiver} of all amount specified at &#39;paidAmount&#39; state variable. that contains the amount of ETH that was paid by users while charging. Throws if the {receiver} is the zero address Throws if there&#39;s nothing to withdraw Throws if the transfer failed     *

#### Parameters

| Name | Type | Description |
|---|---|---|
| receiver | address | The address of the receiver |



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

### OwnershipTransferred

```solidity
event OwnershipTransferred(address indexed previousOwner, address indexed newOwner)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| previousOwner `indexed` | address | undefined |
| newOwner `indexed` | address | undefined |

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






### AlreadySubscribed

```solidity
error AlreadySubscribed()
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






### PlanNotExists

```solidity
error PlanNotExists()
```






### PlanUnavailable

```solidity
error PlanUnavailable()
```







