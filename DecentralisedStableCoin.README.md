
# Decentralised Stable Coin

  
### About contract

Decenstralised Stable Coin (DSC) is a relative stability, USD pegged algorithmic stable coin contract that is governed by DSCEngine.

### Technical

DSCs can be minted by providing over 200% value of collateral. which means, to mint $1000 in DSCs user will have to deposit $2000 worth of collateral. In case of devaluation of collateral, the minter will be liquidated by returning the deposit and burning their minted DSCs which makes the platform algorithmic. 

Based on ERC20 standard. It is similar to DAI if DAI had no governance, no fees and backed by wEth and wBTC.
* It will always be over-collateralised with roughly 140% of liquidation boundry
* If the collateral worth reached the liquidation boundry, it will be liquidated.
* It handles the logic for mining, depositing, and redeeming of collateral.

### External Contracts/Services Used: 

- Oppenzeppelin for ERCs
- Chainlink Brownie Contracts for Price Feeds
  
### Known bugs
- Liquidate logic is not fully tested. 
- If the price dips way too quickly then protocol may crash, (Added a halt check for PriceFeedConsumers)

### More
This repository contains:
- Unit Tests 
- Fuzz Tests
- DeployScripts
- and General Best Practices. 