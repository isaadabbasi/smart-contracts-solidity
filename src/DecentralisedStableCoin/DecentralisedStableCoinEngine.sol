// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console} from "forge-std/console.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "@library/OracleLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

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
    // *** Premitive Proxies *** //
    using OracleLib for AggregatorV3Interface;

    // *** Constants *** //
    uint256 private constant FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATOR_BONUS = 10;

    // *** State Variables *** //
    mapping(address user => mapping(address token => uint256 balance)) private collateralDeposited;
    mapping(address user => uint256 DSCMinted) private DSCMinted;
    mapping(address collateralTokens => address priceFeed) private priceFeed;
    address[] private unallowedTokens;
    address[] private collateralTokens;

    DecentralisedStableCoin private immutable DSC;

    // *** Errors *** //
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__MinimumHealthFactorReached();
    error DSCEngine__MintingFailed();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokensAndPriceFeedLengthMismatch();
    error DSCEngine__TransferFailed();
    error DSCEngine__CollateralAddressIsNotAllowed();
    error DSCEngine__MintedDSCExceedingThreshold();

    // *** Events *** //
    event DSCEngine__CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event DSCEngine__CollateralRedeemed(
        address indexed from, address indexed to, address indexed token, uint256 amount
    );

    // *** Modifiers *** //

    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isCollateralAddress(address _token) {
        uint256 totalCollateralTokens = collateralTokens.length;
        bool isSupported = false;
        for (uint256 i = 0; i < totalCollateralTokens; ++i) {
            if (_token == collateralTokens[i]) {
                isSupported = true;
                break;
            }
        }
        if (isSupported == false) {
            revert DSCEngine__CollateralAddressIsNotAllowed();
        }
        _;
    }

    modifier isTokenAllowed(address _token) {
        uint256 numOfUnallowedTokens = unallowedTokens.length;
        for (uint256 i = 0; i < numOfUnallowedTokens; ++i) {
            if (_token == unallowedTokens[i]) {
                revert DSCEngine__TokenNotAllowed();
            }
        }
        _;
    }

    // *** Special Functions  *** //
    constructor(address[] memory _tokens, address[] memory _priceFeeds, address _dsc) {
        if (_tokens.length != _priceFeeds.length) {
            revert DSCEngine__TokensAndPriceFeedLengthMismatch();
        }

        // For example: USDC => BTC/USDC, USDT => BTC/USDT
        for (uint64 i = 0; i < _tokens.length; ++i) {
            priceFeed[_tokens[i]] = _priceFeeds[i];
            collateralTokens.push(_tokens[i]);
        }
        unallowedTokens.push(address(0));
        DSC = DecentralisedStableCoin(_dsc);
    }

    // *** Private and Internal Functions *** //

    function _burnDSC(address _onBehalfOf, address _dscFrom, uint256 _amount) private {
        DSCMinted[_onBehalfOf] -= _amount;
        bool success = DSC.transferFrom(_dscFrom, address(this), _amount);
        if (success == false) {
            revert DSCEngine__TransferFailed();
        }
        DSC.burn(_amount);
    }
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

    function _getCollateralValue(address _user, address _collateralToken) private view returns (uint256) {
        uint256 amount = collateralDeposited[_user][_collateralToken];

        if (amount == 0) return 0;

        return _getTokenValue(_collateralToken, amount);
    }

    /**
     * @param _user user address for which we want to get the total value of collateral
     * @notice Returns the total value of collateral in USD
     */
    function _getTotalCollateralValue(address _user) internal view returns (uint256) {
        uint256 totalValueInUSD = 0;
        uint256 numOfCollateralTokens = collateralTokens.length;
        for (uint32 i = 0; i < numOfCollateralTokens; i++) {
            totalValueInUSD += _getCollateralValue(_user, collateralTokens[i]);
        }
        return totalValueInUSD;
    }

    function _getTokenAmountFromUSD(address _collateralToken, uint256 _usdAmountInWei) private view returns (uint256) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(priceFeed[_collateralToken]);
        (, int256 price,,,) = aggregator.staleCheckLatestRoundData();

        return (_usdAmountInWei * PRECISION) / (uint256(price) * FEED_PRECISION);
    }

    /**
     * @param _token wBTC, wEth Contract Addresses
     * @param _amount Amount of BTC or ETH deposited (18 decimal)
     * @notice Returns the value of the token in USD
     */
    function _getTokenValue(address _token, uint256 _amount) private view returns (uint256) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(priceFeed[_token]);
        (, int256 price,,,) = aggregator.staleCheckLatestRoundData();
        // _amount is also 18 decimate value. so $1000 = 1000 * 1e18;
        return ((uint256(price) * FEED_PRECISION) * _amount) / PRECISION;
    }

    /**
     * @notice Describes how close a user is to the liquidation boundary
     * If a user goes below 1, then it will be liquidated
     */
    function _calcHealthFactor(uint256 _dscMinted, uint256 totalCollateralValue) private pure returns (uint256) {
        if (_dscMinted == 0) {
            return type(uint256).max;
        }
        // Example: $1000 Eth * LIQUIDATION_THRESHOLD = $50,000 / LIQUIDATION_PRECISION = $500;
        // Example: $1000 Eth * LIQUIDATION_THRESHOLD = $50,000 / LIQUIDATION_PRECISION = $500;
        uint256 collateralAdjustedForThreshold = (totalCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // let's say if the user minted $500 worth of DSC,
        // Example continued: $500 * 1e18 = 5000e18 / _DSCMinted = $500*1e18 / $500*1e18 = 1;
        // let's say if the user minted $200 DSC,
        // Example continued: $500 * 1e18 = 5000e18 / _DSCMinted = $500*1e18 / $200*1e18 = 2.5 = 2;
        // let's say if the user minted $600 DSC,
        // Example continued: $500 * 1e18 = 5000e18 / _DSCMinted = $500*1e18 / $600*1e18 = 0.83 = 0;
        
        return (collateralAdjustedForThreshold * PRECISION) / _dscMinted;
    }

    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 dscMinted, uint256 totalCollateralValue) = _getAccountInformation(_user);
        return _calcHealthFactor(dscMinted, totalCollateralValue);
    }

    /**
     * @param _from Address that deposited the collateral
     * @param _to Address where we need to send the collateral back
     * @param _collateralToken Address of the Collateral Token like wEth, wBTC, etc...
     * @param _collateralAmount Amount of collateral deposited
     * @notice To be used to pull collateral back and burn borrowed DSCs. 
     * and also used to liquidate the user, which contains this function as a part.
     */
    function _redeemCollateral(address _from, address _to, address _collateralToken, uint256 _collateralAmount)
        private
        moreThanZero(_collateralAmount)
        isCollateralAddress(_collateralToken)
        isTokenAllowed(_from)
    {
        // ? - What if requested _collateralAmount is more than the deposited collateral?
        collateralDeposited[_from][_collateralToken] -= _collateralAmount;
        emit DSCEngine__CollateralRedeemed(_from, _to, _collateralToken, _collateralAmount);

        bool success = IERC20(_collateralToken).transfer(_to, _collateralAmount);
        if (success == false) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _revertIfHealthFactorisBroken(address _user) internal view {
        (uint256 dscMinted, uint256 totalCollateralValue) = _getAccountInformation(_user);
        if ((dscMinted * LIQUIDATION_PRECISION) / LIQUIDATION_THRESHOLD > totalCollateralValue) {
            revert DSCEngine__MintedDSCExceedingThreshold();
        }
        uint256 healthFactor = _calcHealthFactor(dscMinted, totalCollateralValue);

        if (healthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__MinimumHealthFactorReached();
        }
    }

    // *** Public and External Functions *** //

    /**
     * 
     * @param _token Contract Address of the token to be restricted
     */
    function unallowToken(address _token) external {
        unallowedTokens.push(_token);
    }

    /**
     * 
     * @param _user address for the user who wants to get the account information
     * @return totalDSCMinted Total stable coins minted againsted deposited collateral
     * not necessarily 50% worth of collateral, it could be aything less than 50%.
     * @return totalCollateralValue Total collateral value in USD
     */
    function getAccountInformation(address _user)
        public
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValue)
    {
        return _getAccountInformation(_user);
    }

    /**
     * 
     * @param _token Address of the token which we no longer want to restrict
     * @notice there might be some cases where you want to ban a particular token from your protocol
     */
    function revertUnallowToken(address _token) external {
        bool matchFound = false; // Couldn have be  en with -1 starting value, but to avoid casting uint256 to int256.
        uint256 indexFoundAt = 0;
        uint256 numOfUnallowedTokens = unallowedTokens.length;
        for (uint256 i = 0; i < numOfUnallowedTokens; ++i) {
            if (_token == unallowedTokens[i]) {
                matchFound = true;
                indexFoundAt = i;
            }
        }
        if (matchFound) {
            unallowedTokens[indexFoundAt] = unallowedTokens[numOfUnallowedTokens - 1];
            unallowedTokens.pop();
        }
    }

    function burnDSC(uint256 _amount) public moreThanZero(_amount) {
        _burnDSC(msg.sender, msg.sender, _amount);
        _revertIfHealthFactorisBroken(msg.sender);
    }

    /**
     * @param _collateralToken address for wEth or wBTC
     * @param _collateralAmount 200% worth of mintable DSCs, 18 decimal value 
     */
    function depositCollateral(address _collateralToken, uint256 _collateralAmount)
        public
        moreThanZero(_collateralAmount)
        isCollateralAddress(_collateralToken)
        nonReentrant
    {
        collateralDeposited[msg.sender][_collateralToken] += _collateralAmount;
        emit DSCEngine__CollateralDeposited(msg.sender, _collateralToken, _collateralAmount);

        bool success = IERC20(_collateralToken).transferFrom(msg.sender, address(this), _collateralAmount);
        if (success == false) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param _collateralToken address for wEth or wBTC
     * @param _collateralAmount 150% worth of collateral of mintable DSCs
     * @param _mintAmount Amount DSC to be minted, Should be less than mintable threshold
     */
    function depositCollateralAndMintDSC(address _collateralToken, uint256 _collateralAmount, uint256 _mintAmount)
        external
    {
        depositCollateral(_collateralToken, _collateralAmount);
        mintDsc(_mintAmount);
    }

    function liquidate(address _collateralToken, address _user, uint256 _debtToCover) external {
        uint256 startingHealthFactor = _healthFactor(msg.sender);
        if (startingHealthFactor >= MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = _getTokenAmountFromUSD(_collateralToken, _debtToCover);
        uint256 liquidatorBonus = (tokenAmountFromDebtCovered * LIQUIDATOR_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + liquidatorBonus;
        _redeemCollateral(_user, msg.sender, _collateralToken, totalCollateralToRedeem);
        _burnDSC(_user, msg.sender, totalCollateralToRedeem);

        uint256 endingHealthFactor = _healthFactor(msg.sender);
        if (endingHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorisBroken(msg.sender);
    } 

    /**
     * @param _amount less 75% of the amount of deposited collateral
     */
    function mintDsc(uint256 _amount) public moreThanZero(_amount) nonReentrant {
        DSCMinted[msg.sender] += _amount;

        // It will revert only if health factor is less than MINIMUM_HEALTH_FACTOR
        _revertIfHealthFactorisBroken(msg.sender);

        bool minted = DSC.mint(msg.sender, _amount);
        if (minted == false) {
            revert DSCEngine__MintingFailed();
        }
    }

    function redeemCollateral(address _collateralToken, uint256 _collateralAmount)
        public
        moreThanZero(_collateralAmount)
        isCollateralAddress(_collateralToken)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, _collateralToken, _collateralAmount);
        _revertIfHealthFactorisBroken(msg.sender);
    }

    function redeemCollateralForDsc(address _collateralToken, uint256 _collateralAmount, uint256 _dscToBurn) external {
        burnDSC(_dscToBurn);
        redeemCollateral(_collateralToken, _collateralAmount);
    }

    // *** Public Getters *** //

    function getDSCMinted(address _user) public view returns (uint256) {
        return DSCMinted[_user];
    }

    function getCollateralDepositedFor(address _user, address _token) public view returns (uint256) {
        return collateralDeposited[_user][_token];
    }

    function getHealthFactor(address _user) public view returns (uint256) {
        return _healthFactor(_user);
    }

    function getFeedFromCollateralToken(address _collateralToken) public view returns (address) {
        return priceFeed[_collateralToken];
    }

    function getTotalCollateralValue(address _user) public view returns (uint256) {
        return _getTotalCollateralValue(_user);
    }

    function getCollateralValue(address _user, address _collateralToken) public view returns (uint256) {
        return _getCollateralValue(_user, _collateralToken);
    }

    function getTokenAmountFromUSD(address _collateralToken, uint256 _usdAmount) public view returns (uint256) {
        return _getTokenAmountFromUSD(_collateralToken, _usdAmount);
    }

    function getTokenValue(address _token, uint256 _amount) public view returns (uint256) {
        return _getTokenValue(_token, _amount);
    }

}
