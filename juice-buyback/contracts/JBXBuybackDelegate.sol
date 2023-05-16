// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayDelegate.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal3_1.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBFundingCycleMetadataResolver.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidPayData.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "@paulrberg/contracts/math/PRBMath.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "./interfaces/external/IWETH9.sol";

/**
 * @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVS MEAM
 *
 * @title  Buyback Delegate
 *
 * @notice Datasource and delegate allowing pay beneficiary to get the highest amount
 *         of project tokens between minting using the project weigh and swapping in a
 *         given Uniswap V3 pool
 *
 * @dev    This only supports ETH terminal. The pool is fixed, if a new pool offers deeper
 *         liquidity, this delegate needs to be redeployed.
 */

contract JBXBuybackDelegate is IJBFundingCycleDataSource, IJBPayDelegate, IUniswapV3SwapCallback, Ownable {
    using JBFundingCycleMetadataResolver for JBFundingCycle;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JuiceBuyback_Unauthorized();
    error JuiceBuyback_MaximumSlippage();

    //*********************************************************************//
    // -----------------------------  events ----------------------------- //
    //*********************************************************************//

    event JBXBuybackDelegate_Swap(uint256 projectId, uint256 amountEth, uint256 amountOut);
    event JBXBuybackDelegate_Mint(uint256 projectId);

    //*********************************************************************//
    // --------------------- private constant properties ----------------- //
    //*********************************************************************//

    /**
     * @notice Address project token < address terminal token ?
     */
    bool private immutable _projectTokenIsZero;

    /**
     * @notice The unit of the max slippage (expressed in 1/10000th)
     */
    uint256 private constant SLIPPAGE_DENOMINATOR = 10000;

    //*********************************************************************//
    // --------------------- public constant properties ------------------ //
    //*********************************************************************//

    /**
     * @notice The project token address
     * 
     * @dev In this context, this is the tokenOut
     */
    IERC20 public immutable projectToken;

    /**
     * @notice The uniswap pool corresponding to the project token-other token market
     *         (this should be carefully chosen liquidity wise)
     */
    IUniswapV3Pool public immutable pool;

    /**
     * @notice The project terminal using this extension
     */
    IJBPayoutRedemptionPaymentTerminal3_1 public immutable jbxTerminal;

    /**
     * @notice The WETH contract
     */
    IWETH9 public immutable weth;

    //*********************************************************************//
    // --------------------- private stored properties ------------------- //
    //*********************************************************************//

    /**
     * @notice The amount of token created if minted is prefered
     * 
     * @dev    This is a mutex 1-x-1
     */
    uint256 private mintedAmount = 1;

    /**
     * @notice The current reserved rate
     * 
     * @dev    This is a mutex 1-x-1
     */
    uint256 private reservedRate = 1;

    /**
     * @dev No other logic besides initializing the immutables
     */
    constructor(
        IERC20 _projectToken,
        IWETH9 _weth,
        IUniswapV3Pool _pool,
        IJBPayoutRedemptionPaymentTerminal3_1 _jbxTerminal
    ) {
        projectToken = _projectToken;
        pool = _pool;
        jbxTerminal = _jbxTerminal;
        _projectTokenIsZero = address(_projectToken) < address(_weth);
        weth = _weth;
    }

    //*********************************************************************//
    // ---------------------- external functions ------------------------- //
    //*********************************************************************//

    /**
     * @notice The datasource implementation
     *
     * @param  _data the data passed to the data source in terminal.pay(..). _data.metadata need to have the Uniswap quote
     * @return weight the weight to use (the one passed if not max reserved rate, 0 if swapping or the one corresponding
     *         to the reserved token to mint if minting)
     * @return memo the original memo passed
     * @return delegateAllocations The amount to send to delegates instead of adding to the local balance.
     */
    function payParams(JBPayParamsData calldata _data)
        external
        override
        returns (uint256 weight, string memory memo, JBPayDelegateAllocation[] memory delegateAllocations)
    {
        // Find the total number of tokens to mint, as a fixed point number with 18 decimals
        uint256 _tokenCount = PRBMath.mulDiv(_data.amount.value, _data.weight, 10 ** 18);

        // Unpack the quote from the pool, given by the frontend
        (,, uint256 _quote, uint256 _slippage) = abi.decode(_data.metadata, (bytes32, bytes32, uint256, uint256));

        // If the amount swapped is bigger than the lowest received when minting, use the swap pathway
        if (_tokenCount < _quote - (_quote * _slippage / SLIPPAGE_DENOMINATOR)) {
            // Pass the quote and reserve rate via a mutex
            mintedAmount = _tokenCount;
            reservedRate = _data.reservedRate;

            // Return this delegate as the one to use, and do not mint from the terminal
            delegateAllocations = new JBPayDelegateAllocation[](1);
            delegateAllocations[0] =
                JBPayDelegateAllocation({delegate: IJBPayDelegate(this), amount: _data.amount.value});

            return (0, _data.memo, delegateAllocations);
        }

        // If minting, do not use this as delegate
        return (_data.weight, _data.memo, new JBPayDelegateAllocation[](0));
    }

    /**
     * @notice Delegate to either swap to the beneficiary or mint to the beneficiary
     *
     * @dev    This delegate is called only if the quote for the swap is bigger than the lowest received when minting.
     *         If the swap reverts (slippage, liquidity, etc), the delegate will then mint the same amount of token as
     *         if the delegate was not used.
     *         If the beneficiary requests non claimed token, the swap is not used (as it is, per definition, claimed token)
     *
     * @param _data the delegate data passed by the terminal
     */
    function didPay(JBDidPayData calldata _data) external payable override {
        // Access control as minting is authorized to this delegate
        if (msg.sender != address(jbxTerminal)) revert JuiceBuyback_Unauthorized();

        // Retrieve the number of token created if minting and reset the mutex (not exposed in JBDidPayData)
        uint256 _tokenCount = mintedAmount;
        mintedAmount = 1;

        // Retrieve the fc reserved rate and reset the mutex
        uint256 _reservedRate = reservedRate;
        reservedRate = 1;

        // The minimum amount of token received if swapping
        (,, uint256 _quote, uint256 _slippage) = abi.decode(_data.metadata, (bytes32, bytes32, uint256, uint256));
        uint256 _minimumReceivedFromSwap = _quote - (_quote * _slippage / SLIPPAGE_DENOMINATOR);

        // Pick the appropriate pathway (swap vs mint), use mint if non-claimed prefered
        if (_data.preferClaimedTokens) {
            // Try swapping
            uint256 _amountReceived = _swap(_data, _minimumReceivedFromSwap, _reservedRate);

            // If swap failed, mint instead, with the original weight + add to balance the token in
            if (_amountReceived == 0) _mint(_data, _tokenCount);
        } else {
            _mint(_data, _tokenCount);
        }
    }

    /**
     * @notice The Uniswap V3 pool callback (where token transfer should happens)
     *
     * @dev    Slippage controle is achieved here
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // Check if this is really a callback
        if (msg.sender != address(pool)) revert JuiceBuyback_Unauthorized();

        // Unpack the data
        (uint256 _minimumAmountReceived) = abi.decode(data, (uint256));

        // Assign 0 and 1 accordingly
        uint256 _amountReceived = uint256(-(_projectTokenIsZero ? amount0Delta : amount1Delta));
        uint256 _amountToSend = uint256(_projectTokenIsZero ? amount1Delta : amount0Delta);

        // Revert if slippage is too high
        if (_amountReceived < _minimumAmountReceived) revert JuiceBuyback_MaximumSlippage();

        // Wrap and transfer the weth to the pool
        weth.deposit{value: _amountToSend}();
        weth.transfer(address(pool), _amountToSend);
    }

    function redeemParams(JBRedeemParamsData calldata _data)
        external
        override
        returns (uint256 reclaimAmount, string memory memo, JBRedemptionDelegateAllocation[] memory delegateAllocations)
    {}

    //*********************************************************************//
    // ---------------------- internal functions ------------------------- //
    //*********************************************************************//

    /**
     * @notice Swap the terminal token to receive the project toke_beforeTransferTon
     *
     * @dev    This delegate first receive the whole amount of project token,
     *         then send the non-reserved token to the beneficiary,
     *         then burn the rest of this delegate balance (ie the amount of reserved token),
     *         then mint the same amount as received (this will add the reserved token, following the fc rate)
     *         then burn the difference (ie this delegate balance)
     *         -> End result is having the correct balances (beneficiary and reserve), according to the reserve rate
     *
     * @param  _data the didPayData passed by the terminal
     * @param  _minimumReceivedFromSwap the minimum amount received, to prevent slippage
     */
    function _swap(JBDidPayData calldata _data, uint256 _minimumReceivedFromSwap, uint256 _reservedRate)
        internal
        returns (uint256 _amountReceived)
    {
        // Pass the token and min amount to receive as extra data
        try pool.swap({
            recipient: address(this),
            zeroForOne: !_projectTokenIsZero,
            amountSpecified: int256(_data.amount.value),
            sqrtPriceLimitX96: _projectTokenIsZero ? TickMath.MAX_SQRT_RATIO - 1 : TickMath.MIN_SQRT_RATIO + 1,
            data: abi.encode(_minimumReceivedFromSwap)
        }) returns (int256 amount0, int256 amount1) {
            // Swap succeded, take note of the amount of projectToken received (negative as it is an exact input)
            _amountReceived = uint256(-(_projectTokenIsZero ? amount0 : amount1));
        } catch {
            // implies _amountReceived = 0 -> will later mint when back in didPay
            return _amountReceived;
        }

        // The amount to send to the beneficiary
        uint256 _nonReservedToken = PRBMath.mulDiv(
            _amountReceived, JBConstants.MAX_RESERVED_RATE - _reservedRate, JBConstants.MAX_RESERVED_RATE
        );

        // The amount to add to the reserved token
        uint256 _reservedToken = _amountReceived - _nonReservedToken;

        // Send the non-reserved token to the beneficiary (if any / reserved rate is not max)
        if (_nonReservedToken != 0) projectToken.transfer(_data.beneficiary, _nonReservedToken);

        // If there are reserved token, add them to the reserve
        if (_reservedToken != 0) {
            IJBController controller = IJBController(jbxTerminal.directory().controllerOf(_data.projectId));

            // 1) Burn all the reserved token, which are in this address -> result: 0 here, 0 in reserve
            controller.burnTokensOf({
                _holder: address(this),
                _projectId: _data.projectId,
                _tokenCount: _reservedToken,
                _memo: "",
                _preferClaimedTokens: true
            });

            // 2) Mint the reserved token with this address as beneficiary -> result: _amountReceived-reserved here, reservedToken in reserve
            controller.mintTokensOf({
                _projectId: _data.projectId,
                _tokenCount: _amountReceived,
                _beneficiary: address(this),
                _memo: _data.memo,
                _preferClaimedTokens: false,
                _useReservedRate: true
            });

            // 3) Burn the non-reserve token which are now left in this address (can be 0) -> result: 0 here, reservedToken in reserve
            uint256 _nonReservedTokenInContract = _amountReceived - _reservedToken;

            if (_nonReservedTokenInContract != 0) {
                controller.burnTokensOf({
                    _holder: address(this),
                    _projectId: _data.projectId,
                    _tokenCount: _nonReservedTokenInContract,
                    _memo: "",
                    _preferClaimedTokens: false
                });
            }
        }

        emit JBXBuybackDelegate_Swap(_data.projectId, _data.amount.value, _amountReceived);
    }

    /**
     * @notice Mint the token out, sending back the token in in the terminal
     *
     * @param  _data the didPayData passed by the terminal
     * @param  _amount the amount of token out to mint
     */
    function _mint(JBDidPayData calldata _data, uint256 _amount) internal {
        IJBController controller = IJBController(jbxTerminal.directory().controllerOf(_data.projectId));

        // Mint to the beneficiary with the fc reserve rate
        controller.mintTokensOf({
            _projectId: _data.projectId,
            _tokenCount: _amount,
            _beneficiary: _data.beneficiary,
            _memo: _data.memo,
            _preferClaimedTokens: _data.preferClaimedTokens,
            _useReservedRate: true
        });

        // Send the eth back to the terminal balance
        jbxTerminal.addToBalanceOf{value: _data.amount.value}(
            _data.projectId, _data.amount.value, JBTokens.ETH, "", new bytes(0)
        );

        emit JBXBuybackDelegate_Mint(_data.projectId);
    }

    //*********************************************************************//
    // ---------------------- peripheral functions ----------------------- //
    //*********************************************************************//

    function supportsInterface(bytes4 _interfaceId) external pure override returns (bool) {
        return _interfaceId == type(IJBFundingCycleDataSource).interfaceId
            || _interfaceId == type(IJBPayDelegate).interfaceId;
    }
}
