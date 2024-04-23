import { run, network } from "hardhat";
import { isNullOrWhitespace } from "../string";

const verificationDisabledNetworks: ReadonlySet<string> = new Set<string>([
  "hardhat",
  "local",
]);

export class Verifier {
  private readonly etherscanURL: string;

  constructor(etherscanURL: string) {
    if (isNullOrWhitespace(etherscanURL)) {
      throw Error("etherscan URL cannot be an empty string");
    }
    this.etherscanURL = etherscanURL;
  }

  public async verifyAddress(
    address: string,
    constructorArguments: ReadonlyArray<any> = [],
  ): Promise<string> {
    if (verificationDisabledNetworks.has(network.name)) {
      console.log(`skipping contract verification for network name 'hardhat'`);
      return "VERIFICATION_SKIPPED";
    }
    try {
      console.log(`verifying address: '${address}'`);

      await run("verify:verify", {
        address: address,
        constructorArguments: constructorArguments,
      });
    } catch (error) {
      console.error(
        `error verifying contract on address: '${address}'. Error: '${error}'`,
      );
      throw error;
    }

    return `${this.etherscanURL}/${address}#code`;
  }
}
