// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import "forge-std/console.sol";
import {PointsHook} from "../src/PointsHook.sol";

contract TestPointsHook is Test, Deployers {
    using CurrencyLibrary for Currency;

    MockERC20 rax; // our token to use in the ETH-TOKEN pool

    // Native tokens are represented by address(0)
    Currency ethCurrency = Currency.wrap(address(0));
    Currency raxCurrency;

    PointsHook hook;

    address public alice;
    address public bob;

    function setUp() public {
        // TODO

        //Deploying instance of poolManager and periphery router.
        deployFreshManagerAndRouters();

        //Deploy RAX token
        rax = new MockERC20("RAX token", "RAX", 18);
        raxCurrency = Currency.wrap(address(rax));

        // Create addresses for Alice and Bob
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        //Mint a bunch of RAX to ALICE and BOB
        rax.mint(alice, 1000 ether);
        rax.mint(bob, 1000 ether);

        //Provide 1000 ETH to both alice and bob
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);

        // Deploy hook to an address that has the proper flags set
        uint160 flags = uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG);

        deployCodeTo("PointsHook.sol", abi.encode(manager, "Soul token", "SOUL"), address(flags));

        //Deploying our hook
        hook = PointsHook(address(flags));

        vm.startPrank(alice);

        //Approving RAX for spending on the swap router and modify liquidity router
        rax.approve(address(swapRouter), type(uint256).max);
        rax.approve(address(modifyLiquidityRouter), type(uint256).max);

        vm.stopPrank();

        //Initializing the pool
        (key,) = initPool(
            ethCurrency,
            raxCurrency,
            hook,
            3000, //Swap Fees
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
    }

    function test_addLiquidityAndSwap() public {
        /**
         * Swapping without any referrer
         */
        //Setting no referrer in the hookdata
        bytes memory hookData = hook.getHookData(address(0), alice);

        //Initial souls that alice owns
        uint256 soulsBalanceOriginal = hook.balanceOf(alice);

        /**
         * Adding liquidity
         */
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        //Calculating amount0 delta and amount1 delta
        (uint256 amount0Delta, uint256 amount1Delta) =
            LiquidityAmounts.getAmountsForLiquidity(SQRT_PRICE_1_1, sqrtPriceAtTickLower, sqrtPriceAtTickUpper, 1 ether);

        vm.startPrank(alice);
        //Modifying the liquidity router
        modifyLiquidityRouter.modifyLiquidity{value: amount0Delta + 1}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether,
                salt: bytes32(0)
            }),
            hookData
        );
        vm.stopPrank();

        //Souls alice owns after adding liquidity
        uint256 soulsBalanceAfterAddLiquidity = hook.balanceOf(alice);

        assertApproxEqAbs(
            soulsBalanceAfterAddLiquidity - soulsBalanceOriginal,
            2995354955910434,
            0.0001 ether // error margin for precision loss
        );

        /**
         * Swapping ETH for RAX tokens by alice
         */
        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        //Souls alice owns after swapping
        uint256 soulsBalanceAfterSwap = hook.balanceOf(alice);

        assertEq(soulsBalanceAfterSwap - soulsBalanceAfterAddLiquidity, 2 * 10 ** 14);
    }

    function test_addLiquidityAndSwapWithReferral() public {
        /**
         * Swapping with referrer
         * Alice => Referree
         * Bob => Referrer
         */

        //Setting bob as the referrer
        bytes memory hookData = hook.getHookData(bob, alice);

        //Getting the initial soul tokens of alice and bob
        uint256 soulsBalanceOriginal = hook.balanceOf(alice);
        uint256 referrerSoulsBalanceOriginal = hook.balanceOf(bob);

        //Calculating tick values
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        //Calculating amount0 and amount1 values
        (uint256 amount0Delta, uint256 amount1Delta) =
            LiquidityAmounts.getAmountsForLiquidity(SQRT_PRICE_1_1, sqrtPriceAtTickLower, sqrtPriceAtTickUpper, 1 ether);

        /**
         * Adding Liquidity to the pool by alice
         */
        vm.startPrank(alice);

        modifyLiquidityRouter.modifyLiquidity{value: amount0Delta + 1}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether,
                salt: bytes32(0)
            }),
            hookData
        );

        vm.stopPrank();

        //Capturing souls balance after adding liquidity
        uint256 soulsBalanceAfterAddLiquidity = hook.balanceOf(alice);
        uint256 referrerSoulsBalanceAfterAddLiquidity = hook.balanceOf(bob);

        //Assertions
        assertApproxEqAbs(soulsBalanceAfterAddLiquidity - soulsBalanceOriginal, 2995354955910434, 0.00001 ether);
        assertApproxEqAbs(
            referrerSoulsBalanceAfterAddLiquidity - referrerSoulsBalanceOriginal - hook.POINTS_FOR_REFERRAL(),
            299535495591043,
            0.000001 ether
        );

        /**
         * Swapping ETH for RAX
         */
        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        //Captuing souls after swapping
        uint256 soulsBalanceAfterSwap = hook.balanceOf(alice);
        uint256 referrerSoulsBalanceAfterSwap = hook.balanceOf(bob);

        //Assertions
        assertEq(soulsBalanceAfterSwap - soulsBalanceAfterAddLiquidity, 2 * 10 ** 14);
        assertEq(referrerSoulsBalanceAfterSwap - referrerSoulsBalanceAfterAddLiquidity, 2 * 10 ** 13);
    }
}
