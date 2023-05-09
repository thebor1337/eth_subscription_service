// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./SubscriptionService.sol";

contract TestStandaloneSubscriptionService is StandaloneSubscriptionService {
    function __subscribed(address account) external view returns(bool) {
        return _subscribed(account);
    }

    function __cancelled(address account) external view returns(bool) {
        return _cancelled(account);
    }
}