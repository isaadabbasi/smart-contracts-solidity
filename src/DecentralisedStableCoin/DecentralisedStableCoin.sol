// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { ERC20, ERC20Burnable } from '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title Decentralised Stable Coin
 * @author Saad Abbasi, @isaadabbasi
 * @notice This is an ERC20 implementation of a Decentralised Stable Coin.
 * Where: 
 * -  The stablility is Relative/Anchored Stability comes from collatoralization of Eth and BTC.
 * -  Its pegged to USD (1 DSC -> 1 USD)
 * - Governed by a DAO/Contract called DSC Engine, which makes it algorithmic.
 * 
 * @notice This contract is for educational purposes only. 
 */
contract DecentralisedStableCoin is ERC20Burnable, Ownable {
  error DSC__InsufficientBalance();
  error DSC__AddressNotAllowed();
  error DSC__InvalidAmount();

  constructor() ERC20('DecentralisedStableCoin', 'DSC') {}

  function burn(uint256 _amount) public override onlyOwner {
    uint256 balance = balanceOf(msg.sender);
    if (balance == 0 || _amount > balance) {
      revert DSC__InsufficientBalance();
    }

    super.burn(_amount);
  }

  function mint(
    address _to,
    uint256 _amount
  ) external onlyOwner returns (bool) {

    // TODO - Redundant
    if (_to == address(0)) revert DSC__AddressNotAllowed();
    if (_amount <= 0) revert DSC__InvalidAmount();

    _mint(_to, _amount);
    return true;
  }

}