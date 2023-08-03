// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {IDecentralisedStableCoinEngine} from "./IDecentralisedStableCoinEngine.sol";

/**
 * @title Decentralised Stable Coin
 * @author Saad Abbasi | isaadabbasi
 * @notice The governance contract for Decentralised Stable Coin. -
 * It is similar to DAI if DAI had no governance, no fees and backed by wEth and wBTC.
 * It will always be over-collateralised with roughly 140% of liquidation boundry, -
 *  If the collateral worth reached the liquidation boundry, it will be liquidated.
 * It handles the logic for mining, depositing, and redeeming of collateral.
 */

contract DecentralisedStableCoinEngine is IDecentralisedStableCoinEngine, ReentrancyGuard {
    // *** Types  *** //

    // *** Constants *** //
    uint256 private constant FEED_PRECISION = 10e8;
    uint256 private constant PRECISION = 10e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; 
    uint256 private constant LIQUIDATION_PRECISION = 100; 
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1; 

    // *** State Variables *** //
    mapping(address user => mapping(address token => uint256 balance)) private collateralDeposited;
    mapping(address user => uint256 DSCMinted) private DSCMinted;
    mapping(address token => address priceFeed) private priceFeed;
    address[] private collateralTokens;

    DecentralisedStableCoin private immutable DSC;

    // *** Errors *** //
    error DSCEngine__MinimumHealthFactorReached(); 
    error DSCEngine__MintingFailed();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokensAndPriceFeedLengthMismatch();
    error DSCEngine__TransferFailed();

    // *** Events *** //
    event DSCEngine__CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    // *** Modifiers *** //

    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isTokenAllowed(address _token) {
        if (priceFeed[_token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    // *** Special Functions  *** //
    constructor(address[] memory _tokens, address[] memory _priceFeeds, address _dsc) {
        if (_tokens.length != _priceFeeds.length) {
            revert DSCEngine__TokensAndPriceFeedLengthMismatch();
        }

        // For example: USDC => BTC/USDC, USDT => BTC/USDT
        for (uint64 i = 0; i < _tokens.length; i++) {
            priceFeed[_tokens[i]] = _priceFeeds[i];
            collateralTokens.push(_tokens[i]);
        }

        DSC = DecentralisedStableCoin(_dsc);
    }

    // *** Private and Internal Functions *** //

    /**
     * @param _user user address for which we want to get the account information
     * @return totalDSCMinted Total stable coins minted againsted deposited collateral
     * @return totalCollateralValue Total value of collateral in USD
     */
    function _getAccountInformation(address _user)
        internal
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValue)
    {
        totalDSCMinted = DSCMinted[_user];
        totalCollateralValue = _getTotalCollateralValue(_user);
    }

    /**
     * @param _user user address for which we want to get the total value of collateral
     * @notice Returns the total value of collateral in USD
     */
    function _getTotalCollateralValue(address _user) internal view returns (uint256) {
      uint256 totalValueInUSD = 0;
      uint256 iMax = collateralTokens.length;
      for (uint32 i = 0; i < iMax; i++) {
        address token = collateralTokens[i];
        uint256 amount = collateralDeposited[_user][token];

        if (amount == 0) continue;

        uint256 valueInUSD = _getTokenValue(token, amount);
        totalValueInUSD += valueInUSD;
      }
      return totalValueInUSD;
    }

    /**
     * @param _token wBTC, wEth Contract Addresses
     * @param _amount Amount of BTC or ETH deposited (18 decimal)
     * @notice Returns the value of the token in USD
     */
    function _getTokenValue(address _token, uint256 _amount) internal view returns (uint256) {
      
      AggregatorV3Interface aggregator = AggregatorV3Interface(priceFeed[_token]);
      (, int256 price,,,) = aggregator.latestRoundData();
      // _amount is also 18 decimate value. so $1000 = 1000 * 10e18;
      return ((uint256(price) * FEED_PRECISION) * _amount) / PRECISION;
    }

    /**
     * @notice Describes how close a user is to the liquidation boundary
     * If a user goes below 1, then it will be liquidated
     */
    function _healthFactor(address _user) internal view returns (uint256) {
      (uint256 _DSCMinted, uint256 totalCollateralValue) = _getAccountInformation(_user);
      // Example: $1000 Eth * LIQUIDATION_THRESHOLD = $50,000 / LIQUIDATION_PRECISION = $500;
      // Example: $1000 Eth * LIQUIDATION_THRESHOLD = $50,000 / LIQUIDATION_PRECISION = $500;
      uint256 collateralAdjustedForThreshold = (totalCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
      // let's say if the user minted $500 worth of DSC,
      // Example continued: $500 * 10e18 = 5000e18 / _DSCMinted = $500*10e18 / $500*10e18 = 1;
      // let's say if the user minted $200 DSC,
      // Example continued: $500 * 10e18 = 5000e18 / _DSCMinted = $500*10e18 / $200*10e18 = 2.5 = 2;
      // let's say if the user minted $600 DSC, 
      // Example continued: $500 * 10e18 = 5000e18 / _DSCMinted = $500*10e18 / $600*10e18 = 0.83 = 0;
      return (collateralAdjustedForThreshold * PRECISION) / _DSCMinted;
    }

    function _revertIfHealthFactorisBroken(address _user) internal view {
      uint256 healthFactor = _healthFactor(_user);
      if (healthFactor < MINIMUM_HEALTH_FACTOR) { // TODO - Should it be <= or <
        revert DSCEngine__MinimumHealthFactorReached();
      }
    }

    // *** Public and External Functions *** //
    function burnDSC(uint256 _amount) external {
        // TODO - implement this
    }

    /**
     * @param _collateralToken address for wEth or wBTC
     * @param _collateralAmount 150% worth of collateral of mintable DSCs
     */
    function depositCollateral(address _collateralToken, uint256 _collateralAmount)
        external
        moreThanZero(_collateralAmount)
        isTokenAllowed(_collateralToken)
        nonReentrant
    {
        collateralDeposited[msg.sender][_collateralToken] += _collateralAmount;
        emit DSCEngine__CollateralDeposited(msg.sender, _collateralToken, _collateralAmount);

        bool success = IERC20(_collateralToken).transferFrom(msg.sender, address(this), _collateralAmount);
        if (success == false) {
            revert DSCEngine__TransferFailed();
        }
    }

    function depositCollateralAndMintDSC() external {
        // TODO - implement this
    }

    function getHealthFactor() external view {
      
    }

    function liquidate() external {
        // TODO - implement this
    }

    /**
     * @param _amount less 75% of the amount of deposited collateral
     */
    function mintDsc(uint256 _amount) external moreThanZero(_amount) nonReentrant {
      DSCMinted[msg.sender] += _amount;

      // It will revert only if health factor is less than MINIMUM_HEALTH_FACTOR
      _revertIfHealthFactorisBroken(msg.sender);

      bool minted = DSC.mint(msg.sender, _amount);
      if (minted == false) {
        revert DSCEngine__MintingFailed();
      }
    }

    function redeemCollateral() external {
        // TODO - implement this
    }

    function redeemCollateralForDsc() external {
        // TODO - implement this
    }
}
