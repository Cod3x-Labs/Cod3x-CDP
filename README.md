# Pluc RWA stablecoin

NOTE: This repository started as a fork of [Ethos 2.1](https://github.com/Byte-Masons/liquity-dev/tree/v2.1) -> [commit](https://github.com/Byte-Masons/pluc-stablecoin/commit/0b837a74bfbe03cf77ea16b90151f8291237c2d0)

## Collateral

Pluc collateral is an ERC20 Vault token. Since Pluc is a Real World Asset (RWA)-based protocol, the Vault's underlying tokens are RWA assets. Pluc does not rehypothecate from the Active Pool, instead, rehypothecation occurs within the Vault. This approach allows for maximum capital efficiency and abstracts the rehypothecation logic away from the Stablecoin protocol.

## Oracle

The Price Feed contract is a contract that encapsulates interactions with Oracles, with error handling implemented. In Pluc, the Price Feed will refer to the [Tellor](https://tellor.io) and [Chronicle Labs](https://chroniclelabs.org) oracles.
