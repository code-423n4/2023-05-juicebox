// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import 'forge-std/Test.sol';

import '@jbx-protocol/juice-contracts-v3/contracts/JBController.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBDirectory.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBSingleTokenPaymentTerminalStore.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBFundingCycleStore.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBOperatorStore.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBPrices.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBProjects.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBSplitsStore.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/JBTokenStore.sol';

import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidPayData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidRedeemData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFee.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBToken.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol';


import './AccessJBLib.sol';

import '@paulrberg/contracts/math/PRBMath.sol';

// Base contract for Juicebox system tests.
//
// Provides common functionality, such as deploying contracts on test setup for v3.
contract TestBaseWorkflowV3 is Test {
  //*********************************************************************//
  // --------------------- private stored properties ------------------- //
  //*********************************************************************//

  // Multisig address used for testing.
  address private _multisig = address(123);

  address private _beneficiary = address(69420);

  // EVM Cheat codes - test addresses via prank and startPrank in hevm
  Vm public evm = Vm(HEVM_ADDRESS);

  // JBOperatorStore
  JBOperatorStore private _jbOperatorStore;
  // JBProjects
  JBProjects private _jbProjects;
  // JBPrices
  JBPrices private _jbPrices;
  // JBDirectory
  JBDirectory private _jbDirectory;
  // JBFundingCycleStore
  JBFundingCycleStore private _jbFundingCycleStore;
  // JBTokenStore
  JBTokenStore private _jbTokenStore;
  // JBSplitsStore
  JBSplitsStore private _jbSplitsStore;
  // JBController
  JBController private _jbController;
  // JBETHPaymentTerminalStore
  JBSingleTokenPaymentTerminalStore private _jbPaymentTerminalStore;
  // JBETHPaymentTerminal
  JBETHPaymentTerminal private _jbETHPaymentTerminal;
  // AccessJBLib
  AccessJBLib private _accessJBLib;

  //*********************************************************************//
  // ------------------------- internal views -------------------------- //
  //*********************************************************************//

  function multisig() internal view returns (address) {
    return _multisig;
  }

  function beneficiary() internal view returns (address) {
    return _beneficiary;
  }

  function jbOperatorStore() internal view returns (JBOperatorStore) {
    return _jbOperatorStore;
  }

  function jbProjects() internal view returns (JBProjects) {
    return _jbProjects;
  }

  function jbPrices() internal view returns (JBPrices) {
    return _jbPrices;
  }

  function jbDirectory() internal view returns (JBDirectory) {
    return _jbDirectory;
  }

  function jbFundingCycleStore() internal view returns (JBFundingCycleStore) {
    return _jbFundingCycleStore;
  }

  function jbTokenStore() internal view returns (JBTokenStore) {
    return _jbTokenStore;
  }

  function jbSplitsStore() internal view returns (JBSplitsStore) {
    return _jbSplitsStore;
  }

  function jbController() internal view returns (JBController) {
    return _jbController;
  }

  function jbPaymentTerminalStore() internal view returns (JBSingleTokenPaymentTerminalStore) {
    return _jbPaymentTerminalStore;
  }

  function jbETHPaymentTerminal() internal view returns (JBETHPaymentTerminal) {
    return _jbETHPaymentTerminal;
  }

  function jbLibraries() internal view returns (AccessJBLib) {
    return _accessJBLib;
  }

  //*********************************************************************//
  // --------------------------- test setup ---------------------------- //
  //*********************************************************************//

  // Deploys and initializes contracts for testing.
  function setUp() public virtual {
    // Labels
    evm.label(_multisig, 'projectOwner');
    evm.label(_beneficiary, 'beneficiary');

    // JBOperatorStore
    _jbOperatorStore = new JBOperatorStore();
    evm.label(address(_jbOperatorStore), 'JBOperatorStore');

    // JBProjects
    _jbProjects = new JBProjects(_jbOperatorStore);
    evm.label(address(_jbProjects), 'JBProjects');

    // JBPrices
    _jbPrices = new JBPrices(_multisig);
    evm.label(address(_jbPrices), 'JBPrices');

    address contractAtNoncePlusOne = addressFrom(address(this), 5);

    // JBFundingCycleStore
    _jbFundingCycleStore = new JBFundingCycleStore(IJBDirectory(contractAtNoncePlusOne));
    evm.label(address(_jbFundingCycleStore), 'JBFundingCycleStore');

    // JBDirectory
    _jbDirectory = new JBDirectory(_jbOperatorStore, _jbProjects, _jbFundingCycleStore, _multisig);
    evm.label(address(_jbDirectory), 'JBDirectory');

    // JBTokenStore
    _jbTokenStore = new JBTokenStore(_jbOperatorStore, _jbProjects, _jbDirectory, _jbFundingCycleStore);
    evm.label(address(_jbTokenStore), 'JBTokenStore');

    // JBSplitsStore
    _jbSplitsStore = new JBSplitsStore(_jbOperatorStore, _jbProjects, _jbDirectory);
    evm.label(address(_jbSplitsStore), 'JBSplitsStore');

    // JBController
    _jbController = new JBController(
      _jbOperatorStore,
      _jbProjects,
      _jbDirectory,
      _jbFundingCycleStore,
      _jbTokenStore,
      _jbSplitsStore
    );
    evm.label(address(_jbController), 'JBController');

    evm.prank(_multisig);
    _jbDirectory.setIsAllowedToSetFirstController(address(_jbController), true);

    // JBETHPaymentTerminalStore
    _jbPaymentTerminalStore = new JBSingleTokenPaymentTerminalStore(
      _jbDirectory,
      _jbFundingCycleStore,
      _jbPrices
    );
    evm.label(address(_jbPaymentTerminalStore), 'JBSingleTokenPaymentTerminalStore');

    // AccessJBLib
    _accessJBLib = new AccessJBLib();

    // JBETHPaymentTerminal
    _jbETHPaymentTerminal = new JBETHPaymentTerminal(
      _accessJBLib.ETH(),
      _jbOperatorStore,
      _jbProjects,
      _jbDirectory,
      _jbSplitsStore,
      _jbPrices,
      _jbPaymentTerminalStore,
      _multisig
    );
    evm.label(address(_jbETHPaymentTerminal), 'JBETHPaymentTerminal');
  }

  //https://ethereum.stackexchange.com/questions/24248/how-to-calculate-an-ethereum-contracts-address-during-its-creation-using-the-so
  function addressFrom(address _origin, uint256 _nonce) internal pure returns (address _address) {
    bytes memory data;
    if (_nonce == 0x00) data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80));
    else if (_nonce <= 0x7f)
      data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce));
    else if (_nonce <= 0xff)
      data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce));
    else if (_nonce <= 0xffff)
      data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce));
    else if (_nonce <= 0xffffff)
      data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce));
    else data = abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce));
    bytes32 hash = keccak256(data);
    assembly {
      mstore(0, hash)
      _address := mload(0)
    }
  }
}

