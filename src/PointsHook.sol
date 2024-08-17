// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

contract PointsHook is BaseHook, ERC20 {
    error InvalidReferral(address referrer, address referree);

    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    // Keeping track of user => referrer
    mapping(address => address) public referredBy;

    // Amount of points given to someone for referring someone.
    uint256 public constant POINTS_FOR_REFERRAL = 500 * 1e18;

    //percentage of RAX tokens to allocate based on the amount of ETH spent in swap
    uint256 public constant PERCENTAGE_OF_SOULS_ALLOCATED_ON_ETH_SPENT = 20;

    //Initialize BaseHook and ERC20
    constructor(IPoolManager _manager, string memory _name, string memory _symbol)
        BaseHook(_manager)
        ERC20(_name, _symbol, 18)
    {}

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookdata
    ) external override onlyByPoolManager returns (bytes4, int128) {
        //Check if ETH-RAX pool
        if (!key.currency0.isNative()) return (this.afterSwap.selector, 0);

        //Check we are only buying RAX for ETH
        if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);

        //Calculate 20% of SOULs to referree/swapper
        uint256 ethAmountSpent =
            swapParams.amountSpecified < 0 ? uint256(-swapParams.amountSpecified) : uint256(int256(-delta.amount0()));

        uint256 pointsForSwap = (ethAmountSpent / 5);

        //Mint tokens to the referree and referral.
        _assignPoints(hookdata, pointsForSwap);

        return (this.afterSwap.selector, 0);
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        bytes calldata hookdata
    ) external override onlyByPoolManager returns (bytes4, BalanceDelta) {
        //Check if ETH-RAX pool
        if (!key.currency0.isNative()) return (this.afterAddLiquidity.selector, delta);

        //calculating point equivalent to the amount of ETH they are adding as liquidity.
        uint256 pointsForAddingLiquidity = uint256(int256(-delta.amount0()));

        //Minting SOULS to referree and referrer.
        _assignPoints(hookdata, pointsForAddingLiquidity);

        return (this.afterAddLiquidity.selector, delta);
    }

    function _assignPoints(bytes calldata hookdata, uint256 referreePoints) internal {
        //Return if no referree/referrer specified.
        if (hookdata.length == 0) return;

        //Decoding the hookdata
        (address referrer, address referree) = abi.decode(hookdata, (address, address));

        //Edgecases
        // 1. Referree cannot refer himself
        // 2. Referrer cannot refer address(0)
        if (referrer == referree || referree == address(0)) {
            revert InvalidReferral(referrer, referree);
        }

        //EDGECASE
        // 1. Check if there are enough SOUL tokens to refer.

        //If referrer is refering multiple people, then mint 10% of referrer's points to the referrer.
        /**
         * Business logic:
         * referrer get how many points on first time referral => 500 SOULS
         * referree gets how many points on first time referral => None
         *      referreePoints, from where do i get this value from?? Based on the RAX tokens the referree swaps for the native tokens
         * can referree be refered multiple people ? => No
         * can referrer refer multiple people ? if so how many points does he get on multiple referal ? => on first referral, gets 500 souls, thereafter gets 10% of the transaction done by the referree.
         */

        //If referree is being referred for the first time, then set referrer and mint POINTS_FOR_REFERRAL to the referrer i.e 500 SOULS.
        if (referredBy[referree] == address(0) && referrer != address(0)) {
            referredBy[referree] = referrer;
            _mint(referrer, POINTS_FOR_REFERRAL);
        }

        // Mint 10% worth of the referree's points to the referrer
        if (referredBy[referree] != address(0)) {
            _mint(referrer, referreePoints / 10);
        }

        // Mint the appropriate number of points to the referree
        _mint(referree, referreePoints);
    }

    /// @notice Setting up Hook Permissions to return `true` for `afterSwap` and `afterAddLiquidity` hooks
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @dev Encoding the referrer and referree addresses that is passed to the hooks `hookdata` param
    /// @return bytes after encoding the data
    function getHookData(address referrer, address referree) public pure returns (bytes memory) {
        return abi.encode(referrer, referree);
    }
}
