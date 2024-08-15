import { ethers } from "hardhat";
import { BaseContract } from "ethers";

export class Deployer {
  private readonly txConfirmations: number;
  private readonly gasPrice: number;

  constructor(txConfirmations: number, gasPrice: number) {
    this.txConfirmations = txConfirmations;
    this.gasPrice = gasPrice;
  }

  public async deploy(
    name: string,
    ctorArguments: ReadonlyArray<any> = [],
  ): Promise<BaseContract> {
    console.log(
      `deploying ${name} contract with constructor arguments: ${ctorArguments}`,
    );

    const contractFactory = await ethers.getContractFactory(name);
    const contract = await contractFactory.deploy(...ctorArguments);

    const deploymentTransaction = contract.deploymentTransaction();
    if (deploymentTransaction == null) {
      throw new Error(
        `contract deployment transaction was null. Contract name: '${name}'`,
      );
    }

    console.log(
      `waiting for '${this.txConfirmations}' deployment transaction confirmations`,
    );

    const transaction = await deploymentTransaction.wait(this.txConfirmations);

    if (transaction == null) {
      throw new Error(
        `contract deployment transaction was null most likely due to '0' block confirmations. Contract name: '${name}'`,
      );
    }

    const address = await contract.getAddress();
    console.log(
      `contract with name: '${name}' was deployed to address: '${address}', transaction hash: '${transaction.hash}'`,
    );

    return contract as BaseContract;
  }
}
