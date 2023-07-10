// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BenqiLender} from "./BenqiLender.sol";

interface IStrategy {
    function setPerformanceFeeRecipient(address) external;

    function setKeeper(address) external;

    function setPendingManagement(address) external;
}

contract BenqiLenderFactory {
    event NewBenqiLender(address indexed strategy, address indexed asset);

    constructor(address _asset, string memory _name, address _cToken) {
        newBenqiLender(
            _asset,
            _name,
            _cToken,
            msg.sender,
            msg.sender,
            msg.sender
        );
    }

    function newBenqiLender(
        address _asset,
        string memory _name,
        address _cToken
    ) external returns (address) {
        return
            newBenqiLender(
                _asset,
                _name,
                _cToken,
                msg.sender,
                msg.sender,
                msg.sender
            );
    }

    function newBenqiLender(
        address _asset,
        string memory _name,
        address _cToken,
        address _performanceFeeRecipient,
        address _keeper,
        address _management
    ) public returns (address) {
        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategy newStrategy = IStrategy(
            address(new BenqiLender(_asset, _name, _cToken))
        );

        newStrategy.setPerformanceFeeRecipient(_performanceFeeRecipient);

        newStrategy.setKeeper(_keeper);

        newStrategy.setPendingManagement(_management);

        emit NewBenqiLender(address(newStrategy), _asset);
        return address(newStrategy);
    }
}
