# Lottery Contract

### About contract
Raffle is a lottery contest which anyone can join on the expenses of X amount of eth. The contract is called by a Schedular after scheduled time N and checks if there are enough people in the pool then it rolls the dice and pick a winner. 

Anyone can join multiple times (whether in the same turn or later) which increases the chances of win but every time they join they must spend X amount of Eth. 

### Technical 
User's joins by spending X amount of Eth. After N time, the schedular calls a function to pick the winner. 
Smart contracts are unable to either schedule ticks or generate random numbers; for that, we will have to utilise ChainLink's Automation and VRF.

### Motivation
Recalling the solidity language, To learn the deployment, testing and mocking of units. 
To get better hold of best practices for code practice, design patterns, dir structuring and application flow.
Putting 1 more start to my full stack profile. (⭐️⭐️⭐️⭐️⭐️)

I am not new to unit or intergration tests, some tests are intentionally not written.

### Legends
- X = entrance fees = 0.1 Eth default, configurable.
- T = interval after which dice is rolled = 30 mins default, configurable.
