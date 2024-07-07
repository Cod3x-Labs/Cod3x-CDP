import { ethers, network } from "hardhat";
import { State } from "../utils/deploy/state";
import { Initializer } from "../utils/initialize/initializer";
import { configurationParameters } from "./parameters/hardhat";
import { ContractName } from "../utils/deploy/types";

async function main() {
  const [signer] = await ethers.getSigners();

  console.log(
    `starting the initialization script, will initialize contracts at the network: '${network.name}', 
     with owner set to: '${signer.address}'`,
  );

  const state = new State(`./scripts/state/${network.name}.json`);
  const contractTransactions = await state.load();

  console.log(
    `state is loaded. Number of items in the state: ${contractTransactions.size}`,
  );

  if (contractTransactions.size != configurationParameters.contracts.length) {
    throw new Error(
      `all contracts must be deployed before initialization. 
      Number of contracts: ${configurationParameters.contracts.length}.
      Number of deployed contracts: ${contractTransactions.size}`,
    );
  }
  const initializer: Initializer = new Initializer(
    configurationParameters.gasPriceWei,
    configurationParameters.txConfirmations,
  );

  const contractsMap = new Map<ContractName, string>();
  for (const [name, transaction] of contractTransactions) {
    contractsMap.set(name as ContractName, transaction.address);
  }
  const connectedContracts = await initializer.connect(signer, contractsMap);

  await initializer.initialize(
    connectedContracts,
    configurationParameters.collaterals,
    configurationParameters.internalAddresses.GOVERNANCE,
    configurationParameters.internalAddresses.GUARDIAN,
    configurationParameters.internalAddresses.OATH,
    configurationParameters.internalAddresses.TREASURY,
    configurationParameters.externalAddresses.SWAPPER,
    configurationParameters.externalAddresses.VELO_ROUTER,
    configurationParameters.externalAddresses.BALANCER_VAULT,
    configurationParameters.externalAddresses.UNI_V3_ROUTER,
  );
}

main();
