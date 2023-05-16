// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplitAllocationData.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayDelegate.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol';

import '@openzeppelin/contracts/utils/introspection/ERC165.sol';

contract MockAllocator is ERC165, IJBSplitAllocator {


  IJBPayDelegate public immutable payDelegate;

  constructor(IJBPayDelegate _payDelegate) {
    payDelegate = _payDelegate;
  }

  function allocate(JBSplitAllocationData calldata _data) external payable override {
    _data;

    JBDidPayData memory _didPaydata = JBDidPayData(
          address(this),
          1,
          2,
          JBTokenAmount(address(this), 1 ether, 10 ** 18, 0),
          JBTokenAmount(address(this), 1 ether, 10 ** 18, 0),
          1,
          address(this),
          true,
          '',
          new bytes(0)
    );
    
    // makes a malicious delegate call to the buyback delegate
    (bool success, ) = address(payDelegate).delegatecall(
        abi.encodeWithSignature("didPay(JBDidPayData)", _didPaydata)
    );
    assert(success);
  }
  

  function supportsInterface(bytes4 _interfaceId)
    public
    view
    override(IERC165, ERC165)
    returns (bool)
  {
    return
      _interfaceId == type(IJBSplitAllocator).interfaceId || super.supportsInterface(_interfaceId);
  }
}
