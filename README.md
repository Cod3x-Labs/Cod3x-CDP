# Cod3x CDP stablecoin

NOTE: This repository started as a fork of [Ethos 2.1](https://github.com/Byte-Masons/Ethos-V2-contracts)

## Collateral

In Cod3x CDP, collaterals are ERC4626 vault tokens. Cod3x CDP does not rehypothecate from the Active Pool; instead, rehypothecation occurs within the vault. This approach allows for maximum capital efficiency and abstracts the rehypothecation logic away from the stablecoin protocol.

## Oracle

The PriceFeed contract is a contract that encapsulates interactions with oracles, with error handling implemented. In Cod3x CDP, the PriceFeed will refer to a Chainlink-like (push) oracle as a primary source and [Tellor](https://tellor.io) as a backup, with added checks against vault share manipulation.

## Testing

Testing and deploying should be done from the `src/` directory, and all commands/paths given will assume that is your working directory.
You will need to fill in the value for `ETHERSCAN_API_KEY` in the `.env` file before running tests.
The majority of unit tests are written for the hardhat framework. To run these tests, execute `npx hardhat test --config hardhat.config.test.ts`.
There are also Foundry tests for the BorrowerHelper and Leverager contracts, as well as a test for simulating a fork and upgrade of the contracts (making the iUSD token on Mode point to a new deployment using the contracts in this project). These can be run simply with `forge test`.

## Deploying

You will need to fill in the values for `ETHERSCAN_API_KEY` and `DEPLOYER_PRIVATE_KEY` in `.env` before deploying. You may also need to make changes to `hardhat.config.ts` to add support for the chain and block explorer you are deploying to. You will also need to configure a file in `scripts/parameters` for the chain you are deploying to (if you are using a chain other than Mode, you will need to edit the `configurationParameters` import line in the deploy and initialize scripts). You can begin deploying by running `npx hardhat run scripts/deploy.ts --network <CHAIN_NAME>`. After deploying each contract, state is saved to `scripts/state/<CHAIN_NAME>.js`. This means that if any contracts failed to deploy, you can continue where you left off by running the same command. All contracts will not deploy on the first run because `LUSDToken.sol` and `MultiTroveGetter.sol` take addresses of other deployed contracts as constructor arguments, so you will need to update the js file in `scripts/parameters` with those after the first run. After all 20 contracts are deployed, you will need to initialize them by running `npx hardhat run scripts/initialize.ts --network <CHAIN_NAME>`. This script should also continue where it left off in case of failure.
