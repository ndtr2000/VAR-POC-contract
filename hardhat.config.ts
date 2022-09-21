import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-truffle5";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-solhint";
import "@nomiclabs/hardhat-etherscan";
import "@openzeppelin/hardhat-upgrades";
import "@typechain/hardhat";
import "@nomicfoundation/hardhat-toolbox";

import { HardhatUserConfig } from "hardhat/types";
import "hardhat-docgen";

require("dotenv").config();

const config: HardhatUserConfig = {
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            accounts: { count: 100 },
        },
        rinkeby: {
            url: `https://rinkeby.infura.io/v3/${process.env.INFURA_API_KEY}`,
            accounts: [`${process.env.PRIVATE_KEY}`],
        },
        goerli: {
            url: `https://goerli.infura.io/v3/${process.env.INFURA_API_KEY}`,
            accounts: [`${process.env.PRIVATE_KEY}`],
        },
        // mainnet: {
        //     url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
        //     accounts: [`${process.env.PRIVATE_KEY}`]
        // }

        mumbai: {
            url: `https://matic-mumbai.chainstacklabs.com/`,
            accounts: [`${process.env.PRIVATE_KEY}`],
        },
        bsctestnet: {
            url: `https://data-seed-prebsc-1-s1.binance.org:8545/`,
            accounts: [`${process.env.PRIVATE_KEY}`],
        },
    },
    etherscan: {
        apiKey: `${process.env.ETHERSCAN_KEY}`,
    },
    solidity: {
        compilers: [
            {
                version: "0.8.9",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    paths: {
        sources: "./contracts",
        tests: "./tests",
        cache: "./cache",
        artifacts: "./artifacts",
    },
    mocha: {
        timeout: 200000,
        reporter: "mocha-multi-reporters",
        reporterOptions: {
            configFile: "./mocha-report.json",
        },
    },
    docgen: {
        path: "./docs",
        clear: true,
        runOnCompile: false,
    },
    typechain: {
        outDir: "typechain-types",
        target: "ethers-v5",
    },
};

module.exports = config;