import { ethers, network } from "hardhat";
import { State } from "../utils/deploy/state";
import { Deployer } from "../utils/deploy/deployer";
import { Verifier } from "../utils/deploy/verifier";
import { configurationParameters } from "./parameters/mode";

async function main() {
  const [signer] = await ethers.getSigners();

  console.log(
    `starting the deployment script, will deploy contracts to the network: '${network.name}', 
     with owner set to: '${signer.address}'`,
  );

  const state = new State(`./scripts/state/${network.name}.json`);
  const deployer = new Deployer(
    configurationParameters.txConfirmations,
    configurationParameters.gasPriceWei,
  );
  const verifier = new Verifier(configurationParameters.etherscanURL);
  const deploymentState = await state.load();

  for (const { name, ctorArguments } of configurationParameters.contracts) {
    if (deploymentState.has(name)) {
      console.log(
        `contract with name ${name} was already deployed. Skipping...`,
      );
      continue;
    }
    try {
      const contract = await deployer.deploy(name, ctorArguments);
      const contractAddress = await contract.getAddress();
      const verification = await verifier.verifyAddress(contractAddress, ctorArguments);

      deploymentState.set(name, {
        address: contractAddress,
        txHash: contract.deploymentTransaction()?.hash!,
        verification: verification,
      });
      await state.save(deploymentState);
    } catch (error) {
      let errorMessage: string = "";
      if (error instanceof Error) {
        errorMessage = error.message;
      }
      console.log(
        `error during deployment contract: '${name}'. Error: '${errorMessage}'. Continue...`,
      );
      continue;
    }
  }
}

main();
