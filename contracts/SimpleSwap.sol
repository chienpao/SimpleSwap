// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ISimpleSwap} from "./interface/ISimpleSwap.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SimpleSwap is ISimpleSwap, ERC20, ReentrancyGuard {

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

    /// @inheritdoc ISimpleSwap
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external nonReentrant override returns (uint256 amountOut) {
        require(tokenIn == tokenA || tokenIn == tokenB, "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == tokenA || tokenOut == tokenB, "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        // reference UniswapV2Pair.sol:swap
        uint256 reserveTokenIn = ERC20(tokenIn).balanceOf(address(this));
        uint256 reserveTokenOut = ERC20(tokenOut).balanceOf(address(this));

        // calculate amountOut
        uint256 totalTokenIn = reserveTokenIn + amountIn;
        amountOut = ((totalTokenIn * reserveTokenOut) -_kValue)/(totalTokenIn);

        require(amountOut > 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");

        // get tokenIn from msg.sender
        SafeERC20.safeTransferFrom(ERC20(tokenIn), msg.sender, address(this), amountIn);

        // transfer tokenOut to msg.sender
        ERC20(tokenOut).transfer(msg.sender, amountOut);

        // update reserves, Linter: said need to avoid state changes after transfer
        // but move reserves update before transfer, testing will be error
        _reserveA = ERC20(tokenA).balanceOf(address(this));
        _reserveB = ERC20(tokenB).balanceOf(address(this));

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @inheritdoc ISimpleSwap
    function addLiquidity(uint256 amountAIn, uint256 amountBIn)
        external
        nonReentrant
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
            liquidity = Math.sqrt(amountAIn * amountBIn); // (amountA x amountB)^2
            amountA = amountAIn;
            amountB = amountBIn;
        } else {
            // if pool is not empty
            // choose min one
            liquidity = Math.min(
                (amountAIn*totalSupply)/_reserveA,
                (amountBIn*totalSupply)/_reserveB
            );
            amountA = (liquidity*_reserveA)/totalSupply;
            amountB = (liquidity*_reserveB)/totalSupply;
        }

        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");

        // update reserves and K value
        _updateReservesAndK(true, amountA, amountB);

        // get the tokens from msg.sender
        SafeERC20.safeTransferFrom(ERC20(tokenA), msg.sender, address(this), amountA);
        SafeERC20.safeTransferFrom(ERC20(tokenB), msg.sender, address(this), amountB);

        // mint LP token to msg.sender
        _mint(msg.sender, liquidity);

        // send event
        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    /// @inheritdoc ISimpleSwap
    function removeLiquidity(uint256 liquidity)
        external
        nonReentrant
        override
        returns (uint256 amountA, uint256 amountB)
    {
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        // reference UniswapV2Pair.sol:burn
        // calculate token's amount from current liquidity
        uint256 totalSupply = totalSupply();
        amountA = (liquidity*_reserveA)/totalSupply;
        amountB = (liquidity*_reserveB)/totalSupply;

        // update reserves and K value
        _updateReservesAndK(false, amountA, amountB);

        // send LP token to contract
        _transfer(msg.sender, address(this), liquidity);

        // transfer back tokens to msg.sender
        ERC20(tokenA).transfer(msg.sender, amountA);
        ERC20(tokenB).transfer(msg.sender, amountB);

        // burn LP token from this contract
        _burn(address(this), liquidity);

        // send event
        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    /// @inheritdoc ISimpleSwap
    function getReserves() external view override returns (uint256, uint256) {
        return (_reserveA, _reserveB);
    }

    /// @inheritdoc ISimpleSwap
    function getTokenA() external view override returns (address) {
        return tokenA;
    }

    /// @inheritdoc ISimpleSwap
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
        _kValue = _reserveA * _reserveB;
    }
}
