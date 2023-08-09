// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// *** System imports *** // 
import { console } from "forge-std/console.sol";
import { Test } from 'forge-std/Test.sol';
import { StdInvariant } from 'forge-std/StdInvariant.sol';


// *** Installed Libraries/Packages imports *** // 
import { IERC20 } from '@openzeppelin/contracts/interfaces/IERC20.sol';

// *** Custom contract/library imports *** // 
import { Handler as FuzzHandler } from './Handler.f.sol';
import { DecentralisedStableCoinEngine } from '@DSC/DecentralisedStableCoinEngine.sol';
import { DecentralisedStableCoin } from '@DSC/DecentralisedStableCoin.sol';
import { HelperConfig } from '@DSCScript/HelperConfig.s.sol';
import { DeployDecentralisedStableCoinEngine } from '@DSCScript/DeployDecentralisedStableCoinEngine.s.sol';

contract DSCOpenInvariantTest is StdInvariant, Test {
  
  address private wEth;
  address private wBTC;
  
  DecentralisedStableCoinEngine private engine;
  DecentralisedStableCoin private dsc;
  HelperConfig private hc;

  function setUp() public {
    
    DeployDecentralisedStableCoinEngine deployer = new DeployDecentralisedStableCoinEngine();
    (dsc, engine, hc) = deployer.run();
    (wEth,,wBTC,,) = hc.active();
    address[2] memory tokenAddresses = [wEth, wBTC];
    FuzzHandler handler = new FuzzHandler(dsc, engine, tokenAddresses);
    targetContract(address(handler));
  }

  function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
    uint256 dscTotalSupply = dsc.totalSupply();
    uint256 totalwEthDeposited = IERC20(wEth).balanceOf(address(engine));
    uint256 totalwBTCDeposited = IERC20(wBTC).balanceOf(address(engine));

    uint256 totalwEthValue = engine.getTokenValue(wEth, totalwEthDeposited);
    uint256 totalwBTCValue = engine.getTokenValue(wBTC, totalwBTCDeposited);

    uint256 totalValueLocked = totalwEthValue + totalwBTCValue;
    assert(totalValueLocked >= dscTotalSupply);
  }

  function invariant_gettersCantRevert() public view {
    
    // TODO (not really) - implement getters in engine for constants and immutables.
    // * Leaving it due to laziness. 
    // engine.getCollateralTokens();
    // engine.getLiquidationBonus();
    // engine.getLiquidationBonus();
    // engine.getLiquidationThreshold();
    // engine.getMinHealthFactor();
    // engine.getPrecision();
    // engine.getDsc();
    // engine.getAccountCollateralValue();
    //etc
    }

}