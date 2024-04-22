import { promises as fs, constants } from "fs";
import * as path from "path";
import { isNullOrWhitespace } from "../string";
import { Transaction } from "./types";

export class State {
  private readonly filePath: string;

  constructor(filePath: string) {
    if (isNullOrWhitespace(filePath)) {
      throw Error("file path cannot be an empty string");
    }
    this.filePath = filePath;
  }

  public async load(): Promise<Map<string, Transaction>> {
    console.log(
      `loading previous deployment from location: '${this.filePath}'`,
    );
    const fileExists = await this.fileExists();
    if (!fileExists) {
      console.log(
        `previous deployment state file does not exist. Returning empty state object`,
      );
      return new Map<string, Transaction>();
    }

    try {
      const data = JSON.parse(
        await fs.readFile(this.filePath, { encoding: "utf8" }),
      );
      const stateMap = new Map<string, Transaction>(Object.entries(data));

      return stateMap;
    } catch (error) {
      console.error("failed to read file:", error);
      throw error;
    }
  }

  public async save(state: ReadonlyMap<string, Transaction>): Promise<void> {
    try {
      const stateAsJson = JSON.stringify(Object.fromEntries(state), null, 2);
      console.log(
        `saving object state object. Number of objects in the state: ${state.size}`,
      );

      const dirname = path.dirname(this.filePath);
      await fs.mkdir(dirname, { recursive: true });

      await fs.writeFile(this.filePath, stateAsJson);
      console.log(
        `successfully saved state file in location: '${this.filePath}'`,
      );
    } catch (error) {
      console.error("failed to write to file:", error);
      throw error;
    }
  }

  private async fileExists(): Promise<boolean> {
    try {
      await fs.access(this.filePath, constants.F_OK);
      return true;
    } catch {
      return false;
    }
  }
}
