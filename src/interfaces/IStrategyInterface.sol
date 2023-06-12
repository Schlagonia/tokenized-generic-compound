// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {CErc20I} from "./compound/CErc20I.sol";
import {CompoundLender} from "../CompoundLender.sol";

interface IStrategyInterface is IStrategy {
    //TODO: Add your specific implementation interface in here.
    function underlyingBalance() external returns (uint256 _balance);

    function cToken() external view returns (CErc20I);

    function rewardStatus() external view returns (uint256);

    function setRewardStatus(
        CompoundLender.ActiveRewards _newRewardStatus
    ) external;
}
