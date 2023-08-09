// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";

import {MockV3Aggregator} from "@mock/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {DecentralisedStableCoin} from "@DSC/DecentralisedStableCoin.sol";
import {DecentralisedStableCoinEngine} from "@DSC/DecentralisedStableCoinEngine.sol";

contract Handler is Test {
    uint256 private constant MAX_DEPOSIT = type(uint96).max;

    ERC20Mock private wEth;
    ERC20Mock private wBTC;
    DecentralisedStableCoin private dsc;
    DecentralisedStableCoinEngine private engine;
    MockV3Aggregator private ethUsdPriceFeed;
    MockV3Aggregator private btcUsdPriceFeed;

    constructor(
        DecentralisedStableCoin _dsc,
        DecentralisedStableCoinEngine _engine,
        address[2] memory _collateralTokens
    ) {
        dsc = _dsc;
        engine = _engine;
        wEth = ERC20Mock(_collateralTokens[0]);
        wBTC = ERC20Mock(_collateralTokens[1]);

        btcUsdPriceFeed = MockV3Aggregator(engine.getFeedFromCollateralToken(address(wBTC)));
        ethUsdPriceFeed = MockV3Aggregator(engine.getFeedFromCollateralToken(address(wEth)));
    }

    function depositCollateral(uint256 _collateralSeed, uint256 _collateralAmount) public {
        ERC20Mock collateralToken = _getCollateralFromSeed(_collateralSeed);
        _collateralAmount = bound(_collateralAmount, 1, MAX_DEPOSIT);

        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, _collateralAmount);
        collateralToken.approve(address(engine), _collateralAmount);

        engine.depositCollateral(address(collateralToken), _collateralAmount);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 _collateralSeed, uint256 _collateralAmount) public {
        ERC20Mock collateralToken = _getCollateralFromSeed(_collateralSeed);

        uint256 maxCollateralRedeemable = engine.getCollateralValue(msg.sender, address(collateralToken));
        _collateralAmount = bound(_collateralAmount, 0, maxCollateralRedeemable);

        console.log("redeemCollateral: ", _collateralAmount);
        console.log("maxCollateralRedeemable: ", maxCollateralRedeemable);
        if (_collateralAmount == 0) {
            return;
        }

        engine.redeemCollateral(address(collateralToken), _collateralAmount);
    }

    function burnDsc(uint256 _amountDsc) public {
        // Must burn more than 0
        _amountDsc = bound(_amountDsc, 0, dsc.balanceOf(msg.sender));
        if (_amountDsc == 0) {
            return;
        }

        engine.burnDSC(_amountDsc);
    }

    function transferDsc(uint256 _amountDsc, address _to) public {
        if (_to == address(0)) {
            _to = address(1);
        }
        _amountDsc = bound(_amountDsc, 0, dsc.balanceOf(msg.sender));
        vm.prank(msg.sender);
        dsc.transfer(_to, _amountDsc);
    }

    // THIS IS A KNOWN BUG, IF THE COLLATERAL VALUE DROPS TOO QUICKLY, THE PROTOCOL MAY CRASH
    function updateCollateralPrice(uint96 newPrice, uint256 collateralSeed) public {
      int256 intNewPrice = int256(uint256(newPrice));
      ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
      MockV3Aggregator priceFeed = MockV3Aggregator(engine.getFeedFromCollateralToken(address(collateral)));

      priceFeed.updateAnswer(intNewPrice);
    }

    function _getCollateralFromSeed(uint256 _seed) public view returns (ERC20Mock) {
        if (_seed % 2 == 0) {
            return wEth;
        }

        return wBTC;
    }
}
