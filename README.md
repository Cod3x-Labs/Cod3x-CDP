# Solidity template

## Template frameworks

This template utilizes set of various frameworks:

- **Hardhat** with **TypeScript** for compilation, deployments and tests
- **Forge** for tests (it is possible to write tests with both Hardhat and Forge)
- **NPM** used as a package manager
- **GitHub Action** are used for CI/CD pipelines
- **Solhint** and its integration with **Prettier** (`npm run lint` with trigger both **Solhint** and **Prettier** runs)

## How to use it

Certainly, here's your README text with improved grammar and clarity:

- Create a new GitHub project using this template.
- Navigate to the `src` folder and run `npm install`.

- All commands, both for Hardhat and Forge, are encapsulated via NPM. For example, running `npm run test` will execute both `hardhat test` and `forge tests` commands. This means you should avoid running Hardhat or Forge commands directly. If you find it necessary to update the commands, please modify the `package.json` with the new set of commands. To view the available scripts, refer to the `package.json` file.

- The `/test` directory may contain both Forge and Hardhat types of tests.

- The `/utils` directory currently contains a generic TypeScript script that can be used for deploying various Smart Contracts. An example of usage can be found in `main.ts` under the `/scripts` directory.

- The `/.github` directory contains both workflow definitions for GitHub Actions and a `dependabot.yml` file with configuration for Dependabot, which automatically opens pull requests to keep your project's dependencies up to date.
