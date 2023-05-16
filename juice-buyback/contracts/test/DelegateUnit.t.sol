// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../interfaces/external/IWETH9.sol';
import './helpers/TestBaseWorkflowV3.sol';

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleStore.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatable.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayDelegate.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBRedemptionDelegate.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBToken.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBCurrencies.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBFundingCycleMetadataResolver.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol';

import '@paulrberg/contracts/math/PRBMath.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';

import '../JBXBuybackDelegate.sol';
import '../mock/MockAllocator.sol';

/**
 * @notice Unit tests for the JBXBuybackDelegate contract.
 *
 */
contract TestUnitJBXBuybackDelegate is TestBaseWorkflowV3 {
  using JBFundingCycleMetadataResolver for JBFundingCycle;

  JBController controller;
  JBProjectMetadata _projectMetadata;
  JBFundingCycleData _data;
  JBFundingCycleData _dataReconfiguration;
  JBFundingCycleData _dataWithoutBallot;
  JBFundingCycleMetadata _metadata;
  JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
  IJBPaymentTerminal[] _terminals; // Default empty

  uint256 _projectId;
  uint256 reservedRate = 4500;
  uint256 weight = 10**18; // Minting 1 token per eth

  JBXBuybackDelegate _delegate;

  // Using fixed addresses to insure token0/token1 consistency
  IWETH9 private constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  IJBToken private constant jbx = IJBToken(0x3abF2A4f8452cCC2CF7b4C1e4663147600646f66);
  IUniswapV3Pool private constant pool = IUniswapV3Pool(address(69420));

  /**
   * @notice Set up a new JBX project and use the buyback delegate as the datasource
   */
  function setUp() public override {
    // label
    evm.label(address(pool), 'uniswapPool');
    evm.label(address(weth), '$WETH');
    evm.label(address(jbx), '$JBX');

    // mock
    evm.etch(address(pool), '0x69');
    evm.etch(address(weth), '0x69');
    evm.etch(address(jbx), '0x69');

    // super is the Jbx V3 fixture
    super.setUp();

    // Deploy the delegate
    _delegate = new JBXBuybackDelegate(IERC20(address(jbx)), weth, pool, IJBPayoutRedemptionPaymentTerminal3_1(address(jbETHPaymentTerminal())));

    // Configure a new project using it
    controller = jbController();

    _projectMetadata = JBProjectMetadata({content: 'myIPFSHash', domain: 1});

    _data = JBFundingCycleData({
      duration: 6 days,
      weight: weight,
      discountRate: 0,
      ballot: IJBFundingCycleBallot(address(0))
    });

    _metadata = JBFundingCycleMetadata({
      global: JBGlobalFundingCycleMetadata({allowSetTerminals: false, allowSetController: false, pauseTransfers: false}),
      reservedRate: reservedRate,
      redemptionRate: 5000,
      ballotRedemptionRate: 0,
      pausePay: false,
      pauseDistributions: false,
      pauseRedeem: false,
      pauseBurn: false,
      allowMinting: true,
      preferClaimedTokenOverride: false,
      allowTerminalMigration: false,
      allowControllerMigration: false,
      holdFees: false,
      useTotalOverflowForRedemptions: false,
      useDataSourceForPay: true,
      useDataSourceForRedeem: false,
      dataSource: address(_delegate),
      metadata: 0
    });

    _fundAccessConstraints.push(
      JBFundAccessConstraints({
        terminal: jbETHPaymentTerminal(),
        token: jbLibraries().ETHToken(),
        distributionLimit: 2 ether,
        overflowAllowance: type(uint232).max,
        distributionLimitCurrency: 1, // Currency = ETH
        overflowAllowanceCurrency: 1
      })
    );

    _terminals = [jbETHPaymentTerminal()];

    JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1); // Default empty

    _projectId = controller.launchProjectFor(
      multisig(),
      _projectMetadata,
      _data,
      _metadata,
      0, // Start asap
      _groupedSplits,
      _fundAccessConstraints,
      _terminals,
      ''
    );
  }

  /**
   * @notice  If the quote amount is lower than the token that would be received after minting, the buyback delegate isn't used at all
   */
  function testDatasourceDelegateWhenQuoteIsLowerThanTokenCount(uint256 _quote) public {
    _quote = bound(_quote, 0, weight);

    uint256 payAmountInWei = 2 ether;

    // setting the quote in metadata, bigger than the weight
    bytes memory metadata = abi.encode(new bytes(0), new bytes(0), _quote, 500);
    
    jbETHPaymentTerminal().pay{value: payAmountInWei}(
      _projectId,
      payAmountInWei,
      address(0),
      beneficiary(),
      /* _minReturnedTokens */
      0,
      /* _preferClaimedTokens */
      true,
      /* _memo */
      'Take my money!',
      /* _delegateMetadata */
      metadata
    );

    // Compute the project token which should have been minted (for the beneficiary or the reserve)
    uint256 totalMinted = PRBMath.mulDiv(payAmountInWei, weight, 10**18);
    uint256 amountBeneficiary = (totalMinted * (JBConstants.MAX_RESERVED_RATE - reservedRate)) /
      JBConstants.MAX_RESERVED_RATE;
    uint256 amountReserved = totalMinted - amountBeneficiary;

    // Check: correct beneficiary balance?
    assertEq(jbTokenStore().balanceOf(beneficiary(), _projectId), amountBeneficiary);

    // Check: correct reserve?
    assertEq(controller.reservedTokenBalanceOf(_projectId, reservedRate), amountReserved);
  }

  /**
   * @notice If claimed token flag is not true then make sure the delegate mints the tokens & the balance distribution is correct
   */
  function testDatasourceDelegateMintIfPreferenceIsNotToClaimTokens() public {
    uint256 payAmountInWei = 10 ether;

    // setting the quote in metadata
    bytes memory metadata = abi.encode(new bytes(0), new bytes(0), 1 ether, 10000);

    jbETHPaymentTerminal().pay{value: payAmountInWei}(
      _projectId,
      payAmountInWei,
      address(0),
      beneficiary(),
      /* _minReturnedTokens */
      0, // Cannot be used in this setting
      /* _preferClaimedTokens */
      false,
      /* _memo */
      'Take my money!',
      /* _delegateMetadata */
      metadata
    );

    uint256 totalMinted = PRBMath.mulDiv(payAmountInWei, weight, 10**18);
    uint256 amountBeneficiary = PRBMath.mulDiv(
        totalMinted,
        JBConstants.MAX_RESERVED_RATE - reservedRate,
        JBConstants.MAX_RESERVED_RATE
      );

    uint256 amountReserved = totalMinted - amountBeneficiary;

    assertEq(jbTokenStore().balanceOf(beneficiary(), _projectId), amountBeneficiary);
    assertEq(controller.reservedTokenBalanceOf(_projectId, reservedRate), amountReserved);
    assertEq(jbPaymentTerminalStore().balanceOf(jbETHPaymentTerminal(), _projectId), payAmountInWei);
  }

  /**
   * @notice if claimed token flag is true and the quote is greather than the weight, we go for the swap path
   */
  function testDatasourceDelegateSwapIfPreferenceIsToClaimTokens() public {
    uint256 payAmountInWei = 1 ether;
    uint256 quoteOnUniswap = weight * 106 / 100; // Take slippage into account

    // Trick the delegate balance post-swap (avoid callback revert on slippage)
    evm.prank(multisig());
    jbController().mintTokensOf(_projectId, quoteOnUniswap, address(_delegate), '', false, false);

    // setting the quote in metadata
    bytes memory metadata = abi.encode(new bytes(0), new bytes(0), quoteOnUniswap, 500);

    // Mock the jbx transfer to the beneficiary - same logic as in delegate to avoid rounding errors
    uint256 reservedAmount = PRBMath.mulDiv(
      quoteOnUniswap,
      reservedRate,
      JBConstants.MAX_RESERVED_RATE
    );

    uint256 nonReservedAmount = quoteOnUniswap - reservedAmount;

    // Mock the transfer to the beneficiary
    evm.mockCall(
      address(jbx),
      abi.encodeWithSelector(
        IERC20.transfer.selector,
        beneficiary(),
        nonReservedAmount
      ),
      abi.encode(true)
    );

    // Check: token actually transfered?
    evm.expectCall(
      address(jbx),
      abi.encodeWithSelector(
        IERC20.transfer.selector,
        beneficiary(),
        nonReservedAmount
      )
    );

    // Mock the swap returned value, which is the amount of token transfered (negative = exact amount)
    evm.mockCall(
      address(pool),
      abi.encodeWithSelector(IUniswapV3PoolActions.swap.selector),
      abi.encode(-int256(quoteOnUniswap), 0)
    );

    // Check: swap triggered?
    evm.expectCall(
      address(pool),
      abi.encodeWithSelector(IUniswapV3PoolActions.swap.selector)
    );

    jbETHPaymentTerminal().pay{value: payAmountInWei}(
      _projectId,
      payAmountInWei,
      address(0),
      beneficiary(),
      /* _minReturnedTokens */
      0,
      /* _preferClaimedTokens */
      true,
      /* _memo */
      'Take my money!',
      /* _delegateMetadata */
      metadata
    );

    // Check: correct reserve balance?
    assertEq(
      controller.reservedTokenBalanceOf(_projectId, reservedRate),
      reservedAmount
    );
  }

  /**
   * @notice Test the uniswap callback reverting when max slippage is hit
   *
   * @dev    This would mean the _mint is then called
   */
  function testRevertIfSlippageIsTooMuchWhenSwapping() public {
    // construct metadata, minimum amount received is 100 
    bytes memory metadata = abi.encode(100 ether);

    evm.prank(address(pool));
    evm.expectRevert(abi.encodeWithSignature("JuiceBuyback_MaximumSlippage()"));

    // callback giving 1 instead
    _delegate.uniswapV3SwapCallback(-1 ether, 1 ether, metadata);
  }
}