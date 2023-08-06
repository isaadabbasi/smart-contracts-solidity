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
    uint256 private constant FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATOR_BONUS = 10;

    // *** State Variables *** //
    mapping(address user => mapping(address token => uint256 balance)) private collateralDeposited;
    mapping(address user => uint256 DSCMinted) private DSCMinted;
    mapping(address token => address priceFeed) private priceFeed;
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

            uint256 valueInUSD = getTokenValue(token, amount);
            totalValueInUSD += valueInUSD;
        }
        return totalValueInUSD;
    }

    function getTokenAmountFromUSD(address _collateralToken, uint256 _usdAmountInWei) private view returns (uint256) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(priceFeed[_collateralToken]);
        (, int256 price,,,) = aggregator.latestRoundData();

        return (_usdAmountInWei * PRECISION) / (uint256(price) * FEED_PRECISION);
    }

    /**
     * @param _token wBTC, wEth Contract Addresses
     * @param _amount Amount of BTC or ETH deposited (18 decimal)
     * @notice Returns the value of the token in USD
     */
    function getTokenValue(address _token, uint256 _amount) public view returns (uint256) {
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

    function _redeemCollateral(address _from, address _to, address _tokenCollateral, uint256 _amountCollateral)
        private
        moreThanZero(_amountCollateral)
    {
        // ? - What if requested _amountCollateral is more than the deposited collateral?
        collateralDeposited[_from][_tokenCollateral] -= _amountCollateral;
        emit DSCEngine__CollateralRedeemed(_from, _to, _tokenCollateral, _amountCollateral);

        bool success = IERC20(_tokenCollateral).transfer(_to, _amountCollateral);
        if (success == false) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _revertIfHealthFactorisBroken(address _user) internal view {
        uint256 healthFactor = _healthFactor(_user);
        if (healthFactor < MINIMUM_HEALTH_FACTOR) {
            // TODO - Should it be <= or <
            revert DSCEngine__MinimumHealthFactorReached();
        }
    }

    // *** Public and External Functions *** //

    function unallowToken(address _token) external {
        unallowedTokens.push(_token);
    }

    function revertUnallowToken(address _token) external {
        bool matchFound = false; // Couldn have been with -1 starting value, but to avoid casting uint256 to int256.
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
     * @param _collateralAmount 150% worth of collateral of mintable DSCs
     */
    function depositCollateral(address _collateralToken, uint256 _collateralAmount)
        public
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

    function getHealthFactor(address _user) external view {}

    function liquidate(address _collateralToken, address _user, uint256 _debtToCover) external {
        uint256 startingHealthFactor = _healthFactor(msg.sender);
        if (startingHealthFactor >= MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(_collateralToken, _debtToCover);
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

    function redeemCollateral(address _tokenCollateral, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isTokenAllowed(_tokenCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, _tokenCollateral, _amountCollateral);
        _revertIfHealthFactorisBroken(msg.sender);
    }

    function redeemCollateralForDsc(address _tokenCollateral, uint256 _amountCollateral, uint256 _dscToBurn) external {
        burnDSC(_dscToBurn);
        redeemCollateral(_tokenCollateral, _amountCollateral);
    }
}
