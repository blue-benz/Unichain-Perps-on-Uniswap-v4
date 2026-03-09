export type Address = `0x${string}`;

export type DeploymentManifest = {
  chainId: number;
  chainName: string;
  perpsEngine: Address;
  perpsHook: Address;
  collateralVault: Address;
  riskManager: Address;
  liquidationModule: Address;
  poolManager: Address;
  marketId: `0x${string}`;
};

export const placeholderUnichainDeployment: DeploymentManifest = {
  chainId: 0,
  chainName: "Unichain (TBD)",
  perpsEngine: "0x0000000000000000000000000000000000000000",
  perpsHook: "0x0000000000000000000000000000000000000000",
  collateralVault: "0x0000000000000000000000000000000000000000",
  riskManager: "0x0000000000000000000000000000000000000000",
  liquidationModule: "0x0000000000000000000000000000000000000000",
  poolManager: "0x0000000000000000000000000000000000000000",
  marketId: "0x0000000000000000000000000000000000000000000000000000000000000000"
};
