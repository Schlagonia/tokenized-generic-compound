// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV2Router02} from "./interfaces/uniswap/IUniswapV2Router02.sol";

import {CErc20I, CTokenI} from "./interfaces/compound/CErc20I.sol";
import {ComptrollerI} from "./interfaces/compound/ComptrollerI.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;
}

contract CompoundLender is BaseTokenizedStrategy {
    using SafeERC20 for ERC20;

    enum ActiveRewards {
        Protocol,
        Avax,
        Both,
        None
    }

    ActiveRewards public rewardStatus;

    address internal constant WNATIVE =
        0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    CErc20I public immutable cToken;

    ComptrollerI public immutable COMPTROLLER;
    
    address public immutable rewardToken;

    IUniswapV2Router02 public router;

    constructor(
        address _asset,
        string memory _name,
        address _cToken,
        address _comptroller,
        address _rewardToken,
        address _router
    ) BaseTokenizedStrategy(_asset, _name) {
        cToken = CErc20I(_cToken);
        require(cToken.underlying() == _asset, "WRONG CTOKEN");

        ERC20(asset).safeApprove(_cToken, type(uint256).max);

        COMPTROLLER = ComptrollerI(_comptroller);
        rewardToken = _rewardToken;
        router = IUniswapV2Router02(_router);
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        require(cToken.mint(_amount) == 0, "ctoken: mint fail");
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting puroposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        // We don't check liquidity here so temporary liquidity consraints
        // dont cause a loss to be realized by the withdrawer.
        cToken.redeemUnderlying(_amount);
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        if (!TokenizedStrategy.isShutdown()) {
            _claimAndSellRewards();

            uint256 _looseBalance = ERC20(asset).balanceOf(address(this));
            if (_looseBalance > 0) {
                require(cToken.mint(_looseBalance) == 0, "ctoken: mint fail");
            }
        }

        _totalAssets =
            ERC20(asset).balanceOf(address(this)) +
            underlyingBalance();
    }

    function underlyingBalance() public returns (uint256 _balance) {
        _balance = cToken.balanceOfUnderlying(address(this));
    }

    function _claimAndSellRewards() internal {
        ActiveRewards _rewardStatus = rewardStatus;
        if (_rewardStatus == ActiveRewards.Protocol) {
            _claimRewards(0);
        } else if (_rewardStatus == ActiveRewards.Avax) {
            _claimRewards(1);
        } else if (_rewardStatus == ActiveRewards.Both) {
            _claimRewards(0);
            _claimRewards(1);
        } else return;

        uint256 rewardBalance = ERC20(rewardToken).balanceOf(address(this));
        if (rewardBalance > 1e10 && rewardToken != asset) {
            _swapFrom(rewardToken, asset, rewardBalance, 0);
        }

        uint256 avaxBal = address(this).balance;
        if (avaxBal > 1e10) {
            IWETH(WNATIVE).deposit{value: avaxBal}();
            _swapFrom(WNATIVE, asset, avaxBal, 0);
        }
    }

    function _claimRewards(uint8 rewardType) internal {
        CTokenI[] memory cTokens = new CTokenI[](1);
        cTokens[0] = cToken;
        address payable[] memory holders = new address payable[](1);
        holders[0] = payable(address(this));

        // Claim only rewards for lending to reduce the gas cost
        COMPTROLLER.claimReward(rewardType, holders, cTokens, false, true);
    }

    function _swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _amountOut
    ) internal {
        _checkAllowance(address(router), _from, _amountIn);

        router.swapExactTokensForTokens(
            _amountIn,
            _amountOut,
            _getTokenOutPath(_from, _to),
            address(this),
            block.timestamp
        );
    }

    function _getTokenOutPath(
        address _tokenIn,
        address _tokenOut
    ) internal pure returns (address[] memory _path) {
        bool isNative = _tokenIn == WNATIVE || _tokenOut == WNATIVE;
        _path = new address[](isNative ? 2 : 3);
        _path[0] = _tokenIn;

        if (isNative) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = WNATIVE;
            _path[2] = _tokenOut;
        }
    }

    function setRewardStatus(
        ActiveRewards _newRewardStatus
    ) external onlyManagement {
        rewardStatus = _newRewardStatus;
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A seperate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        cToken.redeemUnderlying(_amount);
    }

    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal {
        if (ERC20(_token).allowance(address(this), _contract) < _amount) {
            ERC20(_token).approve(_contract, 0);
            ERC20(_token).approve(_contract, _amount);
        }
    }

    // Needed to receive AVAX rewards.
    receive() external payable {}
}
