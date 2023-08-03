// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IDecentralisedStableCoinEngine {
  function burnDSC(uint256 _amount) external;

  function depositCollateral(address, uint256) external;

  function depositCollateralAndMintDSC() external;

  function getHealthFactor() external view;

  function liquidate() external;

  function mintDsc(uint256) external;

  function redeemCollateral() external;

  function redeemCollateralForDsc() external;
}