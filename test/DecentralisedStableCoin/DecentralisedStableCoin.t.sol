// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { DecentralisedStableCoin } from '@DSC/DecentralisedStableCoin.sol';
import { DeployDecentralisedStableCoin } from '@DSCScript/DeployDecentralisedStableCoin.s.sol';

contract DecentralisedStableCoinTest is Test {
  
  address ALICE = makeAddr("1");

  DecentralisedStableCoin private dsc;
  
  function setUp() external {
    DeployDecentralisedStableCoin deployer = new DeployDecentralisedStableCoin();
    dsc = deployer.run();
  }

  function test_mintByNonAdmin() public {
    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    dsc.mint(ALICE, 0);
  }

  function test_mintToZeroAddress() public isOwner {
    vm.expectRevert(DecentralisedStableCoin.DSC__AddressNotAllowed.selector);
    dsc.mint(address(0), 1);
  }

  function test_mintWithInvalidAmount() public isOwner {
    vm.expectRevert(DecentralisedStableCoin.DSC__InvalidAmount.selector);
    dsc.mint(ALICE, 0);
  }

  function test_mintSuccessOnValidArguments() public isOwner {
    bool minted = dsc.mint(ALICE, 1);
    assertEq(minted, true);

    uint256 balance = dsc.balanceOf(ALICE);
    assertEq(balance, 1);
  }

  function test_burnByNonAdmin() public {
    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    dsc.burn(1);
  }

  function test_burnWithZeroAmount()  public isOwner {
    vm.expectRevert(DecentralisedStableCoin.DSC__InsufficientBalance.selector);
    dsc.burn(0);
  }

  function test_burnSuccessOnValidArguments() public isOwner {    
    // TODO - Implement later
  }

  modifier isOwner() {
    vm.prank(msg.sender);
    _;
  }

}
