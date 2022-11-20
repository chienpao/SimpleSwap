// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ISimpleSwap} from "./interface/ISimpleSwap.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract SimpleSwap is ISimpleSwap, ERC20 {
    using SafeMath for uint256;

    address public tokenA;
    address public tokenB;
    uint256 private _reserveA;
    uint256 private _reserveB;
    uint256 private _kValue;

    constructor(address _tokenA, address _tokenB)
        ERC20("SimpleSwap LP Token", "SLP")
    {
        require(
            Address.isContract(_tokenA),
            "SimpleSwap: TOKENA_IS_NOT_CONTRACT"
        );
        require(
            Address.isContract(_tokenB),
            "SimpleSwap: TOKENB_IS_NOT_CONTRACT"
        );
        require(
            _tokenA != _tokenB,
            "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS"
        );
        _reserveA = 0;
        _reserveB = 0;
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    /// @notice Swap tokenIn for tokenOut with amountIn
    /// @param tokenIn The address of the token to swap from
    /// @param tokenOut The address of the token to swap to
    /// @param amountIn The amount of tokenIn to swap
    /// @return amountOut The amount of tokenOut received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external override returns (uint256 amountOut) {
        require(tokenIn == tokenA || tokenIn == tokenB, "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == tokenA || tokenOut == tokenB, "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        // reference UniswapV2Pair.sol:swap
        uint256 reserveTokenIn = ERC20(tokenIn).balanceOf(address(this));
        uint256 reserveTokenOut = ERC20(tokenOut).balanceOf(address(this));

        // calculate amountOut
        uint256 totalTokenIn = reserveTokenIn.add(amountIn);
        amountOut = ((totalTokenIn.mul(reserveTokenOut)).sub(_kValue)).div(totalTokenIn);

        require(amountOut > 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");

        // get tokenIn from msg.sender
        ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // transfer tokenOut to msg.sender
        ERC20(tokenOut).transfer(msg.sender, amountOut);

        // update reserves, Linter: said need to avoid state changes after transfer
        // but move reserves update before transfer, testing will be error
        _reserveA = ERC20(tokenA).balanceOf(address(this));
        _reserveB = ERC20(tokenB).balanceOf(address(this));

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Add liquidity to the pool
    /// @param amountAIn The amount of tokenA to add
    /// @param amountBIn The amount of tokenB to add
    /// @return amountA The actually amount of tokenA added
    /// @return amountB The actually amount of tokenB added
    /// @return liquidity The amount of liquidity minted
    function addLiquidity(uint256 amountAIn, uint256 amountBIn)
        external
        override
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        require(
            amountAIn > 0 && amountBIn > 0,
            "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT"
        );

        // reference UniswapV2Pair.sol:mint
        uint256 totalSupply = totalSupply();

        // if pool is empty, that's mean is first addLiquidity user
        if (totalSupply == 0) {
            liquidity = Math.sqrt(amountAIn.mul(amountBIn)); // (amountA x amountB)^2
            amountA = amountAIn;
            amountB = amountBIn;
        } else {
            // if pool is not empty
            // choose min one
            liquidity = Math.min(
                (amountAIn.mul(totalSupply)).div(_reserveA),
                (amountBIn.mul(totalSupply)).div(_reserveB)
            );
            amountA = (liquidity.mul(_reserveA)).div(totalSupply);
            amountB = (liquidity.mul(_reserveB)).div(totalSupply);
        }

        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");

        // update reserves and K value
        _updateReservesAndK(true, amountA, amountB);

        // get the tokens from msg.sender
        ERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        ERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        // mint LP token to msg.sender
        _mint(msg.sender, liquidity);

        // send event
        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Remove liquidity from the pool
    /// @param liquidity The amount of liquidity to remove
    /// @return amountA The amount of tokenA received
    /// @return amountB The amount of tokenB received
    function removeLiquidity(uint256 liquidity)
        external
        override
        returns (uint256 amountA, uint256 amountB)
    {
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        // reference UniswapV2Pair.sol:burn
        // calculate token's amount from current liquidity
        uint256 totalSupply = totalSupply();
        amountA = (liquidity.mul(_reserveA)).div(totalSupply);
        amountB = (liquidity.mul(_reserveB)).div(totalSupply);

        // update reserves and K value
        _updateReservesAndK(false, amountA, amountB);

        // send LP token to contract
        transfer(address(this), liquidity);

        // transfer back tokens to msg.sender
        ERC20(tokenA).transfer(msg.sender, amountA);
        ERC20(tokenB).transfer(msg.sender, amountB);

        // burn LP token from this contract
        _burn(address(this), liquidity);

        // send event
        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Get the reserves of the pool
    /// @return _reserveA The reserve of tokenA
    /// @return _reserveB The reserve of tokenB
    function getReserves() external view override returns (uint256, uint256) {
        return (_reserveA, _reserveB);
    }

    /// @notice Get the address of tokenA
    /// @return tokenA The address of tokenA
    function getTokenA() external view override returns (address) {
        return tokenA;
    }

    /// @notice Get the address of tokenB
    /// @return tokenB The address of tokenB
    function getTokenB() external view override returns (address) {
        return tokenB;
    }

    function _updateReservesAndK(
        bool add,
        uint256 amountA,
        uint256 amountB
    ) private {
        if (add) {
            _reserveA += amountA;
            _reserveB += amountB;
        } else {
            _reserveA -= amountA;
            _reserveB -= amountB;
        }
        _kValue = _reserveA.mul(_reserveB);
    }
}
