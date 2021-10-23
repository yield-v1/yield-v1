import {config as dotEnvConfig} from "dotenv";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-solhint";
import '@openzeppelin/hardhat-upgrades';
import "@typechain/hardhat";
import "hardhat-docgen";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import "hardhat-tracer";
import "hardhat-etherscan-abi";
import "solidity-coverage"
import "@tenderly/hardhat-tenderly"

dotEnvConfig();
// tslint:disable-next-line:no-var-requires
const argv = require('yargs/yargs')()
.env('TETU')
.options({
  maticRpcUrl: {
    type: "string",
  },
  infuraKey: {
    type: "string",
  },
  networkScanKey: {
    type: "string",
  },
  privateKey: {
    type: "string",
    default: "85bb5fa78d5c4ed1fde856e9d0d1fe19973d7a79ce9ed6c0358ee06a4550504e" // random account
  },
  forkBlock: {
    type: "number",
    default: 20432038
  },
}).argv;


export default {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      chainId: 137,
      timeout: 99999,
      forking: {
        url: argv.maticRpcUrl,
        blockNumber: argv.forkBlock
      },
      accounts: {
        mnemonic: "test test test test test test test test test test test junk",
        path: "m/44'/60'/0'/0",
        accountsBalance: "100000000000000000000000000000"
      },
    },
    matic: {
      url: argv.maticRpcUrl,
      timeout: 99999,
      chainId: 137,
      gas: 19_000_000,
      gasPrice: 35_000_000_000,
      // gasMultiplier: 2,
      accounts: [argv.privateKey],
    },
    mumbai: {
      url: "https://polygon-mumbai.infura.io/v3/" + argv.infuraKey,
      chainId: 80001,
      gasPrice: 1,
      accounts: [argv.privateKey],
    },
    ropsten: {
      url: "https://ropsten.infura.io/v3/" + argv.infuraKey,
      chainId: 3,
      gas: 8_000_000,
      accounts: [argv.privateKey],
    },
    rinkeby: {
      url: "https://rinkeby.infura.io/v3/" + argv.infuraKey,
      chainId: 4,
      gas: 8_000_000,
      gasPrice: 1_100_000_000,
      accounts: [argv.privateKey],
    },
  },
  etherscan: {
    apiKey: argv.networkScanKey
  },
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
    ]
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 9999999999
  },
  docgen: {
    path: './docs',
    clear: true,
    runOnCompile: true,
    except: ['contracts/third_party', 'contracts/test']
  },
  contractSizer: {
    alphaSort: false,
    runOnCompile: false,
    disambiguatePaths: false,
  },
  gasReporter: {
    enabled: false,
    currency: 'USD',
    gasPrice: 21
  },
  tenderly: {
    project: "https://dashboard.tenderly.co/tetu/tetu-contracts",
    username: "belbix",
  },
};
