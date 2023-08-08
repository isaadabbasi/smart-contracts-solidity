// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IDecentralisedStableCoinEngine {
  function burnDSC(uint256) external;

  function depositCollateral(address, uint256) external;

  function depositCollateralAndMintDSC(address, uint256, uint256) external;

  function getHealthFactor(address) external view returns(uint256);

  function liquidate(address, address, uint256) external;

  function mintDsc(uint256) external;

  function redeemCollateral(address, uint256) external;

  function redeemCollateralForDsc(address, uint256, uint256) external;
}