# Cod3x CDP stablecoin

NOTE: This repository started as a fork of [Ethos 2.1](https://github.com/Byte-Masons/Ethos-V2-contracts)

## Collateral

In Cod3x CDP, collaterals are ERC4626 vault tokens. Cod3x CDP does not rehypothecate from the Active Pool; instead, rehypothecation occurs within the vault. This approach allows for maximum capital efficiency and abstracts the rehypothecation logic away from the stablecoin protocol.

## Oracle

The PriceFeed contract is a contract that encapsulates interactions with oracles, with error handling implemented. In Cod3x CDP, the PriceFeed will refer to a Chainlink-like (push) oracle as a primary source and [Tellor](https://tellor.io) as a backup, with added checks against vault share manipulation.
