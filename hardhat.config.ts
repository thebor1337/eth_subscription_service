import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import '@primitivefi/hardhat-dodoc';

const config: HardhatUserConfig = {
  solidity: "0.8.19",
  dodoc: {
    runOnCompile: true,
    debugMode: false,
  },
};

export default config;
