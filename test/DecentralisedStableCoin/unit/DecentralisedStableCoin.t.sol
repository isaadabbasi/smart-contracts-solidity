// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// *** System level packages ***
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

// *** Installed libraries/packages ***
import { ERC20Mock } from '@openzeppelin/contracts/mocks/ERC20Mock.sol';

// *** Custom contracts *** //
import { DecentralisedStableCoin } from '@DSC/DecentralisedStableCoin.sol';
import { DecentralisedStableCoinEngine } from '@DSC/DecentralisedStableCoinEngine.sol';
import { DeployDecentralisedStableCoinEngine } from '@DSCScript/DeployDecentralisedStableCoinEngine.s.sol';

contract DecentralisedStableCoinTest is Test {
  
  address ALICE = makeAddr("1");

  DecentralisedStableCoin private dsc;
  DecentralisedStableCoinEngine private engine;
  
  function setUp() external {
    DeployDecentralisedStableCoinEngine deployer = new DeployDecentralisedStableCoinEngine();
    (dsc, engine,) = deployer.run();
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
    vm.prank(address(engine));
    _;
  }

}
