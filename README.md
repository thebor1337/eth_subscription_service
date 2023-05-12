# Subscription Service

This project demonstrates how to make a subscription system in Ethereum.

# Introduction

The Ethereum Virtual Machine (EVM) currently lacks support for scheduled transactions, a crucial element for implementing a comprehensive subscription system without unnecessary logic and adapters.

The Value of Subscription Systems:
In the non-crypto world, subscription systems offer exceptional convenience from the user's perspective. By subscribing to desired services, users benefit from automatic and regular deductions without the need for confirmation on each transaction.

Challenges in Ethereum:
In Ethereum or any similar system, transactions must be initiated by someone who pays for the associated gas fees. However, should the burden fall on the subscription user? Consider the following reasons why this may not be optimal:

1. Unfair Burden: Users paying for subscriptions shouldn't also be responsible for covering gas fees.
2. Inconvenience: Users shouldn't be expected to remember specific renewal dates for subscriptions across various decentralized applications (DApps). This process can become cumbersome and time-consuming, requiring unnecessary actions despite already providing consent for a subscription.

Should the contract owner handle this responsibility? Here are a few reasons why it may not be the ideal approach:

1. Scalability Challenges: With an ever-growing user base, contract owners cannot manually manage charge() functions for every expired subscription 24/7. Failure to do so or overlooking a user would result in the loss of a subscription that, in theory, should persist until explicitly canceled.
2. Gas Efficiency: While paying for transactions is fair, it lacks efficiency. While batch processing charges is possible, it doesn't fundamentally address the issue.

# Proposed Solution

This project introduces a combined method, designed primarily for educational purposes. While it's possible that similar implementations or accepted standards already exist, my focus remains on exploring the subject matter.

###### Algorithm Example

Users can add funds to their contract balance, which will be utilized for regular charges related to their subscriptions. Subsequently, users can initiate a subscription by selecting one of the plans created by the contract owner. Upon subscription registration, users are charged for the first month. At the end of each period, the system automatically verifies the availability of sufficient ETH balance to cover the subsequent period, ensuring uninterrupted subscription services.

To prevent abuse, users are restricted from withdrawing funds from the balance that have already been allocated to cover subscription expenses, even if the funds haven't physically left the balance.

###### Contract Owner Flexibility

Contract owner is no longer obligated to charge users at specific times; instead, an owner has the freedom to do so at their discretion. For instance, owners may choose to charge when a substantial amount has accumulated, minimizing gas fees in comparison. Furthermore, owners can exercise this right even if users haven't renewed their subscriptions for several periods.

###### User Involvement and Incentives

Subscription users also have the option to initiate a charge. Contract owners can incentivize users by offering payment discounts when they perform charges themselves. This financial incentive encourages user participation and addresses the issue of stagnant funds on the contract balance.

---

For comprehensive functionality details, please refer to the "docs/SubscriptionService.md" file or check the contract and its NatSpec comments.

# Tests

`npm install`

`npx hardhat test`

---

Feel free to contribute and fix issues, let's make blockchain great
