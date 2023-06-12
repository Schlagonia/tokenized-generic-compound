// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {CompoundLender} from "./CompoundLender.sol";

interface IStrategy {
    function setPerformanceFeeRecipient(address) external;

    function setKeeper(address) external;

    function setManagement(address) external;
}

contract CompoundLenderFactory {
    event NewCompoundLender(address indexed strategy, address indexed asset);

    constructor(
        address _asset,
        string memory _name,
        address _cToken,
        address _comptroller,
        address _rewardToken
    ) {
        newCompoundLender(
            _asset,
            _name,
            _cToken,
            _comptroller,
            _rewardToken,
            msg.sender,
            msg.sender,
            msg.sender
        );
    }

    function newCompoundLender(
        address _asset,
        string memory _name,
        address _cToken,
        address _comptroller,
        address _rewardToken
    ) external returns (address) {
        return
            newCompoundLender(
                _asset,
                _name,
                _cToken,
                _comptroller,
                _rewardToken,
                msg.sender,
                msg.sender,
                msg.sender
            );
    }

    function newCompoundLender(
        address _asset,
        string memory _name,
        address _cToken,
        address _comptroller,
        address _rewardToken,
        address _performanceFeeRecipient,
        address _keeper,
        address _management
    ) public returns (address) {
        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategy newStrategy = IStrategy(
            address(
                new CompoundLender(
                    _asset,
                    _name,
                    _cToken,
                    _comptroller,
                    _rewardToken
                )
            )
        );

        newStrategy.setPerformanceFeeRecipient(_performanceFeeRecipient);

        newStrategy.setKeeper(_keeper);

        newStrategy.setManagement(_management);

        emit NewCompoundLender(address(newStrategy), _asset);
        return address(newStrategy);
    }
}
